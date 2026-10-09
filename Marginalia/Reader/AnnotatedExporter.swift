import CoreText
import Foundation
import PDFKit
import PencilKit
import UIKit

/// Writes a copy of a document with every annotation *drawn into the page content* ("flattened"),
/// the way a printed, marked-up page looks.
///
/// Why flatten instead of adding PDF annotation objects: PDFKit writes annotations without
/// appearance streams, so most non-Apple viewers (Android, Windows, Linux, pdf.js) don't show
/// them at all — and some viewers crash on them. Page content renders everywhere.
///
/// - Highlights, underlines, strikes and Pencil ink are drawn as vector graphics over the page.
/// - Flags get a margin glyph; note text is written in the margin beside its passage (or on a small
///   card under the passage when the margin is too narrow). Nothing moves to other pages.
/// - The original page content is drawn as vectors, so text stays selectable and searchable.
///   Links and the outline are not carried over.
nonisolated enum AnnotatedExporter {
    struct Input: Sendable {
        var sourceURL: URL
        var destinationURL: URL
        var title: String = ""
        var marks: [Highlight]
        var inkByPage: [Int: Data]
    }

    enum ExportError: LocalizedError {
        case unreadable, writeFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: "The original PDF couldn’t be read."
            case .writeFailed: "The annotated PDF couldn’t be written."
            }
        }
    }

    // Graphite marks on paper; multiply blending keeps the text underneath crisp.
    static let highlightFill = UIColor(white: 0.80, alpha: 1)
    static let lineInk = UIColor(white: 0.15, alpha: 1)
    static let markerInk = UIColor(white: 0.20, alpha: 1)

    static func export(_ input: Input) throws {
        guard let source = CGPDFDocument(input.sourceURL as CFURL) else { throw ExportError.unreadable }
        if source.isEncrypted { _ = source.unlockWithPassword("") }

        // Marks top-down within each page, so margin notes stack in reading order.
        let marks = input.marks.sorted { a, b in
            a.page != b.page ? a.page < b.page : (a.rects.first?.maxY ?? 0) > (b.rects.first?.maxY ?? 0)
        }
        let marksByPage = Dictionary(grouping: marks, by: \.page)

        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { throw ExportError.writeFailed }
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let info: [CFString: Any] = [kCGPDFContextTitle: input.title, kCGPDFContextCreator: "Marginalia"]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &defaultBox, info as CFDictionary) else {
            throw ExportError.writeFailed
        }

        for index in 0..<source.numberOfPages {
            guard let page = source.page(at: index + 1) else { continue }   // CGPDF pages are 1-based
            let crop = page.getBoxRect(.cropBox)
            let rotated = page.rotationAngle % 180 != 0
            let size = rotated ? CGSize(width: crop.height, height: crop.width) : crop.size
            var media = CGRect(origin: .zero, size: size)
            ctx.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &media, count: MemoryLayout<CGRect>.size)] as CFDictionary)

            // Map page space (with its /Rotate) onto the output page; everything below draws in
            // the same page space the reader stores annotations in.
            ctx.saveGState()
            ctx.concatenate(page.getDrawingTransform(.cropBox, rect: media, rotate: 0, preserveAspectRatio: true))
            ctx.clip(to: crop)
            ctx.drawPDFPage(page)

            var margins = MarginLayout(pageBox: crop)
            for mark in marksByPage[index] ?? [] {
                draw(mark, in: ctx, pageBox: crop)
            }
            // Notes after all marks, so note cards sit above highlights.
            for mark in marksByPage[index] ?? [] where mark.hasNote {
                drawNote(for: mark, in: ctx, layout: &margins)
            }
            if let data = input.inkByPage[index], let drawing = try? PKDrawing(data: data) {
                draw(drawing, in: ctx, pageBox: crop)
            }
            ctx.restoreGState()
            ctx.endPDFPage()
        }

        ctx.closePDF()

        // Atomic write: re-saving replaces the previous export in one step.
        try (output as Data).write(to: input.destinationURL, options: .atomic)
    }

    // MARK: Text marks

    private static func draw(_ mark: Highlight, in ctx: CGContext, pageBox: CGRect) {
        ctx.saveGState()
        for rect in mark.rects {
            switch mark.style {
            case .highlight:
                ctx.setBlendMode(.multiply)
                ctx.setFillColor(highlightFill.cgColor)
                ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: -1, dy: 0), cornerWidth: 2, cornerHeight: 2, transform: nil))
                ctx.fillPath()
            case .underline, .strikethrough:
                let y = mark.style == .underline ? rect.minY + 0.6 : rect.midY
                ctx.setBlendMode(.normal)
                ctx.setStrokeColor(lineInk.cgColor)
                ctx.setLineWidth(max(0.8, rect.height * 0.07))
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                ctx.strokePath()
            }
        }
        ctx.restoreGState()

        // Flag glyph just left of the first line.
        guard let first = mark.rects.first, let flag = mark.flag else { return }
        let label = flag == .question ? "?" : "→"
        let font = UIFont.systemFont(ofSize: max(7, min(11, first.height * 0.75)), weight: .bold)
        let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: markerInk])
        let width = text.size().width
        let x = max(pageBox.minX + 2, first.minX - width - 8)
        drawText(text, at: CGPoint(x: x, y: first.midY - font.capHeight / 2), in: ctx)
    }

    // MARK: Ink

    /// Drawings are stored in page points with a y-down origin at the top-left of the crop box.
    private static func draw(_ drawing: PKDrawing, in ctx: CGContext, pageBox: CGRect) {
        for stroke in drawing.strokes {
            let points = stroke.path.interpolatedPoints(by: .distance(1)).map { point -> CGPoint in
                let p = point.location.applying(stroke.transform)
                return CGPoint(x: pageBox.minX + p.x, y: pageBox.maxY - p.y)
            }
            guard let first = points.first else { continue }

            let isMarker = stroke.ink.inkType == .marker
            let color = stroke.ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            ctx.saveGState()
            ctx.setBlendMode(isMarker ? .multiply : .normal)
            ctx.setStrokeColor(color.withAlphaComponent(isMarker ? 0.45 : 1).cgColor)
            ctx.setLineWidth(strokeWidth(stroke))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: first)
            for point in points.dropFirst() { ctx.addLine(to: point) }
            if points.count == 1 { ctx.addLine(to: CGPoint(x: first.x + 0.1, y: first.y)) }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    private static func strokeWidth(_ stroke: PKStroke) -> CGFloat {
        let widths = stroke.path.map(\.size.width)
        guard !widths.isEmpty else { return 2 }
        return max(0.5, widths.reduce(0, +) / CGFloat(widths.count))
    }

    // MARK: Margin notes

    static let noteFont = UIFont.systemFont(ofSize: 7.5)
    static let noteInk = UIColor(white: 0.22, alpha: 1)

    /// Tracks how far down each margin is already filled on a page, so nearby notes stack
    /// instead of overlapping. Coordinates are y-up page space.
    struct MarginLayout {
        let pageBox: CGRect
        var leftFloor: CGFloat
        var rightFloor: CGFloat

        init(pageBox: CGRect) {
            self.pageBox = pageBox
            leftFloor = pageBox.maxY
            rightFloor = pageBox.maxY
        }
    }

    /// Writes the note beside its passage: in the wider side margin when there's room, otherwise
    /// on a small card directly under the passage.
    private static func drawNote(for mark: Highlight, in ctx: CGContext, layout: inout MarginLayout) {
        guard let note = mark.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty,
              let first = mark.rects.first, let last = mark.rects.last else { return }
        let box = layout.pageBox
        let text = NSAttributedString(string: note, attributes: [.font: noteFont, .foregroundColor: noteInk])
        let setter = CTFramesetterCreateWithAttributedString(text)

        let textLeft = mark.rects.map(\.minX).min() ?? first.minX
        let textRight = mark.rects.map(\.maxX).max() ?? first.maxX
        let leftSpace = textLeft - box.minX - 14
        let rightSpace = box.maxX - textRight - 14
        let useRight = rightSpace >= leftSpace
        let columnWidth = min(useRight ? rightSpace : leftSpace, 150)

        if columnWidth >= 58 {
            // Margin column: top aligned with the passage, pushed down below earlier notes.
            let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
                setter, CFRange(), nil, CGSize(width: columnWidth, height: .greatestFiniteMagnitude), nil)
            let floor = useRight ? layout.rightFloor : layout.leftFloor
            let top = min(first.maxY, floor - 4)
            let height = min(fitted.height + 1, top - box.minY - 6)
            guard height > 6 else { return }
            let x = useRight ? textRight + 12 : textLeft - 12 - columnWidth
            let rect = CGRect(x: x, y: top - height, width: columnWidth, height: height)

            // A thin rule ties the note to its passage, like a pencilled margin note.
            ctx.saveGState()
            ctx.setStrokeColor(noteInk.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(0.6)
            let ruleX = useRight ? rect.minX - 4 : rect.maxX + 4
            ctx.move(to: CGPoint(x: ruleX, y: rect.maxY))
            ctx.addLine(to: CGPoint(x: ruleX, y: rect.minY))
            ctx.strokePath()
            ctx.restoreGState()

            drawFrame(setter, in: rect, ctx: ctx)
            if useRight { layout.rightFloor = rect.minY } else { layout.leftFloor = rect.minY }
        } else {
            // Narrow margins: a small card right under the passage.
            let width = min(240, box.width - 40)
            let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
                setter, CFRange(), nil, CGSize(width: width - 12, height: .greatestFiniteMagnitude), nil)
            let height = min(fitted.height + 10, 160)
            let x = min(max(box.minX + 8, textLeft), box.maxX - width - 8)
            let y = max(box.minY + 8, last.minY - 4 - height)
            let card = CGRect(x: x, y: y, width: width, height: height)

            ctx.saveGState()
            ctx.setFillColor(UIColor(white: 0.97, alpha: 0.96).cgColor)
            ctx.setStrokeColor(UIColor(white: 0.55, alpha: 1).cgColor)
            ctx.setLineWidth(0.6)
            let path = CGPath(roundedRect: card, cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.addPath(path)
            ctx.drawPath(using: .fillStroke)
            ctx.restoreGState()
            drawFrame(setter, in: card.insetBy(dx: 6, dy: 5), ctx: ctx)
        }
    }

    private static func drawFrame(_ setter: CTFramesetter, in rect: CGRect, ctx: CGContext) {
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: rect, transform: nil), nil)
        ctx.saveGState()
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    /// Draws a single line of text with its baseline-ish origin at `point` in y-up page space.
    private static func drawText(_ text: NSAttributedString, at point: CGPoint, in ctx: CGContext) {
        let line = CTLineCreateWithAttributedString(text)
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = point
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: File naming

    /// A Files-safe name derived from the title.
    static func fileName(for title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(120))
        return base + ".pdf"
    }

    /// First free name in the folder: "Title.pdf", "Title 2.pdf", …
    static func uniqueFileName(for title: String, in folder: URL) -> String {
        let name = fileName(for: title)
        let base = String(name.dropLast(4))
        var candidate = name
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: candidate).path) {
            candidate = "\(base) \(n).pdf"
            n += 1
        }
        return candidate
    }
}
