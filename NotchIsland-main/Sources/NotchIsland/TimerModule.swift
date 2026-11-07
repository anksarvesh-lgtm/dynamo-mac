import SwiftUI

/// Countdown / Pomodoro timer with a ring.
final class TimerEngine: ObservableObject {
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isRunning = false

    var onFinished: (() -> Void)?
    let presets = [5, 10, 15, 25, 45]

    private var endDate: Date?
    private var ticker: Timer?

    var isActive: Bool { total > 0 }
    var progress: Double { total > 0 ? max(0, min(1, 1 - remaining / total)) : 0 }

    var display: String {
        let s = max(0, Int(remaining.rounded(.up)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    func start(minutes: Int, alreadyElapsed: TimeInterval = 0) {
        ticker?.invalidate()
        total = TimeInterval(minutes * 60)
        remaining = max(1, total - alreadyElapsed)
        resume()
    }

    func resume() {
        guard remaining > 0 else { return }
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        Feedback.tap()
    }

    func pause() {
        ticker?.invalidate()
        if let endDate { remaining = max(0, endDate.timeIntervalSinceNow) }
        isRunning = false
        Feedback.tap()
    }

    func toggle() { isRunning ? pause() : resume() }

    func reset() {
        ticker?.invalidate()
        isRunning = false
        total = 0
        remaining = 0
        endDate = nil
    }

    private func tick() {
        guard let endDate else { return }
        let left = max(0, endDate.timeIntervalSinceNow)
        if left != remaining { remaining = left }
        if left <= 0 {
            ticker?.invalidate()
            isRunning = false
            Feedback.chime()
            onFinished?()
        }
    }
}

struct TimerRing: View {
    let progress: Double
    var size: CGFloat = 20
    var lineWidth: CGFloat = 3
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: lineWidth)
            Circle().trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)
        }
        .frame(width: size, height: size)
    }
}

/// Timer card for the shade and hover readout: ring + time + controls while running, presets
/// when idle.
struct TimerCard: View {
    @ObservedObject var engine: TimerEngine

    var body: some View {
        HStack(spacing: 12) {
            if engine.isActive {
                ZStack {
                    TimerRing(progress: engine.progress, size: 40, lineWidth: 3.5)
                    Image(systemName: "timer").font(.system(size: 13, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.display)
                        .font(UI.numeral(22))
                        .monospacedDigit()
                    Text(engine.isRunning ? "Running" : "Paused")
                        .font(UI.body(10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                IconButton(symbol: engine.isRunning ? "pause.fill" : "play.fill", size: 30,
                           help: engine.isRunning ? "Pause" : "Resume") { engine.toggle() }
                IconButton(symbol: "arrow.counterclockwise", size: 30, help: "Reset") { engine.reset() }
            } else {
                IconBadge(symbol: "timer", size: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Timer").font(UI.title())
                    HStack(spacing: 6) {
                        ForEach(engine.presets, id: \.self) { m in
                            PillButton(title: "\(m)m", small: true, help: "Start a \(m) minute timer") {
                                engine.start(minutes: m)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .islandCard(padding: 12)
    }
}
