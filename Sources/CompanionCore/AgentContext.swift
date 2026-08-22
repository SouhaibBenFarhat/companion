import Foundation

/// What the agent is told about its own situation, before anything else.
///
/// Without this the agent answers from its own system prompt, which says it is
/// a command line tool running in a terminal. Asked what it is, it described a
/// terminal session and a working directory the user had never chosen. None of
/// that is wrong from where the agent sits — it simply had not been told
/// otherwise, and every instruction Companion sent it was about how to write,
/// not about where it was.
///
/// Appended, never replacing: the agent keeps its own tools and rules.
public enum AgentContext {
    /// - Parameters:
    ///   - repository: the folder the process is actually started in.
    ///   - hasRepository: whether the user chose that folder, or it is the
    ///     home-folder fallback. The difference matters enormously in an
    ///     answer, so it is stated rather than left to be inferred.
    ///   - watching: what Companion can currently see and hear, when awareness
    ///     is on. Empty otherwise.
    ///   - extra: the user's own instructions from Settings.
    public static func systemPrompt(
        repository: URL,
        hasRepository: Bool,
        isListening: Bool = false,
        watching: String = "",
        extra: String = ""
    ) -> String {
        var parts: [String] = [situation, capabilities(isListening: isListening)]

        if hasRepository {
            parts.append("""
                You are running in \(repository.path). That folder is the \
                project the user is working on; "this repo" means that folder \
                and nothing outside it.
                """)
        } else {
            parts.append("""
                No project folder has been chosen yet, so you were started in \
                the user's home folder, \(repository.path). It is not a \
                project. Do not describe it as one, do not explore it, and if \
                the user asks anything about "this repo" or their code, say \
                they need to pick a folder first — the folder button is in the \
                panel header and in Settings.
                """)
        }

        if !watching.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(watching)
        }

        parts.append(style)

        let trimmedExtra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedExtra.isEmpty, trimmedExtra != style {
            parts.append(trimmedExtra)
        }

        return parts.joined(separator: "\n\n")
    }

    /// Who and where. First, because everything else depends on it.
    static let situation = """
        You are running inside Companion, a small floating panel on the user's \
        Mac. You are not in a terminal and the user is not typing commands at \
        you; they type a question into a chat box and read your answer in the \
        panel. Say "Companion", not "the terminal", if you are asked what you \
        are running in.

        The panel floats above whatever the user is doing and is hidden from \
        screen sharing, so the person they are talking to cannot see you. That \
        is the point of the app: the user is usually pairing or on a video \
        call, sharing their screen, and needs a second opinion nobody else in \
        the meeting can see.
        """

    /// What the app around it can do, and what it is doing right now.
    ///
    /// Without this the agent answers about itself from its own system prompt,
    /// which describes a command line tool with no ears. Asked "can you listen
    /// to calls and help me answer in real time" — the thing Companion is for —
    /// it said no, it could only see what was typed into the chat box. It was
    /// not wrong about the CLI. It had simply never been told what it was
    /// plugged into.
    static func capabilities(isListening: Bool) -> String {
        let now = isListening
            ? """
                Listening is ON right now. The user's microphone and the other \
                side's audio are both being captured and transcribed, and the \
                recent transcript is included with their questions. You are \
                also being told which window they are working in.
                """
            : """
                Listening is OFF right now, so you can only see what the user \
                types. If they ask you to follow a call, do not tell them you \
                cannot hear — tell them to click the microphone button in the \
                panel, next to the agent name.
                """

        return """
            What Companion can do, so that you describe yourself accurately \
            rather than describing a command line tool:

            - Listen to a call. It records the user's microphone and the other \
              person's audio separately, straight out of the call app, and \
              transcribes both live on this machine. Nothing is uploaded.
            - Watch the screen. It reads the text of the window in front — the \
              file being edited, the page being viewed — and can attach a \
              picture of it on request.
            - Speak up unprompted, when the user turns that on, if something \
              said on the call is worth interrupting for.

            \(now)
            """
    }

    /// How to write, given that the reader is mid-conversation with a person.
    public static let style = """
        Lead with the answer in the first sentence. Two or three sentences is \
        usually the whole reply. Use a code block only when the user asks for \
        code. No preamble, no restating the question, no closing summary.
        """
}
