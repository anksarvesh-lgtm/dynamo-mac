import AppKit
import QuartzCore
import SwiftUI

/// Now-playing equalizer, animated entirely by Core Animation (render server — ~0% app CPU).
/// Five rounded bars with an artwork-tinted vertical gradient and a soft glow; each bar runs its own
/// keyframe loop so the motion looks organic rather than metronomic.
struct EqualizerView: NSViewRepresentable {
    var playing: Bool
    var colors: [NSColor]
    var reduceMotion = false

    func makeNSView(context: Context) -> EqualizerNSView { EqualizerNSView() }

    func updateNSView(_ v: EqualizerNSView, context: Context) {
        v.configure(playing: playing && !reduceMotion, colors: colors)
    }
}

final class EqualizerNSView: NSView {
    private var bars: [CAGradientLayer] = []
    private var playing = false
    private var colors: [NSColor] = ArtworkPaletteFallback.colors
    private static let barCount = 5
    private static let rest: CGFloat = 0.22
    // Ten-step "melodies" per bar with mismatched loop lengths, so the bars drift in and out of phase
    // and the overall shape never visibly repeats. Values are deterministic (fixed seed).
    private static let patterns: [[CGFloat]] = (0..<barCount).map { bar in
        var state = UInt64(0x9E37_79B9 &* UInt64(bar + 1))
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) % 1000) / 1000
        }
        var values = (0..<9).map { i in
            // Alternate low/high so every bar keeps "talking", with random amplitude.
            i % 2 == 0 ? 0.18 + next() * 0.35 : 0.55 + next() * 0.45
        }
        values.append(values[0]) // seamless loop
        return values
    }
    private static let durations: [CFTimeInterval] = [1.9, 2.3, 1.7, 2.1, 2.5]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        for _ in 0..<Self.barCount {
            let bar = CAGradientLayer()
            bar.startPoint = CGPoint(x: 0.5, y: 0)
            bar.endPoint = CGPoint(x: 0.5, y: 1)
            bar.shadowOpacity = 0.38
            bar.shadowRadius = 4.5
            bar.shadowOffset = .zero
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Animations are dropped when a layer leaves a window; restart them when it comes back.
        if window != nil, playing { startAnimations() }
    }

    override func layout() {
        super.layout()
        let n = CGFloat(Self.barCount)
        let gap: CGFloat = 2
        let w = max(2, (bounds.width - gap * (n - 1)) / n)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            bar.cornerRadius = w / 2
            bar.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: bounds.midY)
            bar.shadowPath = CGPath(roundedRect: bar.bounds, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
            if !playing { bar.transform = CATransform3DMakeScale(1, Self.rest, 1) }
        }
        CATransaction.commit()
        if playing, bars.first?.animation(forKey: "eq") == nil { startAnimations() }
    }

    func configure(playing: Bool, colors: [NSColor]) {
        if colors != self.colors || bars.first?.colors == nil {
            self.colors = colors.isEmpty ? ArtworkPaletteFallback.colors : colors
            let cg = self.colors.map(\.cgColor)
            for (i, bar) in bars.enumerated() {
                // Spread the palette across the bars so the group reads as one gradient.
                let a = cg[i % cg.count], b = cg[(i + 1) % cg.count]
                bar.colors = [a, b]
                bar.shadowColor = a
            }
        }
        guard playing != self.playing else { return }
        self.playing = playing
        playing ? startAnimations() : stopAnimations()
    }

    private func startAnimations() {
        let now = CACurrentMediaTime()
        for (i, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "eq")
            let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
            a.values = Self.patterns[i % Self.patterns.count]
            a.duration = Self.durations[i % Self.durations.count]
            a.calculationMode = .cubic
            a.repeatCount = .infinity
            a.beginTime = now - Double(i) * 0.17 // phase offset
            a.isRemovedOnCompletion = false
            bar.add(a, forKey: "eq")
            bar.transform = CATransform3DIdentity
        }
    }

    private func stopAnimations() {
        for bar in bars {
            let current = bar.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat ?? 1
            bar.removeAnimation(forKey: "eq")
            let settle = CABasicAnimation(keyPath: "transform.scale.y")
            settle.fromValue = current
            settle.toValue = Self.rest
            settle.duration = 0.35
            settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bar.transform = CATransform3DMakeScale(1, Self.rest, 1)
            bar.add(settle, forKey: "settle")
        }
    }
}

enum ArtworkPaletteFallback {
    static let colors: [NSColor] = [
        NSColor(red: 1.00, green: 0.37, blue: 0.62, alpha: 1),
        NSColor(red: 0.64, green: 0.36, blue: 1.00, alpha: 1),
        NSColor(red: 0.31, green: 0.64, blue: 1.00, alpha: 1),
    ]
}
