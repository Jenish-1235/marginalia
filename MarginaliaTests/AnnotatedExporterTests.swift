import Foundation
import PDFKit
import PencilKit
import Testing
import UIKit
@testable import Marginalia

@MainActor
struct AnnotatedExporterTests {
    let folder: URL

    init() throws {
        folder = URL.temporaryDirectory.appending(path: "export-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// A one-page PDF with a line of real text near the top.
    private func makeSourcePDF() throws -> URL {
        let url = folder.appending(path: "source.pdf")
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            ("Attention is all you need" as NSString).draw(
                at: CGPoint(x: 72, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
        try data.write(to: url)
        return url
    }

    /// A thick red horizontal stroke at y = 300 (top-down), x 80…270.
    private func redStroke() -> Data {
        let points = (0..<20).map { i in
            PKStrokePoint(location: CGPoint(x: 80 + Double(i) * 10, y: 300), timeOffset: Double(i) * 0.01,
                          size: CGSize(width: 6, height: 6), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        return PKDrawing(strokes: [stroke]).dataRepresentation()
    }

    /// Renders page *content only* — what a viewer with no annotation support shows.
    private func renderContent(of url: URL, page: Int = 1) throws -> (CGContext, CGRect) {
        let doc = try #require(CGPDFDocument(url as CFURL))
        let pdfPage = try #require(doc.page(at: page))
        let box = pdfPage.getBoxRect(.mediaBox)
        let ctx = try #require(CGContext(data: nil, width: Int(box.width), height: Int(box.height), bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(box)
        ctx.drawPDFPage(pdfPage)
        return (ctx, box)
    }

    /// RGB at a point in PDF (y-up) coordinates.
    private func pixel(_ ctx: CGContext, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let row = ctx.height - 1 - y
        let offset = row * ctx.bytesPerRow + x * 4
        return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
    }

    @Test func flattensMarksIntoPageContent() throws {
        let source = try makeSourcePDF()
        let destination = folder.appending(path: "out.pdf")
        // Highlight in empty space so the pixel check isn't affected by glyphs.
        let mark = Highlight(id: "h", documentID: "d", page: 0, style: .highlight, flag: .question,
                             rects: [CGRect(x: 72, y: 400, width: 170, height: 16)], text: "Attention",
                             note: "Why does this work?", createdAt: Date(), updatedAt: Date())

        try AnnotatedExporter.export(.init(sourceURL: source, destinationURL: destination, title: "Test",
                                           marks: [mark], inkByPage: [0: redStroke()]))

        let exported = try #require(PDFDocument(url: destination))
        // No annotation objects at all — nothing a viewer could skip or choke on.
        #expect(exported.page(at: 0)!.annotations.isEmpty)
        // Original text is still real, selectable text.
        #expect(exported.page(at: 0)!.string?.contains("Attention is all you need") == true)
        // The note is written on the same page, beside its passage — no extra pages.
        #expect(exported.pageCount == 1)
        #expect(exported.page(at: 0)!.string?.contains("Why does this work?") == true)

        // The marks are visible in the page content itself.
        let (ctx, box) = try renderContent(of: destination)
        let highlight = pixel(ctx, x: 150, y: 408)
        #expect(highlight.r < 235 && highlight.r > 150 && abs(highlight.r - highlight.b) < 10, "graphite highlight")
        let ink = pixel(ctx, x: 170, y: Int(box.height) - 300)
        #expect(ink.r > 150 && ink.g < 90 && ink.b < 90, "red ink stroke")
        let blank = pixel(ctx, x: 500, y: 200)
        #expect(blank.r > 250 && blank.g > 250 && blank.b > 250, "untouched paper stays white")
    }

    @Test func resavingOverwritesTheSameFile() throws {
        let source = try makeSourcePDF()
        let destination = folder.appending(path: "Doc.pdf")
        try AnnotatedExporter.export(.init(sourceURL: source, destinationURL: destination,
                                           marks: [], inkByPage: [0: redStroke()]))
        try AnnotatedExporter.export(.init(sourceURL: source, destinationURL: destination, marks: [], inkByPage: [:]))

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0 != "source.pdf" }
        #expect(files == ["Doc.pdf"])
        let (ctx, box) = try renderContent(of: destination)
        let whereInkWas = pixel(ctx, x: 170, y: Int(box.height) - 300)
        #expect(whereInkWas.r > 250 && whereInkWas.g > 250, "second save has no ink, so it replaced the first")
    }

    @Test func fileNamesAreSafeAndUnique() throws {
        #expect(AnnotatedExporter.fileName(for: "Attention: Is All/You Need") == "Attention- Is All-You Need.pdf")
        #expect(AnnotatedExporter.fileName(for: "   ") == "Untitled.pdf")
        try Data().write(to: folder.appending(path: "Notes.pdf"))
        #expect(AnnotatedExporter.uniqueFileName(for: "Notes", in: folder) == "Notes 2.pdf")
    }
}
