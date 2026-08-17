import XCTest
@testable import CompanionCore

final class ConversationTests: XCTestCase {
    func testTitleUsesShortQuestionsWhole() {
        XCTAssertEqual(Conversation.title(fromFirstMessage: "why is this slow?"), "why is this slow?")
    }

    func testTitleFlattensNewlines() {
        XCTAssertEqual(Conversation.title(fromFirstMessage: "why is\nthis slow?"), "why is this slow?")
    }

    func testTitleTrimsSurroundingSpace() {
        XCTAssertEqual(Conversation.title(fromFirstMessage: "  hello  "), "hello")
    }

    func testTitleFallsBackWhenThereIsNothingToUse() {
        XCTAssertEqual(Conversation.title(fromFirstMessage: "   \n  "), "New conversation")
    }

    func testTitleCutsOnAWordBoundary() {
        let text = "explain why the retry loop keeps firing twice on every failed request"
        let title = Conversation.title(fromFirstMessage: text, limit: 30)
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertLessThanOrEqual(title.count, 31)
        // Cutting mid-word would leave something like "retr…" in the sidebar.
        XCTAssertFalse(title.dropLast().hasSuffix("retr"))
    }

    func testAppendingTheFirstQuestionNamesTheThread() {
        var conversation = Conversation(repositoryPath: "/tmp/repo")
        XCTAssertEqual(conversation.title, "")
        conversation.append(Message(role: .user, text: "what does this function do?"))
        XCTAssertEqual(conversation.title, "what does this function do?")
    }

    func testLaterMessagesDoNotRenameTheThread() {
        var conversation = Conversation(repositoryPath: "/tmp/repo")
        conversation.append(Message(role: .user, text: "first question"))
        conversation.append(Message(role: .assistant, text: "an answer"))
        conversation.append(Message(role: .user, text: "second question"))
        XCTAssertEqual(conversation.title, "first question")
        XCTAssertEqual(conversation.messages.count, 3)
    }

    func testAppendingMovesTheUpdatedTimestamp() {
        let later = Date(timeIntervalSince1970: 1_800_000_000)
        var conversation = Conversation(
            repositoryPath: "/tmp/repo",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        conversation.append(Message(role: .user, text: "hi", createdAt: later))
        XCTAssertEqual(conversation.updatedAt, later)
    }

    func testCarriesTheAgentSessionSoFollowUpsKeepContext() throws {
        var conversation = Conversation(repositoryPath: "/tmp/repo")
        conversation.agentSessionID = "sess-42"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(Conversation.self, from: encoder.encode(conversation))
        XCTAssertEqual(restored.agentSessionID, "sess-42")
    }
}
