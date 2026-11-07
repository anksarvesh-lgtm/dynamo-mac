// SPDX-License-Identifier: MIT
import SwiftUI

/// A seek bar whose played part is a travelling sine wave, in the spirit of the media players in
/// Android 13 and One UI: it ripples while music plays and flattens smoothly when it pauses.
struct WavySeekBar: View, Animatable {
    /// How far through the track, 0...1.
    var progress: Double
    /// 1 while playing, 0 when paused; animating it eases the wave in and out.
    var amplitude: Double
    /// How far the wave has travelled, in radians; advances with time while playing.
    var phase: Double
    var tint: Color

    nonisolated var animatableData: Double {
        get { amplitude }
        set { amplitude = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let lineWidth: CGFloat = 3.5
            let playedX = size.width * min(max(progress, 0), 1)
            var rest = Path()
            rest.move(to: CGPoint(x: playedX, y: midY))
            rest.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(
                rest, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            let height = (size.height / 2 - lineWidth) * amplitude
            let wavelength: CGFloat = 24
            func y(_ x: CGFloat) -> CGFloat { midY + sin(x / wavelength * 2 * .pi - phase) * height }
            var wave = Path()
            wave.move(to: CGPoint(x: 0, y: y(0)))
            for x in stride(from: 2, through: playedX, by: 2) { wave.addLine(to: CGPoint(x: x, y: y(x))) }
            wave.addLine(to: CGPoint(x: playedX, y: y(playedX)))
            context.stroke(
                wave, with: .color(tint), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            // The play head: a short rounded bar.
            let head = CGRect(x: playedX - 2.5, y: midY - 8, width: 5, height: 16)
            context.fill(Path(roundedRect: head, cornerRadius: 2.5), with: .color(tint))
        }
    }
}

/// The waveform along the bottom of the player. While OpenNotch can hear what's playing, each bar
/// follows the loudness of a band of frequencies, bass in the middle and treble at the ends;
/// otherwise layered sine waves stand in. Bars settle flat when paused.
struct Waveform: View, Animatable {
    /// 1 while playing, 0 when paused; animating it settles the bars.
    var level: Double
    /// Seconds; advances while playing.
    var time: Double
    var tint: Color
    /// Loudness per band, 0...1, lowest frequencies first; empty for the stand-in motion.
    var bands: [Float] = []

    nonisolated var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 5
            let barWidth: CGFloat = 3
            let count = Int(size.width / step)
            let middle = Double(count - 1) / 2
            for index in 0..<count {
                let fromMiddle = middle > 0 ? abs(Double(index) - middle) / middle : 0
                let energy = (bands.isEmpty ? motion(at: index) : loudness(at: fromMiddle)) * level
                let height = max(3, size.height * (0.1 + 0.9 * energy))
                let top = (size.height - height) / 2
                let bar = CGRect(x: CGFloat(index) * step, y: top, width: barWidth, height: height)
                context.fill(
                    Path(roundedRect: bar, cornerRadius: barWidth / 2), with: .color(tint.opacity(0.3 + 0.5 * energy)))
            }
        }
    }

    /// The stand-in: layered sine waves travelling across the bars.
    private func motion(at index: Int) -> Double {
        let i = Double(index)
        return 0.55 + 0.25 * sin(time * 3.1 + i * 0.35) + 0.15 * sin(time * 5.7 + i * 0.83)
            + 0.05 * sin(time * 11.3 + i * 2.1)
    }

    /// The band at `position` from the middle (0) to either end (1), blended between neighbours.
    private func loudness(at position: Double) -> Double {
        let place = min(max(position, 0), 1) * Double(bands.count - 1)
        let lower = Int(place)
        let upper = min(lower + 1, bands.count - 1)
        let blend = place - Double(lower)
        return Double(bands[lower]) * (1 - blend) + Double(bands[upper]) * blend
    }
}

/// Shrinks a little while pressed and springs back, so controls feel physical.
public struct PressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}
