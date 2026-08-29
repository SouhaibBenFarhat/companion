import XCTest
@testable import CompanionCore

final class ConversationExportTests: XCTestCase {
    private func conversation(messages: [Message] = []) -> Conversation {
        Conversation(
            title: "Why the retry fires twice",
            repositoryPath: "/Users/someone/code/project",
            agent: .claude,
            messages: messages
        )
    }

    // MARK: - Markdown

    func testMarkdownCarriesTitleProvenanceAndEveryMessage() {
        let exported = ConversationExport.markdown(conversation(messages: [
            Message(role: .user, text: "why is this slow?"),
            Message(role: .assistant, text: "The cache is cold."),
        ]))

        XCTAssertTrue(exported.contains("# Why the retry fires twice"))
        XCTAssertTrue(exported.contains("Repository: /Users/someone/code/project"))
        XCTAssertTrue(exported.contains("Agent: Claude Code"))
        XCTAssertTrue(exported.contains("**You**"))
        XCTAssertTrue(exported.contains("why is this slow?"))
        XCTAssertTrue(exported.contains("**Claude Code**"))
        XCTAssertTrue(exported.contains("The cache is cold."))
    }

    /// An answer is markdown already. A label glued onto the same line as the
    /// text would break the first code fence it met.
    func testACodeBlockSurvivesExportVerbatim() {
        let code = "```swift\nlet x = 1\n```"
        let exported = ConversationExport.markdown(conversation(messages: [
            Message(role: .assistant, text: code)
        ]))
        XCTAssertTrue(exported.contains(code))
    }

    /// A reader outside the app has never seen the panel's labels; the roles
    /// must explain themselves.
    func testSpokenAndNoticedLinesAreLabelledForStrangers() {
        let exported = ConversationExport.markdown(conversation(messages: [
            Message(role: .spokenByUser, text: "let me check"),
            Message(role: .spokenByCall, text: "how do polyfills work?"),
            Message(role: .noticed, text: "The flag is read at launch."),
        ]))

        XCTAssertTrue(exported.contains("**You, on the call**"))
        XCTAssertTrue(exported.contains("**The call**"))
        XCTAssertTrue(exported.contains("**Companion, unprompted**"))
    }

    /// Speech is not markdown. Quoted, a stray leading character stays part of
    /// the sentence instead of becoming document structure.
    func testSpokenLinesAreQuotedNotParsed() {
        let exported = ConversationExport.markdown(conversation(messages: [
            Message(role: .spokenByCall, text: "# of failed requests doubled")
        ]))
        XCTAssertTrue(exported.contains("> # of failed requests doubled"))
    }

    /// A reply cut off mid-stream carries an open code fence, and one open
    /// fence swallows every message after it in a renderer.
    func testAnUnbalancedFenceIsClosedBeforeTheNextMessage() {
        let exported = ConversationExport.markdown(conversation(messages: [
            Message(role: .assistant, text: "```python\ndef f():"),
            Message(role: .user, text: "and then?"),
        ]))

        let opens = exported.components(separatedBy: "\n").filter { $0.hasPrefix("```") }.count
        XCTAssertTrue(opens.isMultiple(of: 2))
        XCTAssertTrue(exported.contains("**You**"))
    }

    // MARK: - JSON

    /// The export is the storage shape: a script written against one must work
    /// against the other.
    func testJSONRoundTripsBackToAConversation() throws {
        let original = conversation(messages: [Message(role: .user, text: "hello")])
        let data = try ConversationExport.json(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.messages.map(\.text), ["hello"])
    }

    /// The agent's session id is an internal handle — enough to resume the
    /// session on this machine. A stranger reading the export has no use for
    /// it, so it stays home.
    func testTheAgentSessionIDStaysHome() throws {
        var original = conversation(messages: [Message(role: .user, text: "hello")])
        original.agentSessionID = "b1946ac9-2af1-4c3f-9a4e-000000000000"

        let json = String(decoding: try ConversationExport.json(original), as: UTF8.self)
        XCTAssertFalse(json.contains("b1946ac9"))
    }

    // MARK: - Secrets

    /// An export is the one copy that leaves Companion's folder — often to be
    /// handed to someone else. A pasted key must not travel with it.
    func testBothFormatsScrubCredentials() throws {
        let secret = "sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789"
        let thread = conversation(messages: [Message(role: .user, text: "my key is \(secret)")])

        let markdown = ConversationExport.markdown(thread)
        let json = String(decoding: try ConversationExport.json(thread), as: UTF8.self)

        XCTAssertFalse(markdown.contains(secret))
        XCTAssertFalse(json.contains(secret))
    }

    // MARK: - File names

    func testTheFileNameComesFromTheTitle() {
        let name = ConversationExport.fileName(for: conversation(), format: .markdown)
        XCTAssertEqual(name, "Why the retry fires twice.md")
    }

    /// Slashes and colons are path machinery on macOS. A title containing them
    /// must not decide where the file lands.
    func testPathCharactersCannotSteerTheFile() {
        var thread = conversation()
        thread.title = "a/b: the plan"
        let name = ConversationExport.fileName(for: thread, format: .json)
        XCTAssertEqual(name, "a-b- the plan.json")
        XCTAssertFalse(name.contains("/"))
    }

    func testAnUntitledThreadStillGetsAName() {
        var thread = conversation()
        thread.title = ""
        XCTAssertEqual(ConversationExport.fileName(for: thread, format: .markdown), "Conversation.md")
    }

    /// The title is cut from the first typed message. A pasted key must not
    /// end up as a file name in Finder — a place no scrubbing ever reaches
    /// again.
    func testASecretInTheTitleDoesNotBecomeTheFileName() {
        var thread = conversation()
        thread.title = "sk-ant-api03-abcdefghijklmnopqrstuvwxyz01234"
        let name = ConversationExport.fileName(for: thread, format: .markdown)
        XCTAssertFalse(name.contains("sk-ant-"))
    }
}
