// Renders Resources/AppIcon.icns (run: scripts/make-icon.sh). Original artwork: a black island on a deep gradient.
import AppKit

let out = CommandLine.arguments[1]
let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                              ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in sizes {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.24, blue: 0.55, alpha: 1), NSColor(red: 0.55, green: 0.22, blue: 0.62, alpha: 1)])!
        .draw(in: bg, angle: -60)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    bg.lineWidth = max(1, s * 0.004)
    bg.stroke()
    let pillW = tile.width * 0.62, pillH = tile.width * 0.2
    let pill = NSRect(x: tile.midX - pillW / 2, y: tile.maxY - tile.height * 0.3 - pillH / 2, width: pillW, height: pillH)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: pill, xRadius: pillH / 2, yRadius: pillH / 2).fill()
    NSShadow().set()
    let dot = pillH * 0.42
    NSColor(red: 1, green: 0.62, blue: 0.04, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: pill.maxX - pillH * 0.5 - dot / 2, y: pill.midY - dot / 2, width: dot, height: dot)).fill()
    NSColor(white: 0.85, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: pill.minX + pillH * 0.3, y: pill.midY - dot / 2, width: dot, height: dot), xRadius: dot * 0.25, yRadius: dot * 0.25).fill()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
