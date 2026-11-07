import XCTest
@testable import ClaudeIsland

final class SessionIdentityTests: XCTestCase {

    func test_codexGuiSessionUsesCodexAgentAndGenericTerminalTag() {
        let session = SessionState(
            sessionId: UUID().uuidString,
            cwd: "/tmp/test",
            projectName: "test",
            terminalApp: "Codex"
        )

        XCTAssertEqual(session.agentTag, "Codex")
        XCTAssertEqual(session.terminalTag, "Terminal")
    }

    func test_cmuxSessionWinsOverGuiTerminalFallback() {
        var session = SessionState(
            sessionId: UUID().uuidString,
            cwd: "/tmp/test",
            projectName: "test",
            terminalApp: "Codex"
        )
        session.cmuxWorkspaceId = "ws-1"

        XCTAssertEqual(session.agentTag, "Codex")
        XCTAssertEqual(session.terminalTag, "cmux")
    }

    func test_chatgptSessionUsesGptAgentTag() {
        let session = SessionState(
            sessionId: UUID().uuidString,
            cwd: "/tmp/test",
            projectName: "test",
            terminalApp: "ChatGPT"
        )

        XCTAssertEqual(session.agentTag, "GPT")
        XCTAssertEqual(session.terminalTag, "ChatGPT")
    }
}
