import PDFKit
import UIKit

/// Turns stored `Highlight`s into PDFKit annotations on the live document.
/// The annotations are display-only; the source file is never written.
enum MarkRenderer {
    /// Graphite tones that read well on white paper.
    static let highlightFill = UIColor(white: 0.42, alpha: 0.30)
    static let lineInk = UIColor(white: 0.12, alpha: 0.90)

    static func annotations(for highlight: Highlight, on page: PDFPage) -> [PDFAnnotation] {
        var result: [PDFAnnotation] = highlight.rects.map { rect in
            let annotation: PDFAnnotation
            switch highlight.style {
            case .highlight:
                annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                annotation.color = highlightFill
            case .underline:
                annotation = PDFAnnotation(bounds: rect, forType: .underline, withProperties: nil)
                annotation.color = lineInk
            case .strikethrough:
                annotation = PDFAnnotation(bounds: rect, forType: .strikeOut, withProperties: nil)
                annotation.color = lineInk
            }
            return annotation
        }

        guard let first = highlight.rects.first else { return result }
        let pageBounds = page.bounds(for: .cropBox)
        let size: CGFloat = 11

        // Intent glyph in the left margin, note glyph in the right margin.
        if let flag = highlight.flag {
            let origin = CGPoint(x: pageBounds.minX + 6, y: first.midY - size / 2)
            result.append(GlyphAnnotation(symbol: flag.symbol, bounds: CGRect(origin: origin, size: .init(width: size, height: size))))
        }
        if highlight.hasNote {
            let origin = CGPoint(x: pageBounds.maxX - size - 6, y: first.midY - size / 2)
            result.append(GlyphAnnotation(symbol: "text.bubble.fill", bounds: CGRect(origin: origin, size: .init(width: size, height: size))))
        }
        return result
    }
}

/// A small SF Symbol drawn in the page margin.
nonisolated final class GlyphAnnotation: PDFAnnotation {
    private var symbol = "circle"

    convenience init(symbol: String, bounds: CGRect) {
        self.init(bounds: bounds, forType: .stamp, withProperties: nil)
        self.symbol = symbol
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let config = UIImage.SymbolConfiguration(pointSize: bounds.height, weight: .bold)
        guard let image = UIImage(systemName: symbol, withConfiguration: config)?
            .withTintColor(UIColor(white: 0.15, alpha: 1), renderingMode: .alwaysOriginal) else { return }
        UIGraphicsPushContext(context)
        context.saveGState()
        // Page space is y-up; UIKit drawing is y-down.
        context.translateBy(x: bounds.minX, y: bounds.maxY)
        context.scaleBy(x: 1, y: -1)
        let fitted = aspectFit(image.size, insideRect: CGRect(origin: .zero, size: bounds.size))
        image.draw(in: fitted)
        context.restoreGState()
        UIGraphicsPopContext()
    }
}

nonisolated private func aspectFit(_ aspectRatio: CGSize, insideRect rect: CGRect) -> CGRect {
    guard aspectRatio.width > 0, aspectRatio.height > 0 else { return rect }
    let scale = min(rect.width / aspectRatio.width, rect.height / aspectRatio.height)
    let size = CGSize(width: aspectRatio.width * scale, height: aspectRatio.height * scale)
    return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
}
