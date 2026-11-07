// SPDX-License-Identifier: MIT
// Adapted from OpenUsage (https://github.com/robinebers/openusage) at 4ce7887.
// Copyright (c) Robin Ebers and contributors. MIT License; see THIRD_PARTY_NOTICES.md.
// swift-format-ignore-file

import Foundation

/// Outcome of a Cloud Code call, split so the orchestrator can tell a genuine auth failure (refresh)
/// apart from a transient outage (try the next base URL / strategy, don't refresh).
enum CloudCodeOutcome: Sendable {
    case ok(Data)
    case authFailed
    case unavailable
}

/// All network I/O for Antigravity: the local language-server RPC (loopback HTTPS, self-signed) and the
/// Google Cloud Code endpoints.
struct AntigravityUsageClient: Sendable {
    static let lsService = "exa.language_server_pb.LanguageServerService"
    static let cloudCodeURLs = [
        "https://daily-cloudcode-pa.googleapis.com",
        "https://cloudcode-pa.googleapis.com"
    ]
    static let fetchModelsPath = "/v1internal:fetchAvailableModels"
    static let loadCodeAssistPath = "/v1internal:loadCodeAssist"
    static let retrieveQuotaPath = "/v1internal:retrieveUserQuota"
    static let quotaSummaryPath = "/v1internal:retrieveUserQuotaSummary"
    // OpenNotch: OpenUsage's Google OAuth token refresh is left out. It needs Antigravity's OAuth client
    // secret in the source; an expired token is renewed by opening Antigravity instead.
    static let lsMetadata = ["ideName": "antigravity", "extensionName": "antigravity", "ideVersion": "unknown", "locale": "en"]

    /// Loopback session that trusts the LS's self-signed cert; remote calls use full validation.
    var lsHTTP: HTTPClient
    var http: HTTPClient

    init(
        lsHTTP: HTTPClient = URLSessionHTTPClient(allowsInsecureLoopback: true),
        http: HTTPClient = URLSessionHTTPClient()
    ) {
        self.lsHTTP = lsHTTP
        self.http = http
    }

    /// Call a language-server RPC method. Returns nil on a transport failure (port not the live one).
    func callLS(scheme: String, port: Int, csrf: String, method: String) async -> HTTPResponse? {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/\(Self.lsService)/\(method)") else { return nil }
        let body = try? JSONSerialization.data(withJSONObject: ["metadata": Self.lsMetadata])
        let request = HTTPRequest(
            method: "POST",
            url: url,
            headers: [
                "Content-Type": "application/json",
                "Connect-Protocol-Version": "1",
                "x-codeium-csrf-token": csrf
            ],
            body: body,
            timeout: 10
        )
        return try? await lsHTTP.send(request)
    }

    /// POST a Cloud Code endpoint, trying each base URL in turn. A 401/403 short-circuits to `.authFailed`
    /// (same token would fail on the other base); other non-2xx / transport errors fall through to the
    /// next base and finally `.unavailable`.
    func cloudCode(path: String, token: String, userAgent: String, body: [String: String]) async -> CloudCodeOutcome {
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        for base in Self.cloudCodeURLs {
            guard let url = URL(string: base + path) else { continue }
            let request = HTTPRequest(
                method: "POST",
                url: url,
                headers: [
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "Authorization": "Bearer \(token)",
                    "User-Agent": userAgent
                ],
                body: payload,
                timeout: 15
            )
            guard let response = try? await http.send(request) else { continue }
            if response.statusCode == 401 || response.statusCode == 403 { return .authFailed }
            if (200..<300).contains(response.statusCode) { return .ok(response.body) }
        }
        return .unavailable
    }
}
