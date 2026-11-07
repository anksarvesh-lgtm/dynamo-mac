import XCTest
@testable import SuperIsland

final class ClaudeUsageFetcherTests: XCTestCase {

    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let secretToken = "secret-token-value-abc123"

    private struct Harness {
        let fetcher: ClaudeUsageFetcher
        let state: State

        final class State {
            var now: Date
            var tokens: [ClaudeUsageFetcher.Token?] = []
            var loadTokenCalls: [Bool] = []
            var invalidateCount = 0
            var requests: [URLRequest] = []
            var results: [HTTPJSONResult] = []
            var logs: [String] = []

            init(now: Date) { self.now = now }
        }
    }

    private func makeHarness(
        token: ClaudeUsageFetcher.Token?,
        results: [HTTPJSONResult]
    ) -> Harness {
        let state = Harness.State(now: baseDate)
        state.tokens = [token]
        state.results = results

        let fetcher = ClaudeUsageFetcher(
            userAgent: { "claude-code/2.1.220" },
            loadToken: { ignoringCache in
                state.loadTokenCalls.append(ignoringCache)
                return state.tokens.isEmpty ? nil : state.tokens.removeFirst()
            },
            invalidateCachedToken: { state.invalidateCount += 1 },
            httpFetch: { request in
                state.requests.append(request)
                return state.results.isEmpty
                    ? HTTPJSONResult(statusCode: nil, headers: [:], json: nil, error: URLError(.timedOut))
                    : state.results.removeFirst()
            },
            buildPayload: { AIUsageProvider.claudeOAuthResponsePayload(from: $0, updatedAt: $1) }
        )
        fetcher.now = { state.now }
        fetcher.log = { state.logs.append($0) }
        return Harness(fetcher: fetcher, state: state)
    }

    private func token(expiresAt: Date? = nil) -> ClaudeUsageFetcher.Token {
        ClaudeUsageFetcher.Token(value: secretToken, expiresAt: expiresAt)
    }

    private func success(_ json: [String: Any]) -> HTTPJSONResult {
        HTTPJSONResult(statusCode: 200, headers: [:], json: json, error: nil)
    }

    private func usageJSON(
        fiveHour: Double? = 31.0,
        sevenDayKey: String = "seven_day",
        sevenDay: Double? = 12.0
    ) -> [String: Any] {
        var json: [String: Any] = [:]
        if let fiveHour {
            json["five_hour"] = ["utilization": fiveHour, "resets_at": "2026-08-19T15:00:00+00:00"]
        }
        if let sevenDay {
            json[sevenDayKey] = ["utilization": sevenDay, "resets_at": "2026-08-22T07:00:00+00:00"]
        }
        return json
    }

    // MARK: - Success parsing

    func testSuccessMapsUtilizationToRemainingPercent() throws {
        let harness = makeHarness(token: token(), results: [success(usageJSON())])
        let payload = try XCTUnwrap(harness.fetcher.payload(updatedAt: 1))

        XCTAssertEqual(payload["available"] as? Bool, true)
        XCTAssertEqual(payload["source"] as? String, "oauth-api")
        XCTAssertEqual(payload["currentSessionRemainingPercent"] as? Double, 69.0)
        XCTAssertEqual(payload["weeklyRemainingPercent"] as? Double, 88.0)
        XCTAssertEqual(payload["remainingPercent"] as? Double, 69.0)
        XCTAssertNil(harness.fetcher.lastFailure)
    }

    func testSuccessReadsEachWeeklyWindowVariant() throws {
        for key in ["seven_day", "seven_day_sonnet", "seven_day_opus", "seven_day_oauth_apps"] {
            let harness = makeHarness(
                token: token(),
                results: [success(usageJSON(sevenDayKey: key, sevenDay: 40.0))]
            )
            let payload = try XCTUnwrap(harness.fetcher.payload(updatedAt: 1), "window key \(key)")
            XCTAssertEqual(payload["weeklyRemainingPercent"] as? Double, 60.0, "window key \(key)")
        }
    }

    func testRequestCarriesClaudeCodeUserAgentAndBetaHeader() throws {
        let harness = makeHarness(token: token(), results: [success(usageJSON())])
        _ = harness.fetcher.payload(updatedAt: 1)

        let request = try XCTUnwrap(harness.state.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "claude-code/2.1.220")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(secretToken)")
    }

    func testMissingSessionWindowIsParseFailure() {
        let harness = makeHarness(token: token(), results: [success(["unrelated": 1])])
        XCTAssertNil(harness.fetcher.payload(updatedAt: 1))
        XCTAssertEqual(harness.fetcher.lastFailure, .parseError)
    }

    func testInvalidJSONOnSuccessStatusIsParseFailure() {
        let harness = makeHarness(
            token: token(),
            results: [HTTPJSONResult(statusCode: 200, headers: [:], json: nil, error: nil)]
        )
        XCTAssertNil(harness.fetcher.payload(updatedAt: 1))
        XCTAssertEqual(harness.fetcher.lastFailure, .parseError)
    }

