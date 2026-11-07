import Foundation

/// Minimal dependency-free test harness (the CLT toolchain on this machine lacks a working XCTest /
/// swift-testing pairing). Tests register via `suite(...)`; `main.swift` runs them.
@MainActor
final class TestKit {
    static let shared = TestKit()
    struct Case { let suite: String; let name: String; let body: @MainActor () async throws -> Void }
    private(set) var cases: [Case] = []
    var failures: [String] = []
    var currentName = ""

    func add(_ suite: String, _ name: String, _ body: @escaping @MainActor () async throws -> Void) {
        cases.append(Case(suite: suite, name: name, body: body))
    }

    func run(filter: String?) async -> Int32 {
        var passed = 0, failed = 0
        let start = Date()
        for c in cases where filter == nil || "\(c.suite).\(c.name)".localizedCaseInsensitiveContains(filter!) {
            currentName = "\(c.suite).\(c.name)"
            let before = failures.count
            do { try await c.body() } catch { failures.append("\(currentName): threw \(error)") }
            if failures.count == before { passed += 1; print("  ✓ \(currentName)") } else { failed += 1; print("  ✗ \(currentName)") }
        }
        for f in failures { print("    FAIL \(f)") }
        print(String(format: "%d passed, %d failed (%.2fs)", passed, failed, Date().timeIntervalSince(start)))
        return failed == 0 ? 0 : 1
    }
}

@MainActor
func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    if !condition() { TestKit.shared.failures.append("\(TestKit.shared.currentName) \(file):\(line) \(message())") }
}

@MainActor
func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #fileID, line: UInt = #line) {
    if a != b { TestKit.shared.failures.append("\(TestKit.shared.currentName) \(file):\(line) expected \(b), got \(a)") }
}

@MainActor
func test(_ suite: String, _ name: String, _ body: @escaping @MainActor () async throws -> Void) {
    TestKit.shared.add(suite, name, body)
}
