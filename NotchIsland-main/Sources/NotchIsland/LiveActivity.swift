import AppKit
import SwiftUI

/// A transient "live activity" shown in the island: volume HUD, charger plugged in, download
/// progress, AirPods connected, timer done, a custom one pushed from Shortcuts, etc.
struct LiveActivity: Identifiable, Equatable {
    enum Kind: Equatable { case volume, battery, download, bluetooth, timer, calendar, focus, custom, update }

    let id: String
    var kind: Kind
    var symbol: String
    var title: String
    var subtitle: String
    var progress: Double?        // 0...1 draws a bar/ring; nil draws none
    var tint: Color
    var image: NSImage? = nil
    /// Seconds before it auto-dismisses. 0 = long-running: shown as a HUD briefly, then as a
    /// small progress ring in the island's ears until it is dismissed or replaced.
    var duration: TimeInterval

    static func == (a: LiveActivity, b: LiveActivity) -> Bool {
        a.id == b.id && a.title == b.title && a.subtitle == b.subtitle &&
        a.progress == b.progress && a.symbol == b.symbol
    }
}

final class ActivityCenter: ObservableObject {
    static let shared = ActivityCenter()

    /// What the HUD under the notch shows right now.
    @Published private(set) var current: LiveActivity?
    /// The most recently updated long-running activity (download…), shown in the compact ears.
    @Published private(set) var sticky: LiveActivity?

    private var stickies: [String: LiveActivity] = [:]
    private var announced: Set<String> = []      // long-running ids that already had their HUD moment
    private var muted: Set<String> = []          // ids the user dismissed; don't re-post those
    private var dismissWork: DispatchWorkItem?
    private static let stickyHUDSeconds: TimeInterval = 4

    func show(_ activity: LiveActivity) {
        DispatchQueue.main.async {
            guard !self.muted.contains(activity.id) else { return }
            if activity.duration == 0 {
                self.stickies[activity.id] = activity
                let first = !self.announced.contains(activity.id)
                self.announced.insert(activity.id)
                withAnimation(first ? Motion.spring : nil) { self.sticky = activity }
                if first {
                    self.present(activity, for: Self.stickyHUDSeconds)
                } else if self.current?.id == activity.id {
                    self.current = activity            // live update while the HUD is still up
                }
                return
            }
            self.present(activity, for: activity.duration)
        }
    }

    private func present(_ activity: LiveActivity, for seconds: TimeInterval) {
        let replacing = current?.id != activity.id
        withAnimation(replacing ? Motion.spring : nil) { current = activity }
        dismissWork?.cancel()
        guard seconds > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.current?.id == activity.id else { return }
            withAnimation(Motion.quick) { self.current = nil }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Programmatic dismissal (e.g. a download finished). Pass nil to clear the HUD.
    func dismiss(id: String? = nil) {
        DispatchQueue.main.async {
            guard let id else {
                self.dismissWork?.cancel()
                withAnimation(Motion.quick) { self.current = nil }
                return
            }
            self.stickies[id] = nil
            self.announced.remove(id)
            withAnimation(Motion.quick) {
                if self.current?.id == id { self.dismissWork?.cancel(); self.current = nil }
                if self.sticky?.id == id { self.sticky = self.stickies.values.first }
            }
        }
    }

    /// The user tapped the HUD: hide it and don't let the same activity re-post itself.
    func dismissByUser() {
        DispatchQueue.main.async {
            guard let id = self.current?.id else { return }
            self.muted.insert(id)
            if self.muted.count > 50 { self.muted.removeAll() }
            self.stickies[id] = nil
            self.dismissWork?.cancel()
            withAnimation(Motion.quick) {
                self.current = nil
                if self.sticky?.id == id { self.sticky = self.stickies.values.first }
            }
        }
    }
}

/// The compact HUD drawn under the notch for a live activity.
struct ActivityHUD: View {
    let activity: LiveActivity

    var body: some View {
        HStack(spacing: 12) {
            if let image = activity.image {
                Image(nsImage: image).resizable().frame(width: 30, height: 30)
            } else {
                IconBadge(symbol: activity.symbol, tint: activity.tint, size: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title).font(UI.title(12.5)).lineLimit(1)
                if !activity.subtitle.isEmpty {
                    Text(activity.subtitle).font(UI.body(10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let p = activity.progress {
                if activity.kind == .volume || activity.kind == .battery {
                    TrackBar(fraction: p, tint: activity.tint, height: 6).frame(width: 72)
                } else {
                    ActivityRing(progress: p, tint: activity.tint, size: 24)
                }
            } else if activity.duration == 0 {
                ActivityRing(progress: nil, tint: activity.tint, size: 24)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Small progress ring; indeterminate (progress nil) spins.
struct ActivityRing: View {
    let progress: Double?
    var tint: Color = .white
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().stroke(UI.track, lineWidth: size / 8)
            if let p = progress {
                Circle().trim(from: 0, to: max(0.02, min(1, p)))
                    .stroke(tint, style: StrokeStyle(lineWidth: size / 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.4), value: p)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                    Circle().trim(from: 0, to: 0.3)
                        .stroke(tint, style: StrokeStyle(lineWidth: size / 8, lineCap: .round))
                        .rotationEffect(.degrees(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
                }
            }
        }
        .frame(width: size, height: size)
    }
}
