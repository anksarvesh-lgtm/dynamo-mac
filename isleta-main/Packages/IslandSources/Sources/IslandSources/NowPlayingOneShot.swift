import Darwin
import Foundation
import IslandKit

/// One short-lived run of the adapter — `get` for the artwork, `queue --length=1` for the format —
/// read under a byte cap and a deadline that **ends in SIGKILL**.
///
/// ## Why the deadline has to end in SIGKILL
///
/// Both callers used to arm a deadline that sent SIGTERM and nothing else. A helper wedged inside a
/// MediaRemote call does not honor SIGTERM — `NowPlayingAdapterReader` escalates to SIGKILL for
/// exactly that reason — so the read below, which blocks until the writer closes the pipe, blocked
/// for good. For the artwork that was worse than one lost cover: every fetch runs on one serial
/// queue, so a single wedged `get` parked the queue and **no cover was fetched again for the rest of
/// the session**. That is the shape of "a long-running instance stops grabbing album artwork" — it
/// needs a `mediaremoted` that stalls once, which a Mac that sleeps and wakes for days on end gives
/// it, and it never recovers until a relaunch.
///
/// The escalation is `Subprocess.run`'s: the polite signal, a short grace, then the one that cannot
/// be caught. A killed writer closes its end of the pipe, which is what lets the read return.
enum NowPlayingOneShot {

    /// What one run came back with.
    enum Outcome {
        /// The helper exited on its own with status 0 and wrote this.
        case output(Data)
        /// It could not be launched, exited non-zero, or wrote more than the cap.
        case failed
        /// It overran the deadline and had to be killed.
        case timedOut
    }

    /// How long SIGTERM is given before SIGKILL.
    static let terminationGrace: TimeInterval = 0.25

    static func run(
        executable: URL,
        arguments: [String],
        byteLimit: Int,
        timeout: TimeInterval
    ) -> Outcome {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        // stderr to /dev/null rather than to a pipe nobody drains. An undrained stderr pipe fills
        // and blocks the writer, so a chatty helper would hang here instead of exiting — the exact
        // failure the streaming reader documents, arriving through a different door.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .failed
        }

        // Deadline before the read, not after: `availableData` blocks until the writer closes the
        // pipe, so a helper that never exits would park the calling thread for the life of the app.
        let boxed = UncheckedBox(process)
        let timedOut = UncheckedFlag()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            guard boxed.value.isRunning else { return }
            timedOut.set()
            boxed.value.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + terminationGrace) {
                guard boxed.value.isRunning else { return }
                kill(boxed.value.processIdentifier, SIGKILL)
            }
        }

        var data = Data()
        let handle = pipe.fileHandleForReading
        while data.count < byteLimit {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        if data.count >= byteLimit {
            // Over the cap: stop reading, and kill the writer rather than leaving it blocked on a
            // pipe nobody is emptying.
            if process.isRunning {
                process.terminate()
                let grace = Date().addingTimeInterval(terminationGrace)
                while process.isRunning, Date() < grace { usleep(10_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            return .failed
        }
        process.waitUntilExit()
        if timedOut.isSet {
            // Once per wedged helper, which is rare by construction and is the one fact that says a
            // cover or a badge went missing because `mediaremoted` stopped answering.
            IslandLog.nowPlaying.warning("one-shot helper overran \(Int(timeout))s and was killed")
            return .timedOut
        }
        guard process.terminationStatus == 0 else { return .failed }
        return .output(data)
    }
}

/// A flag set from the deadline's queue and read on the reader's, once the process has exited.
private final class UncheckedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
