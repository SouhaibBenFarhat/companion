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
        watching: String = "",
        extra: String = ""
    ) -> String {
        var parts: [String] = [situation]

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

    /// How to write, given that the reader is mid-conversation with a person.
    public static let style = """
        Lead with the answer in the first sentence. Two or three sentences is \
        usually the whole reply. Use a code block only when the user asks for \
        code. No preamble, no restating the question, no closing summary.
        """
}
