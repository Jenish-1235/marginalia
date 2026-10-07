import OSLog
import PDFKit
import PencilKit
import UIKit

private let log = Logger(subsystem: "com.jenish.marginalia", category: "ink")

/// Supplies one PencilKit canvas per visible page via PDFKit's overlay API, so ink scrolls and
/// zooms with the page. Drawings are stored in the canvas's own coordinates (page points, y-down).
final class InkLayer: NSObject, PDFPageOverlayViewProvider, PKCanvasViewDelegate {
    private unowned let model: ReaderModel
    private var canvases: [Int: PKCanvasView] = [:]
    private var pendingSaves: [Int: Task<Void, Never>] = [:]
    /// Set while we replace a canvas's drawing ourselves, so it isn't treated as user input.
    private var isApplyingDrawing = false
    /// Canvases whose just-finished stroke should be checked for snapping. PencilKit commits the
    /// stroke to the drawing only *after* `canvasViewDidEndUsingTool`, so the check runs on the
    /// following drawing change.
    private var strokeCountAtToolStart: [Int: Int] = [:]
    private var awaitingSnap: Set<Int> = []

    init(model: ReaderModel) {
        self.model = model
    }

    func apply(_ settings: ToolSettings) {
        for canvas in canvases.values {
            canvas.tool = settings.pkTool
            canvas.drawingPolicy = settings.drawingPolicy
        }
    }

    /// Writes every pending drawing immediately (closing the reader, backgrounding).
    func flush() {
        for (page, canvas) in canvases {
            pendingSaves[page]?.cancel()
            model.saveInk(canvas.drawing, page: page)
        }
        pendingSaves.removeAll()
    }

    // MARK: PDFPageOverlayViewProvider

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        let index = model.pdf.index(for: page)
        if let existing = canvases[index] { return existing }

        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.tool = model.tools.pkTool
        canvas.drawingPolicy = model.tools.drawingPolicy
        canvas.delegate = self
        canvas.tag = index
        // PencilKit's own finger gestures (e.g. the "Insert Space" long-press menu) would steal
        // the finger long-press we use for text selection. Fingers only ever draw when the user
        // opts in, via the drawing gesture recognizer.
        for recognizer in canvas.gestureRecognizers ?? [] where recognizer !== canvas.drawingGestureRecognizer {
            recognizer.allowedTouchTypes = [UITouch.TouchType.pencil.rawValue as NSNumber]
        }
        isApplyingDrawing = true
        canvas.drawing = model.inkDrawing(for: index)
        isApplyingDrawing = false
        canvases[index] = canvas
        return canvas
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = overlayView as? PKCanvasView else { return }
        let index = canvas.tag
        if pendingSaves[index] != nil {
            pendingSaves[index]?.cancel()
            pendingSaves[index] = nil
            model.saveInk(canvas.drawing, page: index)
        }
        canvases[index] = nil
    }

    // MARK: PKCanvasViewDelegate

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingDrawing else { return }
        let index = canvasView.tag
        if awaitingSnap.remove(index) != nil,
           let style = model.tools.tool.snapsToText,
           canvasView.drawing.strokes.count > strokeCountAtToolStart[index, default: 0] {
            snapLastStroke(on: canvasView, style: style)
        }
        pendingSaves[index]?.cancel()
        pendingSaves[index] = Task { [weak self, weak canvasView] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled, let self, let canvasView else { return }
            pendingSaves[index] = nil
            model.saveInk(canvasView.drawing, page: index)
        }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        strokeCountAtToolStart[canvasView.tag] = canvasView.drawing.strokes.count
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        guard model.tools.tool.snapsToText != nil else { return }
        awaitingSnap.insert(canvasView.tag)
    }

    // MARK: Smart highlighter

    /// If the stroke just drawn runs along text, replace it with a real text mark.
    private func snapLastStroke(on canvas: PKCanvasView, style: MarkStyle) {
        let index = canvas.tag
        guard let page = model.pdf.page(at: index),
              let stroke = canvas.drawing.strokes.last,
              canvas.bounds.width > 0, canvas.bounds.height > 0 else { return }

        let box = page.bounds(for: .cropBox)
        let sx = box.width / canvas.bounds.width
        let sy = box.height / canvas.bounds.height
        let points: [CGPoint] = stroke.path.map { point in
            let p = point.location.applying(stroke.transform)
            return CGPoint(x: box.minX + p.x * sx, y: box.maxY - p.y * sy)
        }
        guard let first = points.first, let last = points.last, points.count >= 2 else { return }
        log.debug("snap: canvas \(canvas.bounds.debugDescription) page \(box.debugDescription) first \(first.debugDescription) last \(last.debugDescription)")

        // Mostly horizontal strokes only — arrows and circles stay ink.
        let xs = points.map(\.x), ys = points.map(\.y)
        let width = (xs.max() ?? 0) - (xs.min() ?? 0)
        let height = (ys.max() ?? 0) - (ys.min() ?? 0)
        guard width >= 8, width >= height else {
            log.debug("snap: rejected shape \(width) x \(height)")
            return
        }

        guard let selection = page.selection(from: first, to: last),
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else {
            log.debug("snap: no text between stroke ends")
            return
        }

        let lineRects = selection.selectionsByLine()
            .map { $0.bounds(for: page) }
            .filter { !$0.isEmpty }
        let verticalSlack: CGFloat = style == .underline ? 7 : 3
        let inside = points.filter { p in
            lineRects.contains { $0.insetBy(dx: -4, dy: -verticalSlack).contains(p) }
        }.count
        log.debug("snap: '\(text)' lines \(lineRects.count) inside \(inside)/\(points.count)")
        guard Double(inside) / Double(points.count) >= 0.6 else { return }

        // Snap to whole words: a stroke that starts or ends mid-word takes the whole word.
        for point in [first, last] {
            if let word = page.selectionForWord(at: point), !(word.string ?? "").isEmpty { selection.add(word) }
        }

        var drawing = canvas.drawing
        drawing.strokes.removeLast()
        isApplyingDrawing = true
        canvas.drawing = drawing
        isApplyingDrawing = false
        model.saveInk(drawing, page: index)
        model.addMark(from: selection, style: style)
    }
}
