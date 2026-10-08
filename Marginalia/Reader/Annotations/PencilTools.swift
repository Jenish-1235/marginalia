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

/// Pen ink. Tones are chosen to read well on white paper.
enum InkColor: String, CaseIterable, Identifiable {
    case black, white, red, green, blue, yellow

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: UIColor {
        switch self {
        case .black: UIColor(white: 0.08, alpha: 1)
        case .white: UIColor(white: 0.98, alpha: 1)
        case .red: UIColor(red: 0.83, green: 0.18, blue: 0.18, alpha: 1)
        case .green: UIColor(red: 0.18, green: 0.56, blue: 0.24, alpha: 1)
        case .blue: UIColor(red: 0.10, green: 0.40, blue: 0.80, alpha: 1)
        case .yellow: UIColor(red: 0.98, green: 0.78, blue: 0.10, alpha: 1)
        }
    }
}

enum PenWidth: Double, CaseIterable, Identifiable {
    case fine = 1.4, medium = 2.4, bold = 4.0

    var id: Double { rawValue }
    var dotSize: CGFloat { CGFloat(rawValue * 2 + 2) }
}

struct ToolSettings: Equatable {
    var tool: PencilTool = .pen
    var color: InkColor = .black
    var width: PenWidth = .medium
    /// Off: only Apple Pencil draws and fingers always scroll/select.
    var fingerDraws = false
    /// Off by default: a resting palm can't select text. Pencil highlighting is unaffected.
    var fingerSelects = false

    var pkTool: PKTool {
        switch tool {
        case .pen: PKInkingTool(.pen, color: color.color, width: width.rawValue)
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
        if let raw = defaults.string(forKey: "tools.color"), let color = InkColor(rawValue: raw) { settings.color = color }
        if let width = PenWidth(rawValue: defaults.double(forKey: "tools.width")) { settings.width = width }
        settings.fingerDraws = defaults.bool(forKey: "tools.fingerDraws")
        settings.fingerSelects = defaults.bool(forKey: "tools.fingerSelects")
        return settings
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(tool.rawValue, forKey: "tools.tool")
        defaults.set(color.rawValue, forKey: "tools.color")
        defaults.set(width.rawValue, forKey: "tools.width")
        defaults.set(fingerDraws, forKey: "tools.fingerDraws")
        defaults.set(fingerSelects, forKey: "tools.fingerSelects")
    }
}
