#if DEBUG
import AppKit
import QuartzCore

/// DEBUG: records display-link callback intervals on the Island window to detect main-thread hitches
/// during animations. Writes stats to $TMPDIR/island-frames.txt.
@MainActor
final class FrameRecorder: NSObject {
    private var link: CADisplayLink?
    private var stamps: [CFTimeInterval] = []
    private var refresh: Double = 60

    func record(on view: NSView, seconds: Double) {
        link?.invalidate()
        stamps.removeAll()
        refresh = Double(view.window?.screen?.maximumFramesPerSecond ?? 60)
        let l = view.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.finish() }
    }

    @objc private func tick(_ l: CADisplayLink) { stamps.append(l.timestamp) }

    private func finish() {
        link?.invalidate()
        link = nil
        let gaps = zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }
        let budget = 1000 / refresh
        let dropped = gaps.filter { $0 > budget * 1.5 }.count
        let maxGap = gaps.max() ?? 0
        let avg = gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)
        let text = String(format: "frames=%d refresh=%.0fHz avg=%.2fms max=%.2fms hitches(>1.5 frames)=%d", stamps.count, refresh, avg, maxGap, dropped)
        try? text.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("island-frames.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
