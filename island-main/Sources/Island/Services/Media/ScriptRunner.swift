import Foundation

/// Runs AppleScript out-of-process via /usr/bin/osascript with a hard timeout.
///
/// Out-of-process on purpose: a hung or crashing media app can never block or crash Island,
/// and every call can be killed. Scripts are static strings defined by Island's providers —
/// nothing user- or AI-supplied is ever executed.
enum ScriptRunner {
    enum ScriptError: Error, CustomStringConvertible {
        case timeout, failed(String), launch(String)
        var description: String {
            switch self {
            case .timeout: "AppleScript timed out"
            case .failed(let m): m
            case .launch(let m): m
            }
        }
    }

    static func run(_ source: String, timeout: TimeInterval = 3) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", source]
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                let done = DispatchSemaphore(value: 0)
                p.terminationHandler = { _ in done.signal() }
                do { try p.run() } catch {
                    cont.resume(throwing: ScriptError.launch(error.localizedDescription))
                    return
                }
                // Read concurrently so large outputs (artwork) can't deadlock on a full pipe.
                var data = Data()
                let reader = DispatchQueue(label: "island.script.read")
                let readDone = DispatchSemaphore(value: 0)
                reader.async {
                    data = out.fileHandleForReading.readDataToEndOfFile()
                    readDone.signal()
                }
                if done.wait(timeout: .now() + timeout) == .timedOut {
                    p.terminate()
                    cont.resume(throwing: ScriptError.timeout)
                    return
                }
                _ = readDone.wait(timeout: .now() + 1)
                if p.terminationStatus != 0 {
                    let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "AppleScript error"
                    cont.resume(throwing: ScriptError.failed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                    return
                }
                cont.resume(returning: String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            }
        }
    }

    /// Decodes osascript's `«data XXXXhexhex»` representation of binary data.
    static func decodeDataLiteral(_ s: String) -> Data? {
        guard let start = s.range(of: "«data "), let end = s.range(of: "»", options: .backwards), start.upperBound < end.lowerBound else { return nil }
        let body = s[start.upperBound..<end.lowerBound]
        guard body.count > 4 else { return nil }
        let hex = body.dropFirst(4) // 4-char type code, e.g. PNGf / JPEG / tdta
        var data = Data(capacity: hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            data.append(b)
            idx = next
        }
        return data.isEmpty ? nil : data
    }
}
