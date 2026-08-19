import XCTest
@testable import CompanionCore

final class AgentEnvironmentTests: XCTestCase {
    /// The bug this exists for: launched from a terminal inside a Claude Code
    /// session, the app passed these on and the agent hung forever waiting on
    /// a session socket that was not its own.
    func testDropsNestedSessionMarkers() {
        let child = AgentEnvironment.forAgent(inheriting: [
            "CLAUDECODE": "1",
            "CLAUDE_CODE_MESSAGING_SOCKET": "/tmp/sock",
            "CLAUDE_CODE_SESSION_ID": "abc",
            "CLAUDE_PID": "123",
            "HOME": "/Users/me",
        ])

        XCTAssertNil(child["CLAUDECODE"])
        XCTAssertNil(child["CLAUDE_CODE_MESSAGING_SOCKET"])
        XCTAssertNil(child["CLAUDE_CODE_SESSION_ID"])
        XCTAssertNil(child["CLAUDE_PID"])
        XCTAssertEqual(child["HOME"], "/Users/me")
    }

    func testDropsEveryClaudeCodePrefixedKey() {
        XCTAssertTrue(AgentEnvironment.isNestedSessionKey("CLAUDE_CODE_ANYTHING_NEW"))
        XCTAssertFalse(AgentEnvironment.isNestedSessionKey("CLAUDE_HOME"))
    }

    /// The bug that made the panel hang with no error: an inherited base URL
    /// switches the CLI out of subscription mode into API-key mode, and with no
    /// key it opens a session and then never answers.
    func testDropsInheritedApiConfiguration() {
        let child = AgentEnvironment.forAgent(inheriting: [
            "ANTHROPIC_BASE_URL": "https://api.anthropic.com",
            "ANTHROPIC_API_KEY": "sk-test",
            "ANTHROPIC_AUTH_TOKEN": "tok",
            "OPENAI_API_KEY": "sk-other",
            "HOME": "/Users/me",
        ])

        XCTAssertNil(child["ANTHROPIC_BASE_URL"])
        XCTAssertNil(child["ANTHROPIC_API_KEY"])
        XCTAssertNil(child["ANTHROPIC_AUTH_TOKEN"])
        XCTAssertNil(child["OPENAI_API_KEY"])
        XCTAssertEqual(child["HOME"], "/Users/me")
    }

    /// The CLI reads its own credentials from the keychain, so dropping these
    /// takes nothing away from it.
    func testLeavesUnrelatedVariablesAlone() {
        let child = AgentEnvironment.forAgent(inheriting: ["LANG": "en_GB.UTF-8", "TMPDIR": "/tmp"])
        XCTAssertEqual(child["LANG"], "en_GB.UTF-8")
        XCTAssertEqual(child["TMPDIR"], "/tmp")
    }

    func testAlwaysSetsAPathCoveringTheInstallFolders() {
        let child = AgentEnvironment.forAgent(inheriting: [:])
        XCTAssertTrue(child["PATH"]?.contains("/opt/homebrew/bin") ?? false)
    }

    func testKeepsTheInheritedPathOnTheEnd() {
        let child = AgentEnvironment.forAgent(inheriting: ["PATH": "/custom/bin"])
        XCTAssertTrue(child["PATH"]?.hasSuffix("/custom/bin") ?? false)
    }

    /// No terminal, so colour escape codes would be rendered as text.
    func testAsksForPlainOutput() {
        let child = AgentEnvironment.forAgent(inheriting: [:])
        XCTAssertEqual(child["NO_COLOR"], "1")
        XCTAssertEqual(child["TERM"], "dumb")
    }
}
