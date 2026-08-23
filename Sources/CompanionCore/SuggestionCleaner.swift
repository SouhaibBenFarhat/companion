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

    /// Words that only exist in the prompt, never in an answer to it.
    static let promptMarkers = [
        "<screen>", "</screen>", "<call>", "</call>",
        "the last thing said was",
        "is there anything the user needs to know",
    ]

    /// The model reacting instead of helping. Every one of these is the
    /// assistant talking about its own state, which is never actionable.
    static let selfCommentary = [
        "i'm confused", "i am confused",
        "i'm listening", "i am listening",
        "i'm not sure what", "i am not sure what",
        "none of the names make sense",
        "i don't have enough context", "i do not have enough context",
    ]

    /// Agreeing with what was just said.
    ///
    /// "The speaker is correct — closures capture live references, not copies"
    /// is true, well written, and worthless: the speaker had just said it, so
    /// there is nothing in it the user did not already have. The instruction
    /// says never to comment on what is happening, and a model will not hold
    /// that line on wording alone.
    ///
    /// A note that contradicts the call is the opposite and is exactly what
    /// this feature is for, so only agreement is caught.
    static let agreement = [
        "the speaker is correct", "the speaker is right",
        "that's correct", "that is correct",
        "he's right", "he is right", "she's right", "she is right",
        "they're right", "they are right",
        "correct —", "correct -",
        "good point", "exactly right",
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

        // The prompt read back to you.
        //
        // The panel showed "<screen> App: Claude Window: Claude </screen>"
        // followed by "The last thing said was: ..." — the model repeating what
        // it was given instead of answering it. None of these words can appear
        // in a note about a call, so their presence anywhere is enough.
        let lowered = working.lowercased()
        for echo in promptMarkers where lowered.contains(echo) {
            return nil
        }

        // The model thinking out loud.
        //
        // "What's even "Fable 5" here lol / I'm confused about what the
        // speaker's using. I'm listening but none of the names make sense."
        // That is a reaction, not something the user can act on, and the whole
        // bar for interrupting a live call is that it can be acted on.
        for aside in selfCommentary where lowered.contains(aside) {
            return nil
        }

        // Agreeing with the call adds nothing the user did not just hear.
        for nod in agreement where lowered.hasPrefix(nod) || lowered.contains(". \(nod)") {
            return nil
        }

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
