import Foundation

/// Result of an HTTP JSON request that preserves enough context to
/// distinguish auth failures, rate limits, server errors, and transport
/// errors instead of collapsing everything into `nil`.
struct HTTPJSONResult {
    let statusCode: Int?
    let headers: [AnyHashable: Any]
    let json: [String: Any]?
    let error: Error?

    var isSuccess: Bool {
        statusCode.map { (200..<300).contains($0) } ?? false
    }

    /// Case-insensitive header lookup.
    func header(_ name: String) -> String? {
        for (key, value) in headers {
            if let key = key as? String, key.caseInsensitiveCompare(name) == .orderedSame {
                return value as? String ?? (value as? NSNumber)?.stringValue
            }
        }
        return nil
    }
}

/// Fetches Claude subscription usage from the OAuth usage endpoint.
///
/// Responsibilities beyond a plain request:
/// - identifies as this app by default; the endpoint rate-limits unknown
///   agents into a far stricter bucket, so the caller may opt in to Claude
///   Code's User-Agent instead (see AIUsageProvider.claudeUsageUserAgent),
/// - honors 429 Retry-After (numeric or HTTP-date) and refuses to issue
///   another request before `nextAllowedFetchAt`,
/// - keeps the last successful payload and serves it marked as stale while
///   the endpoint is unavailable,
/// - re-reads the token once after an auth failure so a token rotated by
///   Claude Code is picked up without restarting the app.
///
/// All dependencies are injected so tests can drive every failure path
/// without touching the network or the keychain.
final class ClaudeUsageFetcher {
    struct Token: Equatable {
        let value: String
        let expiresAt: Date?
    }

    enum Failure: String {
        case noToken = "no-token"
        case tokenExpired = "token-expired"
        case authError = "auth-error"
        case rateLimited = "rate-limited"
        case serverError = "server-error"
        case networkError = "network-error"
        case parseError = "parse-error"

        var label: String {
            switch self {
            case .noToken: return "Claude Code sign-in not found"
            case .tokenExpired: return "Claude token expired — run Claude Code to refresh"
            case .authError: return "Claude auth error"
            case .rateLimited: return "Claude usage API rate limited"
            case .serverError: return "Claude usage API server error"
            case .networkError: return "Claude usage API unreachable"
            case .parseError: return "Claude usage API returned unexpected data"
            }
        }
    }

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let defaultRetryAfter: TimeInterval = 900
    private static let maxRetryAfter: TimeInterval = 6 * 3600
    private static let tokenExpirySlack: TimeInterval = 60

    var now: () -> Date = Date.init
    var userAgent: () -> String
    var loadToken: (_ ignoringCache: Bool) -> Token?
    var invalidateCachedToken: () -> Void
    var httpFetch: (URLRequest) -> HTTPJSONResult
    /// Maps a successful usage response to the module payload; returns nil
    /// when the response lacks the expected usage windows.
    var buildPayload: (_ response: [String: Any], _ updatedAt: Int) -> [String: Any]?
    var log: (String) -> Void = { NSLog("SuperIsland AIUsage: %@", $0) }

    private let lock = NSLock()
    private var _nextAllowedFetchAt: Date?
    private var _lastGoodPayload: [String: Any]?
    private var _lastFailure: Failure?

    init(
        userAgent: @escaping () -> String,
        loadToken: @escaping (_ ignoringCache: Bool) -> Token?,
        invalidateCachedToken: @escaping () -> Void,
        httpFetch: @escaping (URLRequest) -> HTTPJSONResult,
        buildPayload: @escaping (_ response: [String: Any], _ updatedAt: Int) -> [String: Any]?
    ) {
        self.userAgent = userAgent
        self.loadToken = loadToken
        self.invalidateCachedToken = invalidateCachedToken
        self.httpFetch = httpFetch
        self.buildPayload = buildPayload
    }

    var nextAllowedFetchAt: Date? {
        lock.lock(); defer { lock.unlock() }
        return _nextAllowedFetchAt
    }

    var lastFailure: Failure? {
        lock.lock(); defer { lock.unlock() }
        return _lastFailure
    }

    /// Returns a module payload, or nil when there is nothing to show and the
    /// caller should fall through to the next data source.
    func payload(updatedAt: Int) -> [String: Any]? {
        let currentDate = now()

        lock.lock()
        let blockedUntil = _nextAllowedFetchAt
        lock.unlock()

        if let blockedUntil, currentDate < blockedUntil {
            return stalePayload(reason: .rateLimited)
        }

        guard let token = usableToken(at: currentDate) else {
            return stalePayload(reason: lastFailure ?? .noToken)
        }

        return perform(token: token, updatedAt: updatedAt, at: currentDate, isRetry: false)
    }

    // MARK: - Request

