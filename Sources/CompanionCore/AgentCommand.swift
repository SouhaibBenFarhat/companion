import Foundation

/// Which coding-agent CLI (command line interface) drives the answers.
///
/// Companion never calls a model API (Application Programming Interface)
/// itself. It spawns one of these, which already holds your subscription
/// login — so there is no key to store and nothing to leak.
public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex

    /// Name of the binary on disk, used when searching the usual install spots.
    public var executableName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        }
    }

    public var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

/// How much the agent is allowed to do to the repo it is pointed at.
public enum AgentPermission: String, Codable, CaseIterable, Sendable {
    /// Answer questions and read the repo, but never change a file.
    /// The sensible default while pairing — you don't want an assistant
    /// editing the code you are demonstrating.
    case readOnly
    /// Let it edit files without asking each time.
    case acceptEdits

    public var title: String {
        switch self {
        case .readOnly: return "Read only"
        case .acceptEdits: return "Allow edits"
        }
    }
}

/// An argument list for one headless agent run.
///
/// Split out from the process spawning so the interesting part — which flags
/// go where — is unit-testable without launching anything.
public struct AgentCommand: Equatable, Sendable {
    public let executable: URL
    public let arguments: [String]
    public let workingDirectory: URL
    /// Written to the child's standard input instead of appearing in `arguments`.
    ///
    /// Process arguments are readable by every process running as the same
    /// user — `ps` shows them. The prompt carries the call transcript, the text
    /// of the focused window and the page being viewed, so putting it in argv
    /// published a live transcript of a private conversation to the whole
    /// machine. Standard input is not visible that way.
    public let standardInput: String?

    public init(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        standardInput: String? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.standardInput = standardInput
    }
}

/// Builds the argument list for a headless run of the chosen agent.
public enum AgentCommandBuilder {
    /// - Parameters:
    ///   - sessionID: the agent's own session, handed back on the first event
    ///     of a run. Passing it on the next question is what makes follow-ups
    ///     like "no, do it the other way" work — otherwise the agent starts
    ///     blank and re-reads the whole repo.
    ///   - systemPrompt: appended to the agent's own system prompt, never
    ///     replacing it. This is where the "you are answering live during a
    ///     call, be brief" instruction goes.
    public static func build(
        kind: AgentKind,
        executable: URL,
        prompt: String,
        workingDirectory: URL,
        sessionID: String? = nil,
        systemPrompt: String? = nil,
        permission: AgentPermission = .readOnly
    ) -> AgentCommand {
        let arguments: [String]
        switch kind {
        case .claude:
            arguments = claudeArguments(
                sessionID: sessionID,
                systemPrompt: systemPrompt,
                permission: permission
            )
        case .codex:
            arguments = codexArguments(
                workingDirectory: workingDirectory,
                sessionID: sessionID,
                permission: permission
            )
        }
        return AgentCommand(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            standardInput: prompt
        )
    }

    private static func claudeArguments(
        sessionID: String?,
        systemPrompt: String?,
        permission: AgentPermission
    ) -> [String] {
        // `--verbose` is required alongside stream-json in print mode, otherwise
        // the CLI refuses to start and we get an empty panel with no reason.
        //
        // `--include-partial-messages` is what makes the answer appear a word
        // at a time instead of landing in one block at the end. Without it a
        // ten-second answer is ten seconds of nothing followed by a wall.
        // No prompt here. It goes on standard input, out of the process table.
        var arguments = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
        ]

        if let sessionID, !sessionID.isEmpty {
            arguments += ["--resume", sessionID]
        }
        if let systemPrompt, !systemPrompt.isEmpty {
            arguments += ["--append-system-prompt", systemPrompt]
        }

        switch permission {
        case .readOnly:
            // Naming the write tools is clearer than switching the whole
            // permission mode: the agent keeps its normal behaviour and simply
            // cannot change files. Reading and searching still work.
            arguments += ["--disallowedTools", "Edit,Write,NotebookEdit"]
        case .acceptEdits:
            arguments += ["--permission-mode", "acceptEdits"]
        }

        return arguments
    }

    private static func codexArguments(
        workingDirectory: URL,
        sessionID: String?,
        permission: AgentPermission
    ) -> [String] {
        var arguments = ["exec"]

        // Codex resumes through a subcommand rather than a flag.
        if let sessionID, !sessionID.isEmpty {
            arguments += ["resume", sessionID]
        }

        arguments += ["--json", "--cd", workingDirectory.path]

        switch permission {
        case .readOnly:
            arguments += ["--sandbox", "read-only"]
        case .acceptEdits:
            arguments += ["--sandbox", "workspace-write"]
        }

        // The prompt is written to standard input, not appended here.
        arguments.append("-")
        return arguments
    }
}

/// The default instruction appended to whichever agent runs.
///
/// The single biggest quality win in the app: agents default to a thorough,
/// essay-shaped answer, which is unreadable in a panel you glance at while
/// talking to someone.
public enum DefaultSystemPrompt {
    public static let text = """
        You are answering inside a small floating panel while the user is on a \
        live call, sharing their screen. They are talking to another person at \
        the same time and can only glance at you.

        Lead with the answer in the first sentence. Two or three sentences is \
        usually the whole reply. Use a code block only when the user asks for \
        code. No preamble, no restating the question, no closing summary.
        """
}
