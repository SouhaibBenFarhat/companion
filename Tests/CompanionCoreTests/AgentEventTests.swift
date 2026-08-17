import XCTest
@testable import CompanionCore

final class AgentEventTests: XCTestCase {
    // MARK: - Claude

    func testReadsTheSessionIdentifierFromTheInitLine() {
        let line = #"{"type":"system","subtype":"init","session_id":"sess-abc","tools":["Read"]}"#
        XCTAssertEqual(AgentEventDecoder.decode(line: line, kind: .claude), [.sessionStarted(id: "sess-abc")])
    }

    func testIgnoresSystemLinesThatAreNotInit() {
        let line = #"{"type":"system","subtype":"compact_boundary","session_id":"sess-abc"}"#
        XCTAssertTrue(AgentEventDecoder.decode(line: line, kind: .claude).isEmpty)
    }

    func testReadsAssistantText() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Use a set."}]}}"#
        XCTAssertEqual(AgentEventDecoder.decode(line: line, kind: .claude), [.assistantText("Use a set.")])
    }

    /// One line can carry several blocks; dropping all but the first would
    /// silently lose part of the answer.
    func testReadsEveryBlockInOneAssistantLine() {
        let line = """
            {"type":"assistant","message":{"content":[\
            {"type":"text","text":"Checking."},\
            {"type":"tool_use","id":"t1","name":"Read","input":{}},\
            {"type":"text","text":"Found it."}]}}
            """
        XCTAssertEqual(
            AgentEventDecoder.decode(line: line, kind: .claude),
            [.assistantText("Checking."), .toolUse(name: "Read"), .assistantText("Found it.")]
        )
    }

    func testSkipsEmptyTextBlocks() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":""}]}}"#
        XCTAssertTrue(AgentEventDecoder.decode(line: line, kind: .claude).isEmpty)
    }

    func testReadsTheResultLine() {
        let line = #"{"type":"result","subtype":"success","is_error":false,"result":"Done."}"#
        XCTAssertEqual(
            AgentEventDecoder.decode(line: line, kind: .claude),
            [.finished(result: "Done.", isError: false)]
        )
    }

    func testReadsAFailingResult() {
        let line = #"{"type":"result","subtype":"error","is_error":true}"#
        XCTAssertEqual(
            AgentEventDecoder.decode(line: line, kind: .claude),
            [.finished(result: nil, isError: true)]
        )
    }

    // MARK: - Codex

    func testCodexReportsItsThreadAsTheSession() {
        let line = #"{"type":"thread.started","thread_id":"th-7"}"#
        XCTAssertEqual(AgentEventDecoder.decode(line: line, kind: .codex), [.sessionStarted(id: "th-7")])
    }

    func testCodexReadsAgentMessages() {
        let line = #"{"type":"item.completed","item":{"type":"agent_message","text":"Try -O2."}}"#
        XCTAssertEqual(AgentEventDecoder.decode(line: line, kind: .codex), [.assistantText("Try -O2.")])
    }

    func testCodexReportsTurnCompletion() {
        let line = #"{"type":"turn.completed","usage":{}}"#
        XCTAssertEqual(
            AgentEventDecoder.decode(line: line, kind: .codex),
            [.finished(result: nil, isError: false)]
        )
    }

    // MARK: - Bad input

    /// These formats change between CLI releases. A line we cannot read must
    /// produce nothing, never crash and never blank the panel.
    func testSurvivesUnusableLines() {
        for line in ["", "   ", "not json", "[]", "null", "{}", #"{"type":"mystery"}"#] {
            XCTAssertTrue(AgentEventDecoder.decode(line: line, kind: .claude).isEmpty, "for: \(line)")
            XCTAssertTrue(AgentEventDecoder.decode(line: line, kind: .codex).isEmpty, "for: \(line)")
        }
    }

    func testSurvivesTheRightTypeWithTheWrongShape() {
        let lines = [
            #"{"type":"assistant"}"#,
            #"{"type":"assistant","message":{"content":"not an array"}}"#,
            #"{"type":"system","subtype":"init"}"#,
        ]
        for line in lines {
            XCTAssertTrue(AgentEventDecoder.decode(line: line, kind: .claude).isEmpty, "for: \(line)")
        }
    }
}
