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
///
/// Two settings, and between them they must cover every case without ever
/// producing a question. Companion runs the agent headless: there is no
/// terminal, so an approval prompt has nowhere to appear and nowhere to be
/// answered. The run simply stops, and the panel shows an assistant asking the
/// user to approve something in a window that does not exist.
public enum AgentPermission: String, Codable, CaseIterable, Sendable {
    /// Read and answer. Cannot write, cannot run a shell.
    ///
    /// The default while pairing — you do not want an assistant editing the
    /// code you are demonstrating. Enforced by handing the agent only the
    /// read-only tools, not by denying the write ones: denying `Edit` and
    /// `Write` while leaving `Bash` in place is not read-only at all, and a
    /// panel set to "Read only" created a file in the user's home folder with
    /// `echo > file`.
    case readOnly
    /// No tools at all. Reads the prompt, answers, stops.
    ///
    /// For the unprompted note, which reacts to a transcript it has already
    /// been handed and has no business touching the disk. Left with reading
    /// tools and no chosen folder, it ran in the user's home directory and went
    /// looking: a note came back quoting a file on their Desktop and a
    /// conversation from another app entirely.
    case noTools
    /// Full power inside the working folder, and never a prompt.
    ///
    /// Deliberately armed: the panel asks twice before turning it on. An
    /// assistant that cannot run the tests or the build is a search box over
    /// your files, so this mode holds nothing back.
    case acceptEdits

    public var title: String {
        switch self {
        case .noTools: return "No tools"
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
    /// - Parameter jsonSchema: a shape the reply must take. The CLI turns it
    ///   into a tool the model has to call, and the runtime validates the
    ///   arguments — so the answer arrives as an object rather than as prose
    ///   that has to be parsed and hoped about. Claude only; Codex ignores it.
    public static func build(
        kind: AgentKind,
        executable: URL,
        prompt: String,
        workingDirectory: URL,
        sessionID: String? = nil,
        systemPrompt: String? = nil,
        permission: AgentPermission = .readOnly,
        jsonSchema: String? = nil
    ) -> AgentCommand {
        let arguments: [String]
        switch kind {
        case .claude:
            arguments = claudeArguments(
                sessionID: sessionID,
                systemPrompt: systemPrompt,
                permission: permission,
                jsonSchema: jsonSchema
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
        permission: AgentPermission,
        jsonSchema: String? = nil
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
        if let jsonSchema, !jsonSchema.isEmpty {
            arguments += ["--json-schema", jsonSchema]
        }

        switch permission {
        case .noTools:
            // Empty string, which is how the CLI is told to disable every tool.
            arguments += ["--tools", ""]

        case .readOnly:
            // The tools it HAS, not the tools it may not use. Denying the write
            // tools left `Bash` available, which writes perfectly well — that
            // is how a read-only panel created a file. With the list given,
            // the write tools do not exist, so nothing is denied at run time
            // and nothing can stop to ask.
            arguments += ["--tools", readOnlyTools.joined(separator: ",")]
        case .acceptEdits:
            // `acceptEdits` accepts file edits and still stops to ask before
            // running a command. Headless, that question reaches nobody and the
            // run hangs. This mode is armed on purpose, behind a confirmation,
            // and it is scoped to the working folder.
            arguments += ["--permission-mode", "bypassPermissions"]
        }

        return arguments
    }

    /// Everything that cannot change the machine.
    ///
    /// `Bash` is absent on purpose, and that is the whole point of the list.
    static let readOnlyTools = ["Read", "Grep", "Glob", "WebSearch", "WebFetch"]

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
        case .noTools:
            // Codex has no flag for "no tools", so this is the tightest it
            // offers. The note is still handed everything it needs in the
            // prompt and has no reason to reach for anything.
            arguments += ["--sandbox", "read-only"]

        case .readOnly:
            arguments += ["--sandbox", "read-only"]
        case .acceptEdits:
            // Same reason as Claude's bypass: `exec` still raises approvals for
            // anything outside the sandbox, and headless there is nobody to
            // raise them to.
            arguments += ["--sandbox", "workspace-write", "--dangerously-bypass-approvals-and-sandbox"]
        }

        // The prompt is written to standard input, not appended here.
        arguments.append("-")
        return arguments
    }
}

/// The starting value of the user's own instructions field in Settings.
///
/// Only a starting value now. What the agent is actually told about itself
/// lives in `AgentContext`, which is always sent and cannot be edited away —
/// it is the difference between an agent that knows it is in Companion and one
/// that describes itself as a terminal session.
public enum DefaultSystemPrompt {
    public static let text = AgentContext.style
}
