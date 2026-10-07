import PencilKit
import UIKit

enum PencilTool: String, CaseIterable, Identifiable {
    case pen, highlighter, underline, eraser, lasso

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Smart Highlighter"
        case .underline: "Smart Underline"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        }
    }

    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .underline: "underline"
        case .eraser: "eraser"
        case .lasso: "lasso"
        }
    }

    /// Text-aware tools turn strokes over text into real text marks.
    var snapsToText: MarkStyle? {
        switch self {
        case .highlighter: .highlight
        case .underline: .underline
        default: nil
        }
    }
}

enum InkShade: String, CaseIterable, Identifiable {
    case ink, graphite

    var id: String { rawValue }
    var title: String { self == .ink ? "Ink" : "Graphite" }
    var color: UIColor { self == .ink ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.45, alpha: 1) }
}

enum PenWidth: Double, CaseIterable, Identifiable {
    case fine = 1.4, medium = 2.4, bold = 4.0

    var id: Double { rawValue }
    var dotSize: CGFloat { CGFloat(rawValue * 2 + 2) }
}

struct ToolSettings: Equatable {
    var tool: PencilTool = .pen
    var shade: InkShade = .ink
    var width: PenWidth = .medium
    /// Off: only Apple Pencil draws and fingers always scroll/select.
    var fingerDraws = false

    var pkTool: PKTool {
        switch tool {
        case .pen: PKInkingTool(.pen, color: shade.color, width: width.rawValue)
        case .highlighter: PKInkingTool(.marker, color: UIColor(white: 0.55, alpha: 1), width: 14)
        case .underline: PKInkingTool(.pen, color: UIColor(white: 0.2, alpha: 1), width: 1.6)
        case .eraser: PKEraserTool(.vector)
        case .lasso: PKLassoTool()
        }
    }

    var drawingPolicy: PKCanvasViewDrawingPolicy { fingerDraws ? .anyInput : .pencilOnly }

    // Persisted between sessions.
    static func load() -> ToolSettings {
        let defaults = UserDefaults.standard
        var settings = ToolSettings()
        if let raw = defaults.string(forKey: "tools.tool"), let tool = PencilTool(rawValue: raw) { settings.tool = tool }
        if let raw = defaults.string(forKey: "tools.shade"), let shade = InkShade(rawValue: raw) { settings.shade = shade }
        if let width = PenWidth(rawValue: defaults.double(forKey: "tools.width")) { settings.width = width }
        settings.fingerDraws = defaults.bool(forKey: "tools.fingerDraws")
        return settings
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(tool.rawValue, forKey: "tools.tool")
        defaults.set(shade.rawValue, forKey: "tools.shade")
        defaults.set(width.rawValue, forKey: "tools.width")
        defaults.set(fingerDraws, forKey: "tools.fingerDraws")
    }
}
