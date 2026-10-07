// Renders the app icon. Run: swift design/make-icon.swift <output-dir>
// Monochrome: a paper page on matte black, text lines, one graphite highlight,
// and a hand-drawn Pencil bracket in the margin — "marginalia".
import AppKit
import CoreGraphics

enum Variant: String, CaseIterable { case light = "icon", dark = "icon-dark", tinted = "icon-tinted" }

func gray(_ w: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(gray: w, alpha: a) }

func render(_ variant: Variant, size: Int = 1024) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)
    // Work in a y-down coordinate space.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // Background: matte black with a faint top-down lift.
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                        colors: [gray(variant == .tinted ? 0.0 : 0.13), gray(0.04)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 0), end: CGPoint(x: 512, y: 1024), options: [])

    // The page, tilted slightly as if laid on a desk.
    ctx.saveGState()
    ctx.translateBy(x: 540, y: 520)
    ctx.rotate(by: -0.06)
    let page = CGRect(x: -270, y: -340, width: 540, height: 680)

    // Soft shadow under the page.
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: gray(0, 0.55))
    ctx.setFillColor(gray(0.95))
    ctx.addPath(CGPath(roundedRect: page, cornerWidth: 30, cornerHeight: 30, transform: nil))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Text lines, set right of a generous margin.
    let left = page.minX + 200
    let lineHeight: CGFloat = 78
    let widths: [CGFloat] = [230, 205, 222, 150, 215, 120]
    let firstY = page.minY + 145
    let highlighted = 2

    for (i, w) in widths.enumerated() {
        let y = firstY + CGFloat(i) * lineHeight
        if i == highlighted {
            // Graphite highlight band behind one line.
            ctx.setFillColor(gray(0.55, 0.45))
            ctx.addPath(CGPath(roundedRect: CGRect(x: left - 18, y: y - 30, width: w + 36, height: 60),
                               cornerWidth: 12, cornerHeight: 12, transform: nil))
            ctx.fillPath()
        }
        ctx.setStrokeColor(gray(0.16))
        ctx.setLineWidth(24)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: left, y: y))
        ctx.addLine(to: CGPoint(x: left + w, y: y))
        ctx.strokePath()
    }

    ctx.setStrokeColor(gray(0.07))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Hand-drawn bracket hugging the highlighted passage.
    let top = firstY + lineHeight * 1 - 34
    let bottom = firstY + lineHeight * 3 + 34
    let mid = (top + bottom) / 2
    let x = left - 46
    let bracket = CGMutablePath()
    bracket.move(to: CGPoint(x: x + 24, y: top))
    bracket.addCurve(to: CGPoint(x: x, y: mid),
                     control1: CGPoint(x: x - 4, y: top + 4), control2: CGPoint(x: x + 4, y: mid - 50))
    bracket.addCurve(to: CGPoint(x: x + 26, y: bottom),
                     control1: CGPoint(x: x - 6, y: mid + 52), control2: CGPoint(x: x - 2, y: bottom - 2))
    ctx.setLineWidth(18)
    ctx.addPath(bracket)
    ctx.strokePath()

    // A handwritten note in the margin: a few looping cursive strokes.
    let noteX = page.minX + 42
    let noteY = mid - 14
    let note = CGMutablePath()
    note.move(to: CGPoint(x: noteX, y: noteY + 10))
    var px = noteX
    for i in 0..<4 {
        let w: CGFloat = i == 1 ? 26 : 20
        note.addCurve(to: CGPoint(x: px + w, y: noteY + 10),
                      control1: CGPoint(x: px + w * 0.15, y: noteY - 22),
                      control2: CGPoint(x: px + w * 0.95, y: noteY - 18))
        px += w
    }
    ctx.setLineWidth(9)
    ctx.addPath(note)
    ctx.strokePath()
    // Underline beneath the note.
    ctx.setLineWidth(7)
    ctx.move(to: CGPoint(x: noteX - 2, y: noteY + 34))
    ctx.addCurve(to: CGPoint(x: px + 4, y: noteY + 30),
                 control1: CGPoint(x: noteX + 30, y: noteY + 40), control2: CGPoint(x: px - 20, y: noteY + 28))
    ctx.strokePath()

    ctx.restoreGState()
    return rep
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
for variant in Variant.allCases {
    let data = render(variant).representation(using: .png, properties: [:])!
    try! data.write(to: outDir.appendingPathComponent("\(variant.rawValue).png"))
}
// Small in-app mark (the same art, for the sidebar header).
for (scale, suffix) in [(1, ""), (2, "@2x"), (3, "@3x")] {
    let data = render(.light, size: 28 * scale).representation(using: .png, properties: [:])!
    try! data.write(to: outDir.appendingPathComponent("logo\(suffix).png"))
}
print("ok")
