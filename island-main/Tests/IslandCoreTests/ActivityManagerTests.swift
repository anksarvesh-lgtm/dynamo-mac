import Foundation
@testable import IslandCore

@MainActor
private func makeManager(now: Date = Date(timeIntervalSince1970: 1_000)) -> ActivityManager {
    let m = ActivityManager(clock: { now })
    m.schedulesExpiry = false
    return m
}

private func media(_ title: String = "Song", playing: Bool = true, source: String = "com.apple.Music") -> Activity {
    Activity(id: "media", kind: .media, priority: playing ? .normal : .low, content: .media(MediaActivity(
        sourceBundleID: source, sourceName: "Music", title: title, playbackState: playing ? .playing : .paused)))
}

private func timer(_ id: String = "timer.1", priority: ActivityPriority = .normal) -> Activity {
    Activity(id: id, kind: .timer, priority: priority, content: .timer(TimerActivity(label: "T", duration: 60, state: .running(endDate: .distantFuture))))
}

private func download(_ id: String = "download.1") -> Activity {
    Activity(id: id, kind: .download, priority: .low, content: .download(DownloadActivity(filename: "f.zip", fraction: 0.5)))
}

private func event(_ id: String, _ p: ActivityPriority, expires: Date? = nil) -> Activity {
    Activity(id: id, kind: .notification, priority: p, content: .event(SystemEventActivity(symbol: "bell", title: id)), expiresAt: expires)
}

