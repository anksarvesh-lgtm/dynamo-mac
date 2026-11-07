import AppKit

// Draws the NotchIsland app icon at a given pixel size: a black squircle with a notch "island"
// pill that glows, in the proportions of a macOS Big Sur-style icon.
func draw(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Squircle body (macOS icon grid: ~82% of the canvas, ~22.4% corner radius).
    let inset = s * 0.09
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.224
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    // Soft shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.05, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor(calibratedWhite: 0.07, alpha: 1).setFill(); path.fill()
    ctx.restoreGState()

    // Body gradient: near-black with a faint top-left sheen.
    path.addClip()
    let g = NSGradient(colorsAndLocations:
        (NSColor(calibratedRed: 0.17, green: 0.18, blue: 0.21, alpha: 1), 0.0),
        (NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1), 0.55),
        (NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.04, alpha: 1), 1.0))!
    g.draw(in: body, angle: -60)

    // A hairline bezel highlight along the top edge.
    let hl = NSBezierPath(roundedRect: body.insetBy(dx: s * 0.004, dy: s * 0.004), xRadius: radius, yRadius: radius)
    hl.lineWidth = s * 0.006
    NSColor.white.withAlphaComponent(0.10).setStroke(); hl.stroke()

    // Accent glow behind the island.
    let islandW = body.width * 0.50, islandH = body.height * 0.135
    let island = CGRect(x: body.midX - islandW / 2, y: body.maxY - body.height * 0.17 - islandH, width: islandW, height: islandH)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.10, color: NSColor(calibratedRed: 0.55, green: 0.75, blue: 1.0, alpha: 0.55).cgColor)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: island, xRadius: islandH / 2, yRadius: islandH / 2).fill()
    ctx.restoreGState()

    // The island pill: white with a subtle vertical gradient; flat top like the real one.
    let pill = NSBezierPath()
    let r = islandH * 0.5
    pill.move(to: CGPoint(x: island.minX, y: island.maxY))
    pill.line(to: CGPoint(x: island.maxX, y: island.maxY))
    pill.line(to: CGPoint(x: island.maxX, y: island.minY + r))
    pill.appendArc(withCenter: CGPoint(x: island.maxX - r, y: island.minY + r), radius: r, startAngle: 0, endAngle: -90, clockwise: true)
    pill.line(to: CGPoint(x: island.minX + r, y: island.minY))
    pill.appendArc(withCenter: CGPoint(x: island.minX + r, y: island.minY + r), radius: r, startAngle: -90, endAngle: -180, clockwise: true)
    pill.close()
    ctx.saveGState()
    pill.addClip()
    NSGradient(starting: NSColor(calibratedWhite: 1.0, alpha: 1), ending: NSColor(calibratedWhite: 0.86, alpha: 1))!
        .draw(in: island, angle: -90)
    ctx.restoreGState()

    // Two "ears": a tiny artwork square and a green level dot, like the compact island.
    let earY = island.midY
    let art = CGRect(x: island.minX + islandH * 0.42, y: earY - islandH * 0.19, width: islandH * 0.38, height: islandH * 0.38)
    NSGradient(starting: NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.55, alpha: 1),
               ending: NSColor(calibratedRed: 0.55, green: 0.35, blue: 1.0, alpha: 1))!
        .draw(in: NSBezierPath(roundedRect: art, xRadius: art.width * 0.28, yRadius: art.width * 0.28), angle: -45)
    let bars = 4
    let bw = islandH * 0.07, gap = islandH * 0.07
    let totalW = CGFloat(bars) * bw + CGFloat(bars - 1) * gap
    let heights: [CGFloat] = [0.18, 0.36, 0.26, 0.40]
    NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1).setFill()
    for i in 0..<bars {
        let h = islandH * heights[i]
        let x = island.maxX - islandH * 0.42 - totalW + CGFloat(i) * (bw + gap)
        NSBezierPath(roundedRect: CGRect(x: x, y: earY - h / 2, width: bw, height: h), xRadius: bw / 2, yRadius: bw / 2).fill()
    }

    // Three faint "cards" below, hinting at the shade.
    let cardW = body.width * 0.62, cardX = body.midX - cardW / 2
    var y = island.minY - body.height * 0.13
    for (i, h) in [0.11, 0.09, 0.07].enumerated() {
        let ch = body.height * CGFloat(h)
        y -= ch
        let c = NSBezierPath(roundedRect: CGRect(x: cardX, y: y, width: cardW, height: ch), xRadius: ch * 0.3, yRadius: ch * 0.3)
        NSColor.white.withAlphaComponent(0.10 - CGFloat(i) * 0.03).setFill(); c.fill()
        y -= body.height * 0.035
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let rep = draw(px)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("iconset written to \(out)")
