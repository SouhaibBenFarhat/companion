import Foundation

/// Builds the text a question is wrapped in.
///
/// The agent already knows the repo — it reads the files itself. What it cannot
/// know is what was just said out loud, or which window the user is looking at.
/// So only that is supplied, and only the part it has not seen.
///
/// Kept pure so the exact shape of what gets sent is testable, which matters:
/// this is the difference between an answer about the conversation and an
/// answer about nothing.
public enum AwarenessPrompt {
    /// Wraps a typed question with whatever context is new.
    ///
    /// - Parameters:
    ///   - question: what the user typed.
    ///   - conversation: recent speech, already labelled by speaker.
    ///   - screen: what the user is looking at, if known.
    public static func build(
        question: String,
        conversation: String = "",
        screen: String = ""
    ) -> String {
        var parts: [String] = []

        let spokenText = conversation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !spokenText.isEmpty {
            parts.append("""
                <call>
                Recent speech from the call the user is on. "You" is the user, \
                "The call" is the person they are talking to. This is a live \
                transcript and may contain mistakes.

                \(spokenText)
                </call>
                """)
        }

        let screenText = screen.trimmingCharacters(in: .whitespacesAndNewlines)
        if !screenText.isEmpty {
            parts.append("""
                <screen>
                \(screenText)
                </screen>
                """)
        }

        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parts.isEmpty else { return asked }

        parts.append(asked)
        return parts.joined(separator: "\n\n")
    }

    /// Instruction for the unprompted case, where the model chooses whether to
    /// speak at all.
    ///
    /// The hard part is not answering; it is staying quiet. An assistant that
    /// remarks on everything gets switched off after one call, so the default
    /// is silence and the bar for breaking it is explicit.
    public static let watchingInstruction = """
        You are listening to a live call the user is on, and watching their \
        screen. You are not part of the conversation.

        Say nothing unless you have something the user could act on in the next \
        few seconds and would otherwise miss: a concrete answer to a question \
        just asked, a fact that contradicts what is being said, or the specific \
        cause of an error on screen.

        Never comment on what is happening. Never summarise. Never greet. \
        Never say you are here to help. If nothing meets the bar, stay silent — \
        that is the normal case and it is not a failure.

        When you do speak, lead with the answer in one sentence.
        """
}
