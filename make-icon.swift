import AppKit

// Draws AppIcon.iconset: sky-blue squircle with a white calorie ring and an orange flame dot.
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let dir = out + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.33, green: 0.58, blue: 0.85, alpha: 1), NSColor(red: 0.16, green: 0.40, blue: 0.75, alpha: 1)])!
        .draw(in: path, angle: -90)
    let c = NSPoint(x: s / 2, y: s / 2), r = rect.width * 0.30, lw = rect.width * 0.09
    let track = NSBezierPath(); track.appendArc(withCenter: c, radius: r, startAngle: 0, endAngle: 360)
    track.lineWidth = lw; NSColor.white.withAlphaComponent(0.28).setStroke(); track.stroke()
    let arc = NSBezierPath(); arc.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: 90 - 250, clockwise: true)
    arc.lineWidth = lw; arc.lineCapStyle = .round; NSColor.white.setStroke(); arc.stroke()
    let dot = rect.width * 0.11
    NSColor(red: 0.92, green: 0.41, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - dot / 2, y: c.y - dot / 2, width: dot, height: dot)).fill()
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