    // MARK: - Auth errors

    func testUnauthorizedInvalidatesTokenAndRetriesWithFreshToken() throws {
        let harness = makeHarness(
            token: token(),
            results: [
                HTTPJSONResult(statusCode: 401, headers: [:], json: nil, error: nil),
                success(usageJSON())
            ]
        )
        harness.state.tokens.append(ClaudeUsageFetcher.Token(value: "rotated-token", expiresAt: nil))

        let payload = try XCTUnwrap(harness.fetcher.payload(updatedAt: 1))
        XCTAssertEqual(payload["source"] as? String, "oauth-api")
        XCTAssertEqual(harness.state.invalidateCount, 1)
        XCTAssertEqual(harness.state.requests.count, 2)
        XCTAssertEqual(
            harness.state.requests.last?.value(forHTTPHeaderField: "Authorization"),
            "Bearer rotated-token"
        )
    }

    func testUnauthorizedWithSameTokenIsAuthErrorWithoutRetryLoop() {
        let harness = makeHarness(
            token: token(),
            results: [HTTPJSONResult(statusCode: 401, headers: [:], json: nil, error: nil)]
        )
        harness.state.tokens.append(token())

        XCTAssertNil(harness.fetcher.payload(updatedAt: 1))
        XCTAssertEqual(harness.fetcher.lastFailure, .authError)
        XCTAssertEqual(harness.state.requests.count, 1)
    }

    func testForbiddenIsAuthError() {
        let harness = makeHarness(
            token: token(),
            results: [HTTPJSONResult(statusCode: 403, headers: [:], json: nil, error: nil)]
        )
        harness.state.tokens.append(nil)

        XCTAssertNil(harness.fetcher.payload(updatedAt: 1))
        XCTAssertEqual(harness.fetcher.lastFailure, .authError)
        XCTAssertEqual(harness.state.invalidateCount, 1)
    }

    // MARK: - Rate limiting

    func testRateLimitWithNumericRetryAfterBlocksFurtherRequests() {
        let harness = makeHarness(
            token: token(),
            results: [HTTPJSONResult(statusCode: 429, headers: ["Retry-After": "1800"], json: nil, error: nil)]
        )

        XCTAssertNil(harness.fetcher.payload(updatedAt: 1))
        XCTAssertEqual(harness.fetcher.lastFailure, .rateLimited)
        XCTAssertEqual(
            harness.fetcher.nextAllowedFetchAt,
            baseDate.addingTimeInterval(1800)
        )

        // Within the blocked window no further request may be issued.
        harness.state.now = baseDate.addingTimeInterval(600)
        XCTAssertNil(harness.fetcher.payload(updatedAt: 2))
        XCTAssertEqual(harness.state.requests.count, 1)

        // After the window a request is allowed again.
        harness.state.now = baseDate.addingTimeInterval(1801)
        harness.state.tokens = [token()]
        harness.state.results = [success(usageJSON())]
        XCTAssertNotNil(harness.fetcher.payload(updatedAt: 3))
        XCTAssertEqual(harness.state.requests.count, 2)
    }

    func testRateLimitWithHTTPDateRetryAfter() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let retryDate = formatter.string(from: baseDate.addingTimeInterval(1200))

        let harness = makeHarness(
            token: token(),
            results: [HTTPJSONResult(statusCode: 429, headers: ["Retry-After": retryDate], json: nil, error: nil)]
        )

