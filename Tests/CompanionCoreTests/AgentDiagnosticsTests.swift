import XCTest
@testable import CompanionCore

final class AgentDiagnosticsTests: XCTestCase {
    /// The line that cost an afternoon: the CLI writes this to its debug file
    /// within seconds, but says nothing on stdout for over three minutes.
    func testRecognisesAnExpiredLogin() {
        let line = #"[ERROR] 401 {"type":"error","error":{"type":"authentication_error","message":"OAuth access token has expired. Re-authenticate to continue."}}"#
        XCTAssertEqual(AgentDiagnostics.classify(line), .expiredLogin)
    }

    /// The false positive that told a signed-in user to sign in: an
    /// unauthorised connector logs an authentication error of its own.
    func testIgnoresConnectorAuthErrors() {
        let log = """
            2026-08-19T11:54:31.379Z [ERROR] MCP server "claude.ai Google Drive": authentication_error
            2026-08-19T11:54:31.379Z [DEBUG] MCP server "jira": Token expired without refresh token
            2026-08-19T11:54:32.001Z [DEBUG] [API:auth] OAuth token check complete
            """
        XCTAssertNil(AgentDiagnostics.classify(log))
    }

    /// The agent's own failure still has to be caught, even in the same file
    /// as connector noise.
    func testFindsTheApiFailureAmongConnectorNoise() {
        let log = """
            2026-08-19T11:54:31.379Z [ERROR] MCP server "jira": authentication_error
            2026-08-19T11:54:33.001Z [ERROR] API error (attempt 2/11): 401 {"type":"error","error":{"type":"authentication_error","message":"OAuth access token has expired. Re-authenticate to continue."}}
            """
        XCTAssertEqual(AgentDiagnostics.classify(log), .expiredLogin)
    }

    func testRecognisesRateLimiting() {
        XCTAssertEqual(AgentDiagnostics.classify(#"[ERROR] {"type":"rate_limit_error"}"#), .rateLimited)
    }

    func testOrdinaryDebugOutputIsNotAFailure() {
        XCTAssertNil(AgentDiagnostics.classify("[DEBUG] [API:auth] OAuth token check complete"))
        XCTAssertNil(AgentDiagnostics.classify(""))
    }

    /// Both fatal cases must stop the run — retrying eleven times changes
    /// nothing and just makes the user wait.
    func testAuthAndRateLimitStopTheRun() {
        XCTAssertTrue(AgentFailure.expiredLogin.isFatal)
        XCTAssertTrue(AgentFailure.rateLimited.isFatal)
        XCTAssertFalse(AgentFailure.other("odd").isFatal)
    }

    func testExpiredLoginTellsYouWhatToDo() {
        XCTAssertTrue(AgentFailure.expiredLogin.message.contains("/login"))
    }

    func testDebugLogPathFollowsTheSessionIdentifier() {
        let url = AgentDiagnostics.debugLogURL(
            sessionID: "abc-123",
            home: URL(fileURLWithPath: "/Users/me")
        )
        XCTAssertEqual(url.path, "/Users/me/.claude/debug/abc-123.txt")
    }

    func testInspectReadsTheSessionFile() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("companion-diag-\(UUID().uuidString)")
        let debug = home.appendingPathComponent(".claude/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: debug, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try "[ERROR] API error: OAuth access token has expired. Re-authenticate to continue.".write(
            to: debug.appendingPathComponent("s1.txt"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(AgentDiagnostics.inspect(sessionID: "s1", home: home), .expiredLogin)
        XCTAssertNil(AgentDiagnostics.inspect(sessionID: "missing", home: home))
    }
}
