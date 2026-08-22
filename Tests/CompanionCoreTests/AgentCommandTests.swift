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

    /// Read only is a list of the tools it HAS, not of the ones it may not
    /// use. Denying `Edit` and `Write` left `Bash` in place, and `echo > file`
    /// writes just as well — a panel set to Read only created a file in the
    /// user's home folder.
    func testClaudeReadOnlyHandsOverOnlyTheReadingTools() throws {
        let arguments = build(permission: .readOnly).arguments
        let index = try XCTUnwrap(arguments.firstIndex(of: "--tools"))
        let tools = arguments[index + 1].split(separator: ",").map(String.init)

        XCTAssertEqual(tools, AgentCommandBuilder.readOnlyTools)
        for forbidden in ["Bash", "Edit", "Write", "NotebookEdit"] {
            XCTAssertFalse(tools.contains(forbidden), "\(forbidden) can change the machine")
        }
        XCTAssertTrue(tools.contains("Read"))
    }

    /// Headless, an approval prompt reaches nobody and the run stops with the
    /// panel showing an assistant asking the user to confirm something in a
    /// window that does not exist. `acceptEdits` accepts file edits and still
    /// asks before running a command, so it is not enough on its own.
    func testClaudeCanEditNeverStopsToAsk() throws {
        let arguments = build(permission: .acceptEdits).arguments
        let index = try XCTUnwrap(arguments.firstIndex(of: "--permission-mode"))
        XCTAssertEqual(arguments[index + 1], "bypassPermissions")
        XCTAssertFalse(arguments.contains("--tools"), "the armed mode holds nothing back")
    }

    /// Neither mode may ever produce a question.
    func testNoModeCanRaiseAPromptWithNowhereToGo() {
        for permission in AgentPermission.allCases {
            let arguments = build(permission: permission).arguments
            XCTAssertFalse(arguments.contains("default"), "\(permission) would prompt")
            if permission == .readOnly {
                XCTAssertTrue(arguments.contains("--tools"))
            } else {
                XCTAssertTrue(arguments.contains("bypassPermissions"))
            }
        }
    }

    // MARK: - Codex

    func testCodexCanEditNeverStopsToAsk() {
        let arguments = build(kind: .codex, permission: .acceptEdits).arguments
        XCTAssertTrue(arguments.contains("--dangerously-bypass-approvals-and-sandbox"))
    }

    func testCodexReadOnlyStaysSandboxed() {
        let arguments = build(kind: .codex, permission: .readOnly).arguments
        let index = arguments.firstIndex(of: "--sandbox")
        XCTAssertEqual(arguments[index! + 1], "read-only")
        XCTAssertFalse(arguments.contains("--dangerously-bypass-approvals-and-sandbox"))
    }

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
