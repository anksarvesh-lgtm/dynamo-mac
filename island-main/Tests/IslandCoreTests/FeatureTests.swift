import Foundation
@testable import IslandCore

private struct FakeProvider: SearchProvider {
    let id: String
    let category: SearchCategory
    var timeout: TimeInterval = 1
    var delay: TimeInterval = 0
    var fail: SearchError?
    var titles: [String] = ["a"]
    func search(_ r: SearchRequest) async throws -> [SearchResult] {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        if let fail { throw fail }
        return titles.map { SearchResult(id: "\(id)-\($0)", category: category, providerID: id, title: $0) }
    }
}

private struct FakeAI: AIProvider {
    let name = "fake"
    let reply: String
    func complete(system: String, messages: [AIMessage], maxTokens: Int) async throws -> String { reply }
}

@MainActor
func registerFeatureTests() {
    let S = "Search"

    test(S, "router prefixes") {
        expectEqual(SearchRouter.route("web swift").scope, .only(.web))
        expectEqual(SearchRouter.route("f report").query, "report")
        expectEqual(SearchRouter.route("ask why is the sky blue").scope, .only(.ai))
        expectEqual(SearchRouter.route("safari").scope, .all)
        expectEqual(SearchRouter.route("web ").scope, .all) // empty remainder isn't a scope
    }

    test(S, "all-scope excludes AI providers") {
        let ps: [any SearchProvider] = [FakeProvider(id: "w", category: .web), FakeProvider(id: "ai", category: .ai)]
        expectEqual(SearchRouter.providers(for: SearchRouter.route("x"), from: ps).map(\.id), ["w"])
    }

    test(S, "slow provider times out without blocking others") {
        let engine = SearchEngine(providers: [FakeProvider(id: "fast", category: .application),
                                              FakeProvider(id: "slow", category: .web, timeout: 0.2, delay: 5)])
        let start = Date()
        var outcomes: [String: Bool] = [:]
        for await o in engine.search("q") {
            if case .success = o.result { outcomes[o.providerID] = true } else { outcomes[o.providerID] = false }
            if o.providerID == "slow", case .failure(let e) = o.result { expectEqual(e, .timeout) }
        }
        expectEqual(outcomes, ["fast": true, "slow": false])
        expect(Date().timeIntervalSince(start) < 1.5, "took too long")
    }

    test(S, "failing provider is isolated") {
        let engine = SearchEngine(providers: [FakeProvider(id: "ok", category: .application),
                                              FakeProvider(id: "bad", category: .web, fail: .rateLimited(retryAfter: 3))])
        var ok = 0, failed = 0
        for await o in engine.search("q") { if case .success = o.result { ok += 1 } else { failed += 1 } }
        expectEqual(ok, 1); expectEqual(failed, 1)
    }

    test(S, "cancellation stops the stream") {
        let engine = SearchEngine(providers: [FakeProvider(id: "slow", category: .web, timeout: 10, delay: 5)])
        let task = Task { var n = 0; for await _ in engine.search("q") { n += 1 }; return n }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let start = Date()
        _ = await task.value
        expect(Date().timeIntervalSince(start) < 1)
    }

    test(S, "empty query yields nothing") {
        var n = 0
        for await _ in SearchEngine(providers: [FakeProvider(id: "a", category: .application)]).search("   ") { n += 1 }
        expectEqual(n, 0)
    }

    test(S, "results are capped to limit") {
        let engine = SearchEngine(providers: [FakeProvider(id: "a", category: .application, titles: (0..<20).map(String.init))])
        for await o in engine.search("q", limit: 3) { if case .success(let r) = o.result { expectEqual(r.count, 3) } }
    }

    test(S, "ranker ordering") {
        expect(SearchRanker.score("Safari", query: "saf") > SearchRanker.score("Notes Safari", query: "saf"))
        expect(SearchRanker.score("Visual Studio Code", query: "vsc") > 0)
        expect(SearchRanker.score("Visual Studio Code", query: "code") > SearchRanker.score("Xcode", query: "zzz"))
        expectEqual(SearchRanker.score("Mail", query: "xyz"), 0)
    }

    test(S, "error mapping") {
        expectEqual(SearchError.from(URLError(.timedOut)), .timeout)
        expectEqual(SearchError.from(URLError(.cancelled)), .cancelled)
        expectEqual(SearchError.from(CancellationError()), .cancelled)
    }

    let W = "Web"

    test(W, "wikipedia parsing strips markup") {
        let json: [String: Any] = ["query": ["search": [["title": "Swift (programming language)", "snippet": "<span class=\"searchmatch\">Swift</span> is &amp; fast", "timestamp": "2026-01-01T00:00:00Z"]]]]
        let r = WikipediaSearchProvider.parse(json, language: "en")
        expectEqual(r.count, 1)
        expectEqual(r.first?.snippet, "Swift is & fast")
        expectEqual(r.first?.domain, "en.wikipedia.org")
        expect(r.first?.url?.absoluteString.contains("Swift_(programming_language)") == true)
        expect(r.first?.timestamp != nil)
    }

    test(W, "duckduckgo parsing flattens topics") {
        let json: [String: Any] = ["Heading": "Swift", "AbstractText": "A language", "AbstractURL": "https://en.wikipedia.org/wiki/Swift",
                                   "RelatedTopics": [["Text": "Swift UI - framework", "FirstURL": "https://duckduckgo.com/SwiftUI"],
                                                     ["Name": "group", "Topics": [["Text": "Taylor Swift - singer", "FirstURL": "https://duckduckgo.com/Taylor"]]]]]
        let r = DuckDuckGoProvider.parse(json, limit: 5)
        expectEqual(r.map(\.title), ["Swift", "Swift UI", "Taylor Swift"])
    }

    test(W, "malformed JSON produces no results, never fabricated ones") {
        expect(WikipediaSearchProvider.parse(["nope": 1], language: "en").isEmpty)
        expect(DuckDuckGoProvider.parse("garbage", limit: 5).isEmpty)
        expect(BraveSearchProvider.parse([String: Any]()).isEmpty)
    }

    test(W, "html extraction") {
        let html = "<html><head><title>Hello &amp; World</title><script>var x=1</script></head><body><nav>menu menu menu menu menu menu</nav><p>This is a long enough paragraph of readable text to keep.</p></body></html>"
        expectEqual(HTMLTextExtractor.title(html), "Hello & World")
        let t = HTMLTextExtractor.text(html)
        expect(t.contains("readable text") && !t.contains("var x") && !t.contains("menu"))
        expectEqual(HTMLTextExtractor.decodeEntities("&#65;&#x42;"), "AB")
    }

    let A = "AI"

    test(A, "invented citations are removed") {
        let src = [ResearchEngine.Source(index: 1, title: "One", url: URL(string: "https://a.com")!, text: "x"),
                   ResearchEngine.Source(index: 2, title: "Two", url: URL(string: "https://b.com")!, text: "y")]
        let a = ResearchEngine.finalize("Fact one [1]. Fake [7]. Fact two [2][1].", sources: src)
        expect(!a.text.contains("[7]"))
        expectEqual(a.citations.map(\.index), [1, 2])
        let none = ResearchEngine.finalize("No sources [1].", sources: [])
        expect(none.citations.isEmpty && !none.text.contains("[1]") && !none.usedWeb)
    }

    test(A, "dedupe by url and domain") {
        let r = ["https://a.com/x#top", "https://www.a.com/x?utm_source=z", "https://a.com/y", "https://a.com/z", "https://b.com/"].map {
            SearchResult(id: $0, category: .web, providerID: "t", title: $0, url: URL(string: $0))
        }
        expectEqual(ResearchEngine.dedupe(r).map(\.id), ["https://a.com/x#top", "https://a.com/y", "https://b.com/"])
    }

    test(A, "research without web needs no search") {
        let engine = ResearchEngine(ai: FakeAI(reply: "Here is a poem [1]"), search: { _ in
            [SearchResult(id: "x", category: .web, providerID: "t", title: "x", snippet: "should not be used", url: URL(string: "https://x.com"))]
        })
        let a = try await engine.answer("write a poem about rain")
        expect(a.citations.isEmpty && !a.usedWeb)
        expect(!a.text.contains("[1]"))
    }

    test(A, "anthropic response parsing") {
        let ok = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"Hi"}],"stop_reason":"end_turn"}"#.data(using: .utf8)!
        expectEqual(try AnthropicProvider.parse(ok, status: 200), "Hi")
        let refusal = #"{"content":[],"stop_reason":"refusal","stop_details":{"category":"cyber"}}"#.data(using: .utf8)!
        do { _ = try AnthropicProvider.parse(refusal, status: 200); expect(false) } catch { expectEqual(error as? AIError, .refused("cyber")) }
        let err = #"{"error":{"message":"bad key"}}"#.data(using: .utf8)!
        do { _ = try AnthropicProvider.parse(err, status: 401); expect(false) } catch { expectEqual(error as? AIError, .http(401, "bad key")) }
    }

    test(A, "missing key is a clear error, no request made") {
        do { _ = try await AnthropicProvider(apiKey: { nil }).complete(system: "", messages: [], maxTokens: 10); expect(false) }
        catch { if case .notConfigured = error as? AIError {} else { expect(false, "\(error)") } }
    }

    let R = "Actions"

    test(R, "timer phrases") {
        expectEqual(ActionRouter.parse("set timer 20 minutes").first, .startTimer(duration: 1200, label: "Timer"))
        expectEqual(ActionRouter.parse("timer 1h 30m").first, .startTimer(duration: 5400, label: "Timer"))
        if case .startTimer(let d, let l)? = ActionRouter.parse("tea timer 4 min").first { expectEqual(d, 240); expectEqual(l, "Tea") } else { expect(false) }
        expectEqual(DurationParser.parse("half an hour"), 1800)
        expectEqual(DurationParser.parse("90s"), 90)
        expectEqual(DurationParser.parse("1.5 hours"), 5400)
        expect(DurationParser.parse("timer 999 hours") == nil)
    }

    test(R, "media, web, apps, files") {
        expectEqual(ActionRouter.parse("play music"), [.media(.play)])
        expectEqual(ActionRouter.parse("next track"), [.media(.next)])
        expectEqual(ActionRouter.parse("search web for swift concurrency"), [.webSearch(query: "swift concurrency")])
        expectEqual(ActionRouter.parse("open VS Code"), [.openApplication(name: "VS Code")])
        expectEqual(ActionRouter.parse("find FAFF Governor"), [.findFile(query: "FAFF Governor")])
        expectEqual(ActionRouter.parse("open https://apple.com"), [.openURL(URL(string: "https://apple.com")!)])
        expect(ActionRouter.parse("hello there").isEmpty)
    }

    test(R, "permission policy") {
        expect(PermissionPolicy.isAllowed(.safe, origin: .ai, userConfirmed: false))
        expect(!PermissionPolicy.isAllowed(.confirm, origin: .ai, userConfirmed: true))
        expect(!PermissionPolicy.isAllowed(.confirm, origin: .automation, userConfirmed: true))
        expect(PermissionPolicy.isAllowed(.confirm, origin: .user, userConfirmed: true))
        expect(!PermissionPolicy.isAllowed(.forbidden, origin: .user, userConfirmed: true))
    }

    let U = "Automation"

    test(U, "battery threshold is edge-triggered") {
        let rules = [AutomationRule(name: "b", trigger: .batteryBelow(percent: 20), actions: [.presentIsland(seconds: 3)])]
        var st: [UUID: Bool] = [:]
        let ctx = AutomationContext(activeKinds: [])
        expectEqual(AutomationEngine.evaluate(rules, event: .batteryLevel(percent: 25, charging: false), context: ctx, state: &st).count, 0)
        expectEqual(AutomationEngine.evaluate(rules, event: .batteryLevel(percent: 19, charging: false), context: ctx, state: &st).count, 1)
        expectEqual(AutomationEngine.evaluate(rules, event: .batteryLevel(percent: 18, charging: false), context: ctx, state: &st).count, 0)
        _ = AutomationEngine.evaluate(rules, event: .batteryLevel(percent: 18, charging: true), context: ctx, state: &st)
        expectEqual(AutomationEngine.evaluate(rules, event: .batteryLevel(percent: 17, charging: false), context: ctx, state: &st).count, 1)
    }

    test(U, "conditions and disabled rules") {
        var rule = AutomationRule(name: "d", trigger: .downloadCompleted, conditions: [.activityInactive(.call), .hourBetween(start: 22, end: 7)],
                                  actions: [.presentIsland(seconds: 3)])
        var st: [UUID: Bool] = [:]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let night = Date(timeIntervalSince1970: 23 * 3600), noon = Date(timeIntervalSince1970: 12 * 3600)
        expectEqual(AutomationEngine.evaluate([rule], event: .downloadCompleted(filename: "x"), context: .init(now: night, activeKinds: [], calendar: cal), state: &st).count, 1)
        expectEqual(AutomationEngine.evaluate([rule], event: .downloadCompleted(filename: "x"), context: .init(now: noon, activeKinds: [], calendar: cal), state: &st).count, 0)
        expectEqual(AutomationEngine.evaluate([rule], event: .downloadCompleted(filename: "x"), context: .init(now: night, activeKinds: [.call], calendar: cal), state: &st).count, 0)
        rule.enabled = false
        expectEqual(AutomationEngine.evaluate([rule], event: .downloadCompleted(filename: "x"), context: .init(now: night, activeKinds: [], calendar: cal), state: &st).count, 0)
    }

    test(U, "rules round-trip through storage") {
        let d = UserDefaults(suiteName: "island.tests.\(UUID().uuidString)")!
        expectEqual(AutomationStore.load(d).count, AutomationRule.defaults.count)
        let r = [AutomationRule(name: "x", trigger: .networkChanged(connected: false), actions: [.showEvent(symbol: "wifi.slash", title: "Offline")])]
        AutomationStore.save(r, d)
        expectEqual(AutomationStore.load(d), r)
    }

    let P = "Providers"

    test(P, "media selection: newest playing wins, then recent paused") {
        let t = Date(timeIntervalSince1970: 10_000)
        typealias Src = MediaSourceSelector.Source
        expectEqual(MediaSourceSelector.select(["music": Src(state: .playing, lastPlayingAt: t), "spotify": Src(state: .playing, lastPlayingAt: t + 5)], now: t + 6), "spotify")
        expectEqual(MediaSourceSelector.select(["music": Src(state: .paused, lastPlayingAt: t + 9), "spotify": Src(state: .playing, lastPlayingAt: t)], now: t + 10), "spotify")
        expectEqual(MediaSourceSelector.select(["music": Src(state: .paused, lastPlayingAt: t)], now: t + 60), "music")
        expect(MediaSourceSelector.select(["music": Src(state: .paused, lastPlayingAt: t)], now: t + 601) == nil)
        expectEqual(MediaSourceSelector.select(["b": Src(state: .playing, lastPlayingAt: t), "a": Src(state: .playing, lastPlayingAt: t)], now: t), "a")
    }

    test(P, "battery transitions") {
        typealias R = BatteryTransitions.Reading
        var shown = Set<Int>()
        expect(BatteryTransitions.events(from: nil, to: R(level: 50, charging: false, onAC: false), shownLow: &shown).isEmpty)
        expectEqual(BatteryTransitions.events(from: R(level: 50, charging: false, onAC: false), to: R(level: 50, charging: true, onAC: true), shownLow: &shown), [.pluggedIn])
        expectEqual(BatteryTransitions.events(from: R(level: 21, charging: false, onAC: false), to: R(level: 20, charging: false, onAC: false), shownLow: &shown), [.low])
        expect(BatteryTransitions.events(from: R(level: 21, charging: false, onAC: false), to: R(level: 20, charging: false, onAC: false), shownLow: &shown).isEmpty)
        expectEqual(BatteryTransitions.events(from: R(level: 99, charging: true, onAC: true), to: R(level: 100, charging: false, onAC: true), shownLow: &shown), [.full])
    }

    test(P, "keychain round trip") {
        let svc = "io.github.poshak2004.island.tests"
        try? Keychain.set("secret", account: "t", service: svc)
        if let v = Keychain.get(account: "t", service: svc) { expectEqual(v, "secret") } // may be unavailable in CI sandboxes
        try? Keychain.set(nil, account: "t", service: svc)
        expect(Keychain.get(account: "t", service: svc) == nil)
    }
}
