import Foundation

/// Rejects a suggestion that is a line of dialogue rather than a note.
///
/// The transcript is handed to the model as a labelled script — "The call:
/// ...", "You: ..." — because that is what makes it readable. It also makes
/// the strongest pattern in the prompt "continue this format", and the model
/// obliges: the panel showed "Human: whats the most recent claude model?", a
/// question addressed to nobody, in a voice that was not its own.
///
/// The prompt now leads with the instruction, which helps and does not settle
/// it. This does: a label at the front means the model wrote a script line, and
/// a script line is never shown.
public enum SuggestionCleaner {
    /// Everything that marks text as a turn in a conversation.
    ///
    /// Both the transcript's own labels and the ones models reach for on their
    /// own when they think they are writing a dialogue.
    static let speakerLabels = [
        "human:", "assistant:", "user:", "ai:", "claude:", "codex:",
        "you:", "the call:", "me:", "them:", "speaker:", "system:",
    ]

    /// The note to show, or nil when the model wrote dialogue instead.
    public static func clean(_ text: String) -> String? {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return nil }

        // A leading label is removed rather than rejected outright: the
        // sentence after it is often the right answer, wearing the wrong
        // costume. Repeated, because "Human: Assistant: ..." happens.
        var strippedAny = false
        var keepGoing = true
        while keepGoing {
            keepGoing = false
            for label in speakerLabels where working.lowercased().hasPrefix(label) {
                working = String(working.dropFirst(label.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                strippedAny = true
                keepGoing = true
                break
            }
        }

        guard !working.isEmpty else { return nil }

        // More than one labelled turn is a script, and no amount of stripping
        // makes it a note.
        let labelledLines = working
            .split(separator: "\n")
            .filter { line in
                let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()
                return speakerLabels.contains { lowered.hasPrefix($0) }
            }
        if !labelledLines.isEmpty { return nil }

        // A stripped line that turns out to be a question is the model asking
        // on somebody else's behalf, not telling the user something. A note
        // that was never labelled may legitimately end in a question mark.
        if strippedAny, working.hasSuffix("?") { return nil }

        return working
    }
}
