import Foundation

/// The words two successive guesses agree on.
///
/// Whisper re-decodes a growing window, so each preview can rewrite the whole
/// line: "we recently added a wave" becomes "we recently added a waveform
/// debugger", and sometimes becomes something quite different before settling.
/// Showing each guess whole makes the panel flicker and makes text that was on
/// screen a moment ago disappear.
///
/// Showing only the leading words two consecutive guesses agree on — the
/// LocalAgreement policy — gives a line that only ever grows. A word appears
/// once the recogniser has said it twice, and never unsays it.
public enum AgreedPrefix {
    /// Compared by word, not by character: half of "waveform" is not a word,
    /// and putting "wavef" on screen is worse than waiting one more pass.
    ///
    /// Case and punctuation are ignored when comparing, because Whisper moves
    /// commas and capitals around between passes while the words stay put. The
    /// text returned is the newer guess's own, so its punctuation is kept.
    public static func of(_ earlier: String, _ later: String) -> String {
        let earlierWords = words(in: earlier)
        let laterWords = words(in: later)

        var agreed = 0
        while agreed < earlierWords.count, agreed < laterWords.count,
              normalise(earlierWords[agreed]) == normalise(laterWords[agreed]) {
            agreed += 1
        }

        guard agreed > 0 else { return "" }
        return laterWords[0..<agreed].joined(separator: " ")
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func normalise(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
