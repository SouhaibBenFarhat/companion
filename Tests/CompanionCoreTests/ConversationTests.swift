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

extension ConversationTests {
    /// A call fills the record before anyone types, so the title has to come
    /// from the first typed question rather than the first message.
    func testTitleComesFromTheFirstTypedQuestion() {
        var conversation = Conversation(repositoryPath: "/tmp", agent: .claude)
        conversation.append(Message(role: .spokenByCall, text: "so what do you think about the retry limit"))
        conversation.append(Message(role: .spokenByUser, text: "not sure yet"))
        XCTAssertTrue(conversation.title.isEmpty)

        conversation.append(Message(role: .user, text: "what is their retry limit?"))
        XCTAssertEqual(conversation.title, Conversation.title(fromFirstMessage: "what is their retry limit?"))
    }

    /// Speech is kept, and keeps who said it.
    func testSpokenMessagesSurviveARoundTrip() throws {
        var conversation = Conversation(repositoryPath: "/tmp", agent: .claude)
        conversation.append(Message(role: .spokenByUser, text: "I got a bit too deep into the rabbit hole."))
        conversation.append(Message(role: .spokenByCall, text: "Right."))

        let restored = try JSONDecoder().decode(
            Conversation.self, from: JSONEncoder().encode(conversation)
        )
        XCTAssertEqual(restored.messages.map(\.role), [.spokenByUser, .spokenByCall])
        XCTAssertEqual(restored.messages.first?.role.speaker, .me)
        XCTAssertTrue(restored.messages.allSatisfy(\.role.isSpoken))
    }
}

extension ConversationTests {
    /// A note has to land after the line that prompted it. Held in its own
    /// list, it could only ever be drawn after every line — including the ones
    /// it was about.
    func testANoteSitsWhereItHappened() {
        var conversation = Conversation(repositoryPath: "/tmp", agent: .claude)
        conversation.append(Message(role: .spokenByCall, text: "closures capture by reference"))
        conversation.append(Message(role: .noticed, text: "They mean by value for primitives."))
        conversation.append(Message(role: .spokenByCall, text: "so same input, same output"))

        XCTAssertEqual(
            conversation.messages.map(\.role),
            [.spokenByCall, .noticed, .spokenByCall]
        )
    }

    func testDismissingANoteRemovesIt() {
        var conversation = Conversation(repositoryPath: "/tmp", agent: .claude)
        conversation.append(Message(role: .spokenByCall, text: "keep me"))
        let note = Message(role: .noticed, text: "dismiss me")
        conversation.append(note)

        conversation.remove(id: note.id)

        XCTAssertEqual(conversation.messages.map(\.text), ["keep me"])
    }

    func testRemovingSomethingThatIsNotThereChangesNothing() {
        var conversation = Conversation(repositoryPath: "/tmp", agent: .claude)
        conversation.append(Message(role: .user, text: "hello"))
        conversation.remove(id: "not-a-real-id")
        XCTAssertEqual(conversation.messages.count, 1)
    }

    /// A note is not speech, and must not claim a speaker.
    func testANoteHasNoSpeaker() {
        XCTAssertNil(MessageRole.noticed.speaker)
        XCTAssertFalse(MessageRole.noticed.isSpoken)
    }
}
