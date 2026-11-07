import SwiftUI

private struct WaveformAnimationsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var waveformAnimationsEnabled: Bool {
        get { self[WaveformAnimationsEnabledKey.self] }
        set { self[WaveformAnimationsEnabledKey.self] = newValue }
    }
}

/// Changes the drawing inside a fixed footprint rather than resizing six
/// SwiftUI children on every tick. Both waveform styles use the same renderer.
struct WaveformBars: View {
    let heights: [CGFloat]
    let tint: Color
    let barWidth: CGFloat
    let spacing: CGFloat
    let height: CGFloat

    var body: some View {
        Path { path in
            for (index, barHeight) in heights.enumerated() {
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + spacing),
                    y: (height - barHeight) / 2,
                    width: barWidth,
                    height: barHeight
                )
                path.addRoundedRect(
                    in: rect,
                    cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                )
            }
        }
        .fill(tint)
        .frame(
            width: CGFloat(heights.count) * barWidth + CGFloat(max(0, heights.count - 1)) * spacing,
            height: height
        )
        .accessibilityHidden(true)
    }
}