@MainActor
func registerActivityManagerTests() {
    let S = "ActivityManager"

    test(S, "empty manager has no primary") {
        let m = makeManager()
        expect(m.primary == nil)
        expect(m.secondaries.isEmpty)
    }

    test(S, "single activity becomes primary") {
        let m = makeManager()
        m.submit(.upsert(media()))
        expectEqual(m.primary?.id, "media")
    }

    test(S, "higher priority wins") {
        let m = makeManager()
        m.submit(.upsert(download()))
        m.submit(.upsert(media()))
        expectEqual(m.primary?.id, "media")
        expectEqual(m.secondaries.map(\.id), ["download.1"])
    }

    test(S, "incumbent keeps focus among equal priority") {
        let m = makeManager()
        m.submit(.upsert(media()))
        m.submit(.upsert(timer()))
        expectEqual(m.primary?.id, "media")
        // Updating the incumbent must not reorder.
        m.submit(.upsert(timer()))
        m.submit(.upsert(media("Other")))
        expectEqual(m.primary?.id, "media")
    }

    test(S, "music + timer + download → one primary, two minimal") {
        let m = makeManager()
        m.submit(.upsert(media()))
        m.submit(.upsert(timer()))
        m.submit(.upsert(download()))
        expectEqual(m.primary?.id, "media")
        expectEqual(m.secondaries.map(\.id), ["timer.1", "download.1"])
    }

    test(S, "high priority interrupts and previous returns") {
        let m = makeManager()
        m.submit(.upsert(media()))
        m.submit(.upsert(timer(priority: .high)))
        expectEqual(m.primary?.id, "timer.1")
        expectEqual(m.secondaries.first?.id, "media")
        m.dismiss(id: "timer.1")
        expectEqual(m.primary?.id, "media")
        expectEqual(m.previousPrimaryID, "timer.1")
    }

    test(S, "critical beats high beats normal beats low") {
        let m = makeManager()
        m.submit(.upsert(event("low", .low)))
        m.submit(.upsert(event("normal", .normal)))
        m.submit(.upsert(event("high", .high)))
        m.submit(.upsert(event("critical", .critical)))
        m.maxSecondaries = 3
        expectEqual(m.ordered.map(\.id), ["critical", "high", "normal", "low"])
    }

    test(S, "ordering is deterministic regardless of dictionary order") {
        for _ in 0..<20 {
            let m = makeManager()
            for i in 0..<6 { m.submit(.upsert(event("e\(i)", .normal))) }
            expectEqual(m.ordered.map(\.id), (0..<6).map { "e\($0)" })
        }
    }

    test(S, "pin outranks normal but not high") {
        let m = makeManager()
        m.submit(.upsert(media()))
        m.submit(.upsert(timer()))
        m.select(id: "timer.1")
        expectEqual(m.primary?.id, "timer.1")
        m.submit(.upsert(event("alert", .high)))
        expectEqual(m.primary?.id, "alert")
        m.dismiss(id: "alert")
        expectEqual(m.primary?.id, "timer.1")
    }

    test(S, "pin clears when activity ends") {
        let m = makeManager()
        m.submit(.upsert(media()))
        m.submit(.upsert(timer()))
        m.select(id: "timer.1")
        m.submit(.remove(id: "timer.1"))
        expect(m.pinnedID == nil)
        expectEqual(m.primary?.id, "media")
    }

    test(S, "select unknown id is ignored") {
        let m = makeManager()
        m.submit(.upsert(media()))
        m.select(id: "nope")
        expect(m.pinnedID == nil)
    }

    test(S, "selectNext cycles visible activities") {
        let m = makeManager()
        m.submit(.upsert(media()))
        m.submit(.upsert(timer()))
        m.submit(.upsert(download()))
        m.selectNext()
        expectEqual(m.primary?.id, "timer.1")
    }

    test(S, "transient activities expire") {
        let now = Date(timeIntervalSince1970: 1_000)
        let m = makeManager(now: now)
        m.submit(.upsert(media()))
        m.submit(.upsert(event("charging", .high, expires: now.addingTimeInterval(3))))
        expectEqual(m.primary?.id, "charging")
        m.purgeExpired(now: now.addingTimeInterval(2))
        expectEqual(m.primary?.id, "charging")
        m.purgeExpired(now: now.addingTimeInterval(3.1))
        expectEqual(m.primary?.id, "media")
    }

    test(S, "complete with final lingers then disappears") {
        let now = Date(timeIntervalSince1970: 1_000)
        let m = makeManager(now: now)
        m.submit(.upsert(download()))
        var done = download()
        done.content = .download(DownloadActivity(filename: "f.zip", state: .completed))
        m.submit(.complete(id: "download.1", final: done, linger: 5))
        if case .download(let d)? = m.primary?.content { expectEqual(d.state, .completed) } else { expect(false, "no download") }
        m.purgeExpired(now: now.addingTimeInterval(6))
        expect(m.primary == nil)
    }

    test(S, "media source switch keeps same activity slot") {
        let m = makeManager()
        m.submit(.upsert(media(source: "com.apple.Music")))
        m.submit(.upsert(timer()))
        m.submit(.upsert(media("Spotify song", source: "com.spotify.client")))
        expectEqual(m.primary?.id, "media")
        if case .media(let mm)? = m.primary?.content { expectEqual(mm.sourceBundleID, "com.spotify.client") }
    }

    test(S, "malformed activities are rejected without crashing") {
        let m = makeManager()
        m.submit(.upsert(Activity(id: "  ", kind: .custom, priority: .normal, content: .event(SystemEventActivity(symbol: "x", title: "t")))))
        m.submit(.upsert(Activity(id: "bad", kind: .timer, priority: .normal, content: .media(MediaActivity(sourceBundleID: "", sourceName: "", title: "", playbackState: .playing)))))
        m.submit(.upsert(event("old", .normal, expires: Date(timeIntervalSince1970: 1))))
        expect(m.activities.isEmpty)
    }

    test(S, "non-finite values are sanitised") {
        let m = makeManager()
        m.submit(.upsert(Activity(id: "d", kind: .download, priority: .low, content: .download(DownloadActivity(
            filename: String(repeating: "x", count: 1000), fraction: .nan, completedBytes: -5, totalBytes: 0, bytesPerSecond: .infinity)))))
        guard case .download(let d)? = m.activity(id: "d")?.content else { expect(false, "missing"); return }
        expect(d.fraction == nil)
        expectEqual(d.completedBytes, 0)
        expect(d.totalBytes == nil)
        expect(d.bytesPerSecond == nil)
        expect(d.filename.count <= ActivityValidator.maxStringLength + 1)
    }

    test(S, "disabled kinds are dropped and purged") {
        let m = makeManager()
        m.submit(.upsert(media()))
        m.submit(.upsert(download()))
        m.enabledKinds.remove(.download)
        expect(m.activity(id: "download.1") == nil)
        m.submit(.upsert(download("download.2")))
        expect(m.activity(id: "download.2") == nil)
        expectEqual(m.primary?.id, "media")
    }

    test(S, "capacity limit evicts lowest ranked") {
        let m = makeManager()
        m.maxActivities = 3
        m.submit(.upsert(event("a", .high)))
        m.submit(.upsert(event("b", .normal)))
        m.submit(.upsert(event("c", .low)))
        m.submit(.upsert(event("d", .normal)))
        expectEqual(m.activities.count, 3)
        expect(m.activity(id: "c") == nil)
    }

    test(S, "bus receives lifecycle events") {
        let bus = EventBus()
        let m = ActivityManager(bus: bus, clock: Date.init)
        m.schedulesExpiry = false
        var names: [String] = []
        bus.subscribe { names.append($0.name) }
        m.submit(.upsert(media()))
        m.dismiss(id: "media")
        expectEqual(names, ["activityStarted", "primaryChanged", "activityEnded", "primaryChanged"])
    }

    test(S, "media position extrapolates only while playing") {
        let t0 = Date(timeIntervalSince1970: 0)
        var mm = MediaActivity(sourceBundleID: "x", sourceName: "x", title: "t", playbackState: .playing, elapsed: 10, positionTimestamp: t0, duration: 100)
        expectEqual(mm.position(at: t0.addingTimeInterval(5)), 15)
        expectEqual(mm.position(at: t0.addingTimeInterval(500)), 100)
        mm.playbackState = .paused
        expectEqual(mm.position(at: t0.addingTimeInterval(5)), 10)
    }

    test(S, "timer remaining and fraction") {
        let t0 = Date(timeIntervalSince1970: 0)
        let t = TimerActivity(label: "x", duration: 100, state: .running(endDate: t0.addingTimeInterval(100)))
        expectEqual(t.remaining(at: t0.addingTimeInterval(25)), 75)
        expectEqual(t.fraction(at: t0.addingTimeInterval(25)), 0.25)
        expectEqual(TimerActivity(label: "x", duration: 100, state: .paused(remaining: 40)).remaining(at: t0), 40)
    }
}
