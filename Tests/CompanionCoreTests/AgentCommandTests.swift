import XCTest
@testable import CompanionCore

final class AgentCommandTests: XCTestCase {
    private let executable = URL(fileURLWithPath: "/usr/local/bin/claude")
    private let repository = URL(fileURLWithPath: "/Users/me/code/project")

    private func build(
        kind: AgentKind = .claude,
        prompt: String = "why is this failing?",
        sessionID: String? = nil,
        systemPrompt: String? = nil,
        permission: AgentPermission = .readOnly
    ) -> AgentCommand {
        AgentCommandBuilder.build(
            kind: kind,
            executable: executable,
            prompt: prompt,
            workingDirectory: repository,
            sessionID: sessionID,
            systemPrompt: systemPrompt,
            permission: permission
        )
    }

    // MARK: - Claude

    func testClaudeRunsHeadlessWithStreamingJSON() {
        let command = build()
        XCTAssertEqual(command.executable, executable)
        XCTAssertEqual(command.workingDirectory, repository)
        XCTAssertEqual(command.arguments.first, "-p")
        XCTAssertTrue(command.arguments.contains("--output-format"))
        XCTAssertTrue(command.arguments.contains("stream-json"))
    }

    /// Process arguments are readable by every process running as the same
    /// user. The prompt carries the call transcript and the text of whatever
    /// window is focused, so argv would publish a private conversation to the
    /// whole machine.
    func testThePromptNeverAppearsInTheArguments() {
        let secret = "the customer said their password is hunter2"
        let command = build(prompt: secret)

        XCTAssertFalse(command.arguments.contains(secret))
        XCTAssertFalse(command.arguments.joined(separator: " ").contains("hunter2"))
        XCTAssertEqual(command.standardInput, secret)
    }

    func testCodexAlsoTakesThePromptOnStandardInput() {
        let command = build(kind: .codex, prompt: "sensitive text")
        XCTAssertFalse(command.arguments.contains("sensitive text"))
        XCTAssertEqual(command.standardInput, "sensitive text")
        // A bare dash tells it to read the prompt from standard input.
        XCTAssertEqual(command.arguments.last, "-")
    }

    /// stream-json in print mode is rejected without --verbose, which would
    /// leave the panel empty with no visible reason.
    func testClaudePassesVerboseAlongsideStreamJSON() {
        XCTAssertTrue(build().arguments.contains("--verbose"))
    }

    /// Without this the answer lands in one block at the end instead of
    /// appearing as it is written.
    func testClaudeAsksForPartialMessages() {
        XCTAssertTrue(build().arguments.contains("--include-partial-messages"))
    }

    func testClaudeOmitsResumeForANewConversation() {
        XCTAssertFalse(build(sessionID: nil).arguments.contains("--resume"))
        XCTAssertFalse(build(sessionID: "").arguments.contains("--resume"))
    }

    func testClaudeResumesAnExistingSession() {
        let arguments = build(sessionID: "sess-123").arguments
        let index = arguments.firstIndex(of: "--resume")
        XCTAssertNotNil(index)
        XCTAssertEqual(arguments[index! + 1], "sess-123")
    }

    func testClaudeAppendsTheSystemPromptRatherThanReplacingIt() {
        let arguments = build(systemPrompt: "be brief").arguments
        let index = arguments.firstIndex(of: "--append-system-prompt")
        XCTAssertNotNil(index)
        XCTAssertEqual(arguments[index! + 1], "be brief")
        XCTAssertFalse(arguments.contains("--system-prompt"))
    }

    func testClaudeReadOnlyBlocksTheWriteTools() {
        let arguments = build(permission: .readOnly).arguments
        let index = arguments.firstIndex(of: "--disallowedTools")
        XCTAssertNotNil(index)
        XCTAssertEqual(arguments[index! + 1], "Edit,Write,NotebookEdit")
    }

    func testClaudeAcceptEditsDoesNotBlockTools() {
        let arguments = build(permission: .acceptEdits).arguments
        XCTAssertFalse(arguments.contains("--disallowedTools"))
        let index = arguments.firstIndex(of: "--permission-mode")
        XCTAssertNotNil(index)
        XCTAssertEqual(arguments[index! + 1], "acceptEdits")
    }

    // MARK: - Codex

    func testCodexRunsExecWithJSONOutput() {
        let arguments = build(kind: .codex).arguments
        XCTAssertEqual(arguments.first, "exec")
        XCTAssertTrue(arguments.contains("--json"))
    }

    func testCodexIsToldTheWorkingDirectory() {
        let arguments = build(kind: .codex).arguments
        let index = arguments.firstIndex(of: "--cd")
        XCTAssertNotNil(index)
        XCTAssertEqual(arguments[index! + 1], repository.path)
    }

    func testCodexResumesThroughTheSubcommand() {
        let arguments = build(kind: .codex, sessionID: "thread-9").arguments
        XCTAssertEqual(Array(arguments.prefix(3)), ["exec", "resume", "thread-9"])
    }

    func testCodexMapsPermissionOntoTheSandbox() {
        let readOnly = build(kind: .codex, permission: .readOnly).arguments
        XCTAssertEqual(readOnly[readOnly.firstIndex(of: "--sandbox")! + 1], "read-only")

        let editing = build(kind: .codex, permission: .acceptEdits).arguments
        XCTAssertEqual(editing[editing.firstIndex(of: "--sandbox")! + 1], "workspace-write")
    }

    /// A prompt starting with a dash cannot be mistaken for a flag when it
    /// never reaches the argument list.
    func testAPromptThatLooksLikeAFlagIsSafe() {
        let command = build(kind: .codex, prompt: "--help me")
        XCTAssertFalse(command.arguments.contains("--help me"))
        XCTAssertEqual(command.standardInput, "--help me")
    }

    func testDefaultSystemPromptAsksForShortAnswers() {
        XCTAssertTrue(DefaultSystemPrompt.text.contains("Lead with the answer"))
        XCTAssertFalse(DefaultSystemPrompt.text.isEmpty)
    }
}