        XCTAssertNil(harness.fetcher.payload(updatedAt: 1))
        let next = harness.fetcher.nextAllowedFetchAt
        XCTAssertNotNil(next)
        XCTAssertEqual(next!.timeIntervalSince(baseDate), 1200, accuracy: 2)
    }

    func testRateLimitWithoutRetryAfterUsesDefaultBackoff() {
        let harness = makeHarness(
            token: token(),
            results: [HTTPJSONResult(statusCode: 429, headers: [:], json: nil, error: nil)]
        )

        XCTAssertNil(harness.fetcher.payload(updatedAt: 1))
        XCTAssertEqual(harness.fetcher.nextAllowedFetchAt, baseDate.addingTimeInterval(900))
    }

    func testParseRetryAfterVariants() {
        XCTAssertEqual(ClaudeUsageFetcher.parseRetryAfter("120", now: baseDate), 120)
        XCTAssertEqual(ClaudeUsageFetcher.parseRetryAfter(" 42 ", now: baseDate), 42)
        XCTAssertNil(ClaudeUsageFetcher.parseRetryAfter(nil, now: baseDate))
        XCTAssertNil(ClaudeUsageFetcher.parseRetryAfter("", now: baseDate))
        XCTAssertNil(ClaudeUsageFetcher.parseRetryAfter("-5", now: baseDate))
        XCTAssertNil(ClaudeUsageFetcher.parseRetryAfter("soon", now: baseDate))
        XCTAssertEqual(
            ClaudeUsageFetcher.parseRetryAfter("Thu, 01 Jan 1970 00:00:00 GMT", now: baseDate),
            0
        )
    }

    // MARK: - Transport failures

    func testTimeoutIsNetworkFailure() {
        let harness = makeHarness(
            token: token(),
            results: [HTTPJSONResult(statusCode: nil, headers: [:], json: nil, error: URLError(.timedOut))]
        )
        XCTAssertNil(harness.fetcher.payload(updatedAt: 1))
        XCTAssertEqual(harness.fetcher.lastFailure, .networkError)
    }

    func testServerErrorIsServerFailure() {
        let harness = makeHarness(
            token: token(),
            results: [HTTPJSONResult(statusCode: 503, headers: [:], json: nil, error: nil)]
        )
        XCTAssertNil(harness.fetcher.payload(updatedAt: 1))
        XCTAssertEqual(harness.fetcher.lastFailure, .serverError)
    }

    // MARK: - Stale payload retention

    func testLastGoodPayloadServedStaleDuringRateLimit() throws {
        let harness = makeHarness(token: token(), results: [success(usageJSON())])
        _ = try XCTUnwrap(harness.fetcher.payload(updatedAt: 1))

        harness.state.now = baseDate.addingTimeInterval(300)
        harness.state.tokens = [token()]
        harness.state.results = [
            HTTPJSONResult(statusCode: 429, headers: ["Retry-After": "1800"], json: nil, error: nil)
        ]

        let stale = try XCTUnwrap(harness.fetcher.payload(updatedAt: 2))
        XCTAssertEqual(stale["available"] as? Bool, true)
        XCTAssertEqual(stale["stale"] as? Bool, true)
        XCTAssertEqual(stale["source"] as? String, "oauth-api-stale")
        XCTAssertEqual(stale["currentSessionRemainingPercent"] as? Double, 69.0)

        // Still stale — and still no extra request — while blocked.
        harness.state.now = baseDate.addingTimeInterval(600)
        let stillStale = try XCTUnwrap(harness.fetcher.payload(updatedAt: 3))
        XCTAssertEqual(stillStale["stale"] as? Bool, true)
        XCTAssertEqual(harness.state.requests.count, 2)
    }

    func testLastGoodPayloadServedStaleAfterNetworkFailure() throws {
        let harness = makeHarness(token: token(), results: [success(usageJSON())])
        _ = try XCTUnwrap(harness.fetcher.payload(updatedAt: 1))

        harness.state.tokens = [token()]
        harness.state.results = [
            HTTPJSONResult(statusCode: nil, headers: [:], json: nil, error: URLError(.notConnectedToInternet))
        ]
        let stale = try XCTUnwrap(harness.fetcher.payload(updatedAt: 2))
        XCTAssertEqual(stale["stale"] as? Bool, true)
    }

    // MARK: - Token expiry

    func testExpiredCachedTokenTriggersFreshReadBeforeRequest() throws {
        let expired = token(expiresAt: baseDate.addingTimeInterval(-100))
        let harness = makeHarness(token: expired, results: [success(usageJSON())])
        harness.state.tokens.append(
            ClaudeUsageFetcher.Token(value: "fresh-token", expiresAt: baseDate.addingTimeInterval(3600))
        )

        let payload = try XCTUnwrap(harness.fetcher.payload(updatedAt: 1))
        XCTAssertEqual(payload["available"] as? Bool, true)
        XCTAssertEqual(harness.state.invalidateCount, 1)
        XCTAssertEqual(
            harness.state.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer fresh-token"
        )
    }

    func testExpiredTokenWithoutFreshReplacementSendsNoRequest() {
        let expired = token(expiresAt: baseDate.addingTimeInterval(-100))
        let harness = makeHarness(token: expired, results: [])
        harness.state.tokens.append(expired)

        XCTAssertNil(harness.fetcher.payload(updatedAt: 1))
        XCTAssertEqual(harness.fetcher.lastFailure, .tokenExpired)
        XCTAssertTrue(harness.state.requests.isEmpty)
    }

    func testMissingTokenIsNoTokenFailureWithoutRequest() {
        let harness = makeHarness(token: nil, results: [])
        XCTAssertNil(harness.fetcher.payload(updatedAt: 1))
        XCTAssertEqual(harness.fetcher.lastFailure, .noToken)
        XCTAssertTrue(harness.state.requests.isEmpty)
    }

    // MARK: - Secret hygiene

    func testLogsNeverContainTokenValue() {
        let scenarios: [[HTTPJSONResult]] = [
            [success(usageJSON())],
            [HTTPJSONResult(statusCode: 401, headers: [:], json: nil, error: nil)],
            [HTTPJSONResult(statusCode: 429, headers: ["Retry-After": "60"], json: nil, error: nil)],
            [HTTPJSONResult(statusCode: nil, headers: [:], json: nil, error: URLError(.timedOut))]
        ]

        for results in scenarios {
            let harness = makeHarness(token: token(), results: results)
            harness.state.tokens.append(token())
            _ = harness.fetcher.payload(updatedAt: 1)
            for line in harness.state.logs {
                XCTAssertFalse(line.contains(secretToken), "token leaked into log: \(line)")
            }
        }
    }
}
