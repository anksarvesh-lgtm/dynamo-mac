//
//  EmojiPixelView.swift
//  ClaudeIsland
//
//  Renders any emoji as an animated 16x16 pixel art sprite.
//  Uses TimelineView(.animation) + Canvas for 60fps programmatic rendering.
//

import SwiftUI
import AppKit

// MARK: - Animation Style

enum EmojiAnimStyle: Sendable {
    /// Gentle left-right rotation + blink
    case rock
    /// Wave ripple, dissolve outward, sparkles, reassemble with trails, hold, repeat
    case wave
}

// MARK: - Pixel Data

/// RGBA pixel extracted from an emoji render.
private struct PixelColor: Sendable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    var isVisible: Bool { a > 0.05 }

    var color: Color {
        Color(red: r, green: g, blue: b)
    }
}

// MARK: - Emoji Pixel View

struct EmojiPixelView: View {
    let emoji: String
    let style: EmojiAnimStyle

    private static let gridSize = 16
    private static let P: CGFloat = 3
    static let canvasSize: CGFloat = CGFloat(gridSize) * P  // 48

    /// 16x16 grid of extracted pixel colors, row-major.
    private let pixels: [[PixelColor]]

    init(emoji: String, style: EmojiAnimStyle) {
        self.emoji = emoji
        self.style = style
        self.pixels = Self.rasterizeEmoji(emoji)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let frame = Int(elapsed * 60)

                switch style {
                case .rock:
                    drawRock(context: &context, frame: frame)
                case .wave:
                    drawWave(context: &context, frame: frame)
                }
            }
            .frame(width: Self.canvasSize, height: Self.canvasSize)
        }
    }

    // MARK: - Emoji Rasterization

    /// Renders the emoji string into a 160x160 bitmap, then samples the center of
    /// each 10x10 cell to produce a 16x16 grid of PixelColor values.
    private static func rasterizeEmoji(_ emoji: String) -> [[PixelColor]] {
        let renderSize = 160
        let cellSize = renderSize / gridSize  // 10

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: renderSize,
            pixelsHigh: renderSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: renderSize * 4,
            bitsPerPixel: 32
        )!

        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        // Clear to transparent
        let clearRect = NSRect(x: 0, y: 0, width: renderSize, height: renderSize)
        NSColor.clear.set()
        clearRect.fill()

        // Draw the emoji centered
        let font = NSFont.systemFont(ofSize: CGFloat(renderSize) * 0.85)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let str = emoji as NSString
        let strSize = str.size(withAttributes: attrs)
        let origin = NSPoint(
            x: (CGFloat(renderSize) - strSize.width) / 2,
            y: (CGFloat(renderSize) - strSize.height) / 2
        )
        str.draw(at: origin, withAttributes: attrs)

        NSGraphicsContext.restoreGraphicsState()

        // Sample pixels
        guard let data = rep.bitmapData else {
            return Array(repeating: Array(repeating: PixelColor(r: 0, g: 0, b: 0, a: 0), count: gridSize), count: gridSize)
        }

        var grid = [[PixelColor]]()
        for row in 0..<gridSize {
            var rowColors = [PixelColor]()
            for col in 0..<gridSize {
                // Sample center of cell
                let sx = col * cellSize + cellSize / 2
                let sy = row * cellSize + cellSize / 2
                let offset = (sy * renderSize + sx) * 4
                let r = Double(data[offset]) / 255.0
                let g = Double(data[offset + 1]) / 255.0
                let b = Double(data[offset + 2]) / 255.0
                let a = Double(data[offset + 3]) / 255.0
                rowColors.append(PixelColor(r: r, g: g, b: b, a: a))
            }
            grid.append(rowColors)
        }
        return grid
    }

    // MARK: - Pixel Drawing Helper

    private func drawPixel(
        _ ctx: inout GraphicsContext,
        x: Double,
        y: Double,
        color: Color,
        alpha: Double
    ) {
        let P = Self.P
        let rect = CGRect(x: x * Double(P), y: y * Double(P), width: Double(P), height: Double(P))
        ctx.fill(Path(rect), with: .color(color.opacity(alpha)))
    }

    // MARK: - ROCK Animation

    /// Gentle left-right rotation (+-12 deg, sine wave, ~2.5s cycle) + blink.
    private func drawRock(context: inout GraphicsContext, frame: Int) {
        let gridSize = Self.gridSize
        let angle = sin(Double(frame) * 0.04188) * 12.0  // ~150 frames = 2.5s at 60fps
        let radians = angle * .pi / 180.0
        let cosA = cos(radians)
        let sinA = sin(radians)
        let center = Double(gridSize) / 2.0

        // Blink: every ~100 frames, dim top 20-42% rows for 4 frames
        let blinkActive = (frame % 100) < 4
        let blinkRowMin = Int(Double(gridSize) * 0.20)  // row 3
        let blinkRowMax = Int(Double(gridSize) * 0.42)  // row 6

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let px = pixels[row][col]
                guard px.isVisible else { continue }

                // Rotate around center
                let dx = Double(col) + 0.5 - center
                let dy = Double(row) + 0.5 - center
                let rx = dx * cosA - dy * sinA + center - 0.5
                let ry = dx * sinA + dy * cosA + center - 0.5

                var alpha = px.a
                if blinkActive && row >= blinkRowMin && row <= blinkRowMax {
                    alpha *= 0.15
                }

                drawPixel(&context, x: rx, y: ry, color: px.color, alpha: alpha)
            }
        }
    }

    // MARK: - WAVE Animation (300 frame cycle)

    private func drawWave(context: inout GraphicsContext, frame: Int) {
        let cycleFrame = frame % 300

        if cycleFrame < 120 {
            drawWavePhase(context: &context, frame: cycleFrame)
        } else if cycleFrame < 160 {
            drawDissolvePhase(context: &context, frame: cycleFrame - 120)
        } else if cycleFrame < 180 {
            drawEmptyPhase(context: &context, frame: cycleFrame - 160)
        } else if cycleFrame < 260 {
            drawReassemblePhase(context: &context, frame: cycleFrame - 180)
        } else {
            drawHoldPhase(context: &context, frame: cycleFrame - 260)
        }
    }

    /// Frames 0-120: each row shifts left/right by sin(frame*0.08 + y*0.6) * 1.5
    private func drawWavePhase(context: inout GraphicsContext, frame: Int) {
        let gridSize = Self.gridSize
        for row in 0..<gridSize {
            let shift = sin(Double(frame) * 0.08 + Double(row) * 0.6) * 1.5
            for col in 0..<gridSize {
                let px = pixels[row][col]
                guard px.isVisible else { continue }
                drawPixel(&context, x: Double(col) + shift, y: Double(row), color: px.color, alpha: px.a)
            }
        }
    }

    /// Frames 120-160 (0-39 local): pixels scatter outward from center, fade out.
    private func drawDissolvePhase(context: inout GraphicsContext, frame: Int) {
        let gridSize = Self.gridSize
        let center = Double(gridSize) / 2.0
        let t = Double(frame) / 40.0  // 0..1

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let px = pixels[row][col]
                guard px.isVisible else { continue }

                let dx = Double(col) + 0.5 - center
                let dy = Double(row) + 0.5 - center
                let dist = sqrt(dx * dx + dy * dy)

                // Speed varies by distance from center and per-pixel pseudo-random
                let seed = Double((row * 31 + col * 17) % 100) / 100.0
                let speed = 1.0 + seed * 2.0
                let scatter = t * speed * 3.0

                let ndx = dist > 0.01 ? dx / dist : 0
                let ndy = dist > 0.01 ? dy / dist : 0

                let jitterX = sin(Double(row * 7 + col * 13)) * t * 1.5
                let jitterY = cos(Double(row * 11 + col * 3)) * t * 1.5

                let fx = Double(col) + ndx * scatter + jitterX
                let fy = Double(row) + ndy * scatter + jitterY
                let alpha = px.a * max(0, 1.0 - t * 1.2)

                drawPixel(&context, x: fx, y: fy, color: px.color, alpha: alpha)
            }
        }
    }

    /// Frames 160-180 (0-19 local): faint blue sparkle dots.
    private func drawEmptyPhase(context: inout GraphicsContext, frame: Int) {
        let sparkleColor = Color(red: 0.5, green: 0.7, blue: 1.0)
        let gridSize = Self.gridSize

        for i in 0..<5 {
            // Deterministic pseudo-random positions that change each frame
            let seed = frame * 7 + i * 31
            let sx = Double((seed * 13 + 5) % gridSize)
            let sy = Double((seed * 17 + 3) % gridSize)
            let alpha = 0.2 + sin(Double(frame) * 0.5 + Double(i)) * 0.15
            drawPixel(&context, x: sx, y: sy, color: sparkleColor, alpha: alpha)
        }
    }

    /// Frames 180-260 (0-79 local): pixels fly back with easeInOutQuad, trails, glow flash.
    private func drawReassemblePhase(context: inout GraphicsContext, frame: Int) {
        let gridSize = Self.gridSize
        let center = Double(gridSize) / 2.0
        let rawT = Double(frame) / 80.0  // 0..1
        let t = easeInOutQuad(rawT)

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let px = pixels[row][col]
                guard px.isVisible else { continue }

                let dx = Double(col) + 0.5 - center
                let dy = Double(row) + 0.5 - center
                let dist = sqrt(dx * dx + dy * dy)

                let seed = Double((row * 31 + col * 17) % 100) / 100.0
                let speed = 1.0 + seed * 2.0
                let maxScatter = speed * 3.0

                let ndx = dist > 0.01 ? dx / dist : 0
                let ndy = dist > 0.01 ? dy / dist : 0

                let jitterX = sin(Double(row * 7 + col * 13)) * 1.5
                let jitterY = cos(Double(row * 11 + col * 3)) * 1.5

                // Lerp from scattered position back to home
                let scatteredX = Double(col) + ndx * maxScatter + jitterX
                let scatteredY = Double(row) + ndy * maxScatter + jitterY
                let fx = scatteredX + (Double(col) - scatteredX) * t
                let fy = scatteredY + (Double(row) - scatteredY) * t
                let alpha = px.a * min(1.0, t * 1.5)

                // Draw faint trail behind the pixel
                if t < 0.9 {
                    let trailX = scatteredX + (Double(col) - scatteredX) * max(0, t - 0.1)
                    let trailY = scatteredY + (Double(row) - scatteredY) * max(0, t - 0.1)
                    drawPixel(&context, x: trailX, y: trailY, color: px.color, alpha: alpha * 0.25)
                }

                drawPixel(&context, x: fx, y: fy, color: px.color, alpha: alpha)
            }
        }

        // White glow flash near completion
        if rawT > 0.85 && rawT < 0.95 {
            let glowAlpha = (1.0 - abs(rawT - 0.9) / 0.05) * 0.25
            let rect = CGRect(x: 0, y: 0, width: Double(Self.canvasSize), height: Double(Self.canvasSize))
            context.fill(Path(rect), with: .color(Color.white.opacity(glowAlpha)))
        }
    }

    /// Frames 260-300 (0-39 local): hold stable with very subtle wave.
    private func drawHoldPhase(context: inout GraphicsContext, frame: Int) {
        let gridSize = Self.gridSize
        for row in 0..<gridSize {
            let shift = sin(Double(frame) * 0.05 + Double(row) * 0.6) * 0.3
            for col in 0..<gridSize {
                let px = pixels[row][col]
                guard px.isVisible else { continue }
                drawPixel(&context, x: Double(col) + shift, y: Double(row), color: px.color, alpha: px.a)
            }
        }
    }

    // MARK: - Easing

    private func easeInOutQuad(_ t: Double) -> Double {
        if t < 0.5 {
            return 2 * t * t
        } else {
            return 1 - pow(-2 * t + 2, 2) / 2
        }
    }
}

// MARK: - Preview

#Preview("Octopus Wave") {
    EmojiPixelView(emoji: "🐙", style: .wave)
        .frame(width: 48, height: 48)
        .background(Color.black)
}

#Preview("Cat Rock") {
    EmojiPixelView(emoji: "🐱", style: .rock)
        .frame(width: 48, height: 48)
        .background(Color.black)
}
