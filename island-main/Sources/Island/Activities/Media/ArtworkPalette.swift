import AppKit

/// Extracts two vivid accent colours from album artwork (cached per artwork id). Used to tint the
/// equalizer like the iPhone does. Falls back to a "voice" gradient (pink → violet → blue).
@MainActor
enum ArtworkPalette {
    private static var cache: [String: [NSColor]] = [:]

    static let voice: [NSColor] = [
        NSColor(red: 1.00, green: 0.37, blue: 0.62, alpha: 1),
        NSColor(red: 0.64, green: 0.36, blue: 1.00, alpha: 1),
        NSColor(red: 0.31, green: 0.64, blue: 1.00, alpha: 1),
    ]

    static func colors(for key: String?, image: NSImage?) -> [NSColor] {
        guard let key, let image else { return voice }
        if let c = cache[key] { return c }
        let c = extract(image) ?? voice
        if cache.count > 64 { cache.removeAll() }
        cache[key] = c
        return c
    }

    /// Downsamples to 12×12 and picks the two most saturated, reasonably bright, distinct colours.
    static func extract(_ image: NSImage) -> [NSColor]? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let n = 12
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var candidates: [(NSColor, CGFloat, CGFloat)] = [] // colour, saturation score, hue
        for i in stride(from: 0, to: px.count, by: 4) {
            let c = NSColor(red: CGFloat(px[i]) / 255, green: CGFloat(px[i + 1]) / 255, blue: CGFloat(px[i + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            guard b > 0.35 else { continue }
            candidates.append((NSColor(hue: h, saturation: min(1, max(s, 0.45)), brightness: max(b, 0.85), alpha: 1), s * b, h))
        }
        let sorted = candidates.sorted { $0.1 > $1.1 }
        guard let first = sorted.first, first.1 > 0.12 else { return nil }
        let second = sorted.first { abs($0.2 - first.2) > 0.08 && abs($0.2 - first.2) < 0.92 }?.0
            ?? first.0.blended(withFraction: 0.45, of: .white) ?? first.0
        return [first.0, second]
    }
}
