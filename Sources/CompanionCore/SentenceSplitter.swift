import Foundation

/// Cuts a settled block of speech into the sentences a reader expects.
///
/// A decode window is up to fifteen seconds long, and everything in it comes
/// back as one string. Shown whole, a paragraph lands in the panel at once and
/// the next one lands on top of it, so a conversation reads as a stack of
/// walls rather than as turns taken.
///
/// Cut into sentences, each one is its own line at its own moment, which is
/// how the conversation actually happened.
public enum SentenceSplitter {
    /// Sentences, in order, with the whitespace trimmed.
    ///
    /// Splits on a full stop, question mark or exclamation mark followed by a
    /// space. Not on a full stop alone: "macOS 26.6" and "AVFoundation.framework"
    /// are one word each, and cutting them is worse than a long line.
    public static func split(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var sentences: [String] = []
        var current = ""
        var characters = Array(trimmed)

        var index = 0
        while index < characters.count {
            let character = characters[index]
            current.append(character)

            let ends = character == "." || character == "?" || character == "!"
            let followedBySpace = index + 1 < characters.count && characters[index + 1].isWhitespace
            let isLast = index == characters.count - 1

            if ends, followedBySpace || isLast {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
                current = ""
            }
            index += 1
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }

        return sentences
    }

    /// Where each sentence starts, spread across the window it came from.
    ///
    /// By length, because a long sentence took longer to say. Approximate on
    /// purpose: the alternative is word-level timestamps from the recogniser,
    /// which cost a second decode pass to gain a precision nobody reading a
    /// transcript can use. What matters is that the order is right and two
    /// speakers interleave correctly.
    public static func times(
        for sentences: [String],
        from startSeconds: TimeInterval,
        over duration: TimeInterval
    ) -> [TimeInterval] {
        guard !sentences.isEmpty else { return [] }
        let total = sentences.reduce(0) { $0 + max(1, $1.count) }
        guard total > 0, duration > 0 else {
            return sentences.indices.map { startSeconds + Double($0) * 0.001 }
        }

        var times: [TimeInterval] = []
        var consumed = 0
        for sentence in sentences {
            times.append(startSeconds + duration * Double(consumed) / Double(total))
            consumed += max(1, sentence.count)
        }
        return times
    }
}
