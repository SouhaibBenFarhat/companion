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

    // MARK: - Streaming word by word

    func testReadsATextDelta() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"1,"}}}"#
        XCTAssertEqual(
            AgentEventDecoder.decode(line: line, kind: .claude, partialMessages: true),
            [.assistantText("1,")]
        )
    }

    /// With partials on, the finished text arrives again as a whole assistant
    /// message. Taking both would print every answer twice.
    func testIgnoresTheCompleteMessageWhenStreaming() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"1, 2, 3"}]}}"#
        XCTAssertTrue(AgentEventDecoder.decode(line: line, kind: .claude, partialMessages: true).isEmpty)
    }

    /// Tool use is not in the deltas, so it still has to come from the
    /// complete message even while streaming.
    func testStillReportsToolUseWhenStreaming() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read"}]}}"#
        XCTAssertEqual(
            AgentEventDecoder.decode(line: line, kind: .claude, partialMessages: true),
            [.toolUse(name: "Read")]
        )
    }

    /// Without partials the whole message is the only copy of the answer.
    func testUsesTheCompleteMessageWhenNotStreaming() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"1, 2, 3"}]}}"#
        XCTAssertEqual(
            AgentEventDecoder.decode(line: line, kind: .claude, partialMessages: false),
            [.assistantText("1, 2, 3")]
        )
    }

    func testIgnoresNonTextDeltas() {
        let line = #"{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"}}}"#
        XCTAssertTrue(AgentEventDecoder.decode(line: line, kind: .claude, partialMessages: true).isEmpty)
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
