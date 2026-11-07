import AppKit
import IslandCore

/// Tracks downloads by subscribing to file progress published under ~/Downloads (the public
/// `Progress.addSubscriber(forFileURL:)` API that Safari, Chrome and Finder use for their progress bars).
/// Fully event-driven: KVO on each published Progress, throttled to a few UI updates per second.
@MainActor
final class DownloadProvider {
    private final class Tracked {
        let id: String
        let progress: Progress
        var observations: [NSKeyValueObservation] = []
        var lastEmit = Date.distantPast
        var lastBytes: Int64 = 0
        var lastBytesAt = Date()
        var speed: Double?
        init(id: String, progress: Progress) {
            self.id = id
            self.progress = progress
        }
    }

    private let sink: (ActivityUpdate) -> Void
    private let bus: EventBus
    private var subscriber: Any?
    private var tracked: [String: Tracked] = [:]
    private(set) var directory: URL

    init(bus: EventBus, sink: @escaping (ActivityUpdate) -> Void, directory: URL? = nil) {
        self.bus = bus
        self.sink = sink
        self.directory = directory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    var activeCount: Int { tracked.count }

    func start() {
        guard subscriber == nil else { return }
        subscriber = Progress.addSubscriber(forFileURL: directory) { [weak self] progress in
            let id = "download.\(UUID().uuidString)"
            DispatchQueue.main.async { self?.track(progress, id: id) }
            return { DispatchQueue.main.async { self?.unpublished(id) } }
        }
    }

    func stop() {
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
        for t in tracked.values { t.observations.removeAll(); sink(.remove(id: t.id)) }
        tracked.removeAll()
    }

    func handle(_ command: DownloadCommand) {
        switch command {
        case .cancel(let id): tracked[id]?.progress.cancel()
        case .pause(let id): tracked[id]?.progress.pause(); if let t = tracked[id] { emit(t, force: true) }
        case .resume(let id): tracked[id]?.progress.resume(); if let t = tracked[id] { emit(t, force: true) }
        case .reveal(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
        case .open(let url): NSWorkspace.shared.open(url)
        }
    }

    // MARK: Tracking

    private func track(_ progress: Progress, id: String) {
        let t = Tracked(id: id, progress: progress)
        tracked[id] = t
        let handler: @Sendable (Progress, NSKeyValueObservedChange<Double>) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async { self?.emit(t, force: false) }
        }
        t.observations.append(progress.observe(\.fractionCompleted, options: [], changeHandler: handler))
        t.observations.append(progress.observe(\.isPaused, options: []) { [weak self] _, _ in
            DispatchQueue.main.async { self?.emit(t, force: true) }
        })
        emit(t, force: true)
    }

    private func emit(_ t: Tracked, force: Bool) {
        guard tracked[t.id] != nil else { return }
        let now = Date()
        guard force || now.timeIntervalSince(t.lastEmit) >= 0.25 else { return }
        t.lastEmit = now
        let p = t.progress
        let completed = p.completedUnitCount
        let dt = now.timeIntervalSince(t.lastBytesAt)
        if dt >= 0.5 {
            let instant = Double(completed - t.lastBytes) / dt
            if instant >= 0 { t.speed = t.speed.map { $0 * 0.7 + instant * 0.3 } ?? instant }
            t.lastBytes = completed
            t.lastBytesAt = now
        }
        let total = p.totalUnitCount > 0 ? p.totalUnitCount : nil
        let speed = (p.throughput.map(Double.init)) ?? t.speed
        let eta = p.estimatedTimeRemaining ?? {
            guard let total, let speed, speed > 1 else { return nil }
            return Double(total - completed) / speed
        }()
        let d = DownloadActivity(
            filename: Self.displayName(for: p.fileURL), fileURL: Self.finalURL(for: p.fileURL),
            fraction: p.isIndeterminate ? nil : p.fractionCompleted, completedBytes: max(0, completed), totalBytes: total,
            bytesPerSecond: speed, estimatedTimeRemaining: eta, state: .active,
            isCancellable: p.isCancellable, isPausable: p.isPausable, isPaused: p.isPaused)
        sink(.upsert(Activity(id: t.id, kind: .download, priority: .low, content: .download(d))))
    }

    private func unpublished(_ id: String) {
        guard let t = tracked.removeValue(forKey: id) else { return }
        t.observations.removeAll()
        let p = t.progress
        let finished = !p.isCancelled && (p.isFinished || p.fractionCompleted >= 0.995)
        guard finished else {
            sink(.remove(id: id))
            return
        }
        let name = Self.displayName(for: p.fileURL)
        let d = DownloadActivity(filename: name, fileURL: Self.finalURL(for: p.fileURL), fraction: 1,
                                 completedBytes: p.completedUnitCount, totalBytes: p.totalUnitCount > 0 ? p.totalUnitCount : nil, state: .completed)
        sink(.complete(id: id, final: Activity(id: id, kind: .download, priority: .high, content: .download(d)), linger: 5))
        bus.publish(.downloadCompleted(filename: name))
    }

    // MARK: Names

    static let partialExtensions = ["download", "crdownload", "part", "partial"]

    static func finalURL(for url: URL?) -> URL? {
        guard let url else { return nil }
        return partialExtensions.contains(url.pathExtension.lowercased()) ? url.deletingPathExtension() : url
    }

    static func displayName(for url: URL?) -> String {
        finalURL(for: url)?.lastPathComponent ?? "Download"
    }
}