    private func perform(token: Token, updatedAt: Int, at currentDate: Date, isRetry: Bool) -> [String: Any]? {
        var request = URLRequest(url: Self.usageURL)
        request.timeoutInterval = 3.0
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let result = httpFetch(request)

        switch result.statusCode {
        case .some(let status) where (200..<300).contains(status):
            guard let json = result.json, let payload = buildPayload(json, updatedAt) else {
                setFailure(.parseError)
                log("claude usage request status=\(status) but response missing usage windows")
                return stalePayload(reason: .parseError)
            }
            lock.lock()
            _lastGoodPayload = payload
            _lastFailure = nil
            _nextAllowedFetchAt = nil
            lock.unlock()
            log("claude usage source=oauth-api status=\(status)")
            return payload

        case .some(401), .some(403):
            invalidateCachedToken()
            if !isRetry, let fresh = loadToken(true), fresh != token {
                log("claude usage auth error status=\(result.statusCode ?? 0), retrying with re-read token")
                return perform(token: fresh, updatedAt: updatedAt, at: currentDate, isRetry: true)
            }
            setFailure(.authError)
            log("claude usage auth error status=\(result.statusCode ?? 0)")
            return stalePayload(reason: .authError)

        case .some(429):
            let retryAfter = Self.parseRetryAfter(result.header("Retry-After"), now: currentDate)
                .map { min(max($0, 1), Self.maxRetryAfter) } ?? Self.defaultRetryAfter
            lock.lock()
            _nextAllowedFetchAt = currentDate.addingTimeInterval(retryAfter)
            _lastFailure = .rateLimited
            lock.unlock()
            log("claude usage request status=429 retryAfter=\(Int(retryAfter))s")
            return stalePayload(reason: .rateLimited)

        case .some(let status) where status >= 500:
            setFailure(.serverError)
            log("claude usage request status=\(status)")
            return stalePayload(reason: .serverError)

        case .some(let status):
            setFailure(.parseError)
            log("claude usage request unexpected status=\(status)")
            return stalePayload(reason: .parseError)

        case .none:
            setFailure(.networkError)
            log("claude usage request failed: \(result.error.map { String(describing: type(of: $0)) } ?? "no response")")
            return stalePayload(reason: .networkError)
        }
    }

    // MARK: - Token

    private func usableToken(at currentDate: Date) -> Token? {
        guard let token = loadToken(false) else {
            setFailure(.noToken)
            log("claude usage token unavailable")
            return nil
        }

        guard let expiresAt = token.expiresAt, expiresAt <= currentDate.addingTimeInterval(Self.tokenExpirySlack) else {
            return token
        }

        // The cached token is expired; Claude Code may have rotated it since.
        invalidateCachedToken()
        if let fresh = loadToken(true) {
            if let freshExpiry = fresh.expiresAt, freshExpiry <= currentDate.addingTimeInterval(Self.tokenExpirySlack) {
                setFailure(.tokenExpired)
                log("claude usage token expired, no fresher token available")
                return nil
            }
            return fresh
        }

        setFailure(.tokenExpired)
        log("claude usage token expired, re-read failed")
        return nil
    }

    private func setFailure(_ failure: Failure) {
        lock.lock()
        _lastFailure = failure
        lock.unlock()
    }

    // MARK: - Stale payload

    /// Last successful payload marked as stale, or nil when there is none —
    /// the caller then falls through to the next source and eventually to an
    /// unavailable payload that carries `lastFailure` for the UI.
    private func stalePayload(reason: Failure) -> [String: Any]? {
        lock.lock()
        let lastGood = _lastGoodPayload
        lock.unlock()

        guard var payload = lastGood else { return nil }
        payload["stale"] = true
        payload["source"] = "oauth-api-stale"
        payload["statusLabel"] = "\(reason.label) — showing cached data"
        // Whatever the cached payload said about being blocked describes a
        // moment we can no longer verify — after a sign-out it would other-
        // wise keep claiming the account is blocked until the app restarts.
        payload["isBlocked"] = false
        return payload
    }

    // MARK: - Retry-After

    /// Parses a Retry-After header value: either delay seconds or an HTTP-date.
    static func parseRetryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(value) {
            return seconds >= 0 ? seconds : nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) {
            let interval = date.timeIntervalSince(now)
            return interval > 0 ? interval : 0
        }

        return nil
    }
}

// MARK: - Claude Code version detection

/// Detects the installed Claude Code CLI version so the usage request can send
/// the exact `claude-code/<version>` User-Agent. GUI apps do not inherit the
/// interactive shell PATH, so well-known install locations are probed
/// directly. The result is cached for the process lifetime.
enum ClaudeCodeVersionDetector {
    /// Last-known-good version, used only when detection fails. Kept current
    /// enough that the endpoint still recognizes the agent string.
    static let fallbackVersion = "2.1.220"

    private static let lock = NSLock()
    private static var cachedVersion: String?

    static func userAgent() -> String {
        "claude-code/\(version())"
    }

    static func version() -> String {
        lock.lock()
        if let cachedVersion {
            lock.unlock()
            return cachedVersion
        }
        lock.unlock()

        let detected = detectVersion() ?? fallbackVersion

        lock.lock()
        cachedVersion = detected
        lock.unlock()
        return detected
    }

    private static func detectVersion() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Reading the npm package manifest is cheaper and quieter than
        // spawning the CLI, so try those locations first.
        let packageJSONCandidates = [
            "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/package.json",
            "/usr/local/lib/node_modules/@anthropic-ai/claude-code/package.json",
            "\(home)/.claude/local/node_modules/@anthropic-ai/claude-code/package.json"
        ]
        for path in packageJSONCandidates {
            if let version = versionFromPackageJSON(at: path) {
                return version
            }
        }

        let binaryCandidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude"
        ]
        for path in binaryCandidates where FileManager.default.isExecutableFile(atPath: path) {
            if let version = versionFromCLI(at: path) {
                return version
            }
        }

        return nil
    }

    private static func versionFromPackageJSON(at path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? String else {
            return nil
        }
        return normalizedVersion(version)
    }

    private static func versionFromCLI(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        // Bounded wait so a wedged CLI cannot stall the refresh queue.
        let deadline = Date().addingTimeInterval(3.0)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // Output looks like "2.1.220 (Claude Code)".
        let firstToken = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .first ?? ""
        return normalizedVersion(firstToken)
    }

    private static func normalizedVersion(_ candidate: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".")
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        return trimmed
    }
}
