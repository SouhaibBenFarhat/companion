import Foundation

/// Commits words as soon as two passes agree, instead of waiting for the
/// speaker to stop.
///
/// Whisper is not a streaming recogniser: it takes a block and returns text for
/// all of it. The obvious way to use it live — wait for a pause, decode, show
/// the result — puts the text as far behind the speech as the block is long. At
/// a fifteen second cap that is fifteen seconds, and a transcript that far
/// behind a live call is not much use.
///
/// LocalAgreement is the accepted way round it (Macháček, Dabre and Bojar,
/// 2023, and the `whisper_streaming` implementation): decode the growing buffer
/// often, and treat a word as settled the moment two consecutive decodes agree
/// on it. Whisper revises its own guesses as it hears more, so agreement across
/// two passes is a good proxy for "it will not change its mind again".
///
/// Latency stops depending on how long somebody talks and becomes the gap
/// between decodes plus one decode — about two and a half seconds here.
public struct LocalAgreement: Sendable {
    /// Words already handed over as settled. Never re-sent.
    private var committed: [String] = []
    /// The previous pass, to agree against.
    private var previous: [String] = []

    public init() {}

    /// What to settle and what to show as still-changing.
    public struct Step: Equatable, Sendable {
        /// Newly settled words. Empty when this pass agreed with nothing new.
        public let settled: String
        /// The tail the recogniser is still revising.
        public let pending: String
    }

    /// Offers the latest decode of the growing buffer.
    public mutating func offer(_ text: String) -> Step {
        let words = Self.words(in: text)

        var agreed = 0
        while agreed < words.count, agreed < previous.count,
              Self.same(words[agreed], previous[agreed]) {
            agreed += 1
        }
        previous = words

        // A later pass can be shorter, or can revise a word already sent. Only
        // ever move forwards: unsaying something on screen is the thing this
        // exists to avoid.
        let alreadySent = min(committed.count, words.count)
        var settled: [String] = []
        if agreed > alreadySent {
            settled = Array(words[alreadySent..<agreed])
            committed = Array(words[0..<agreed])
        }

        let tailStart = max(agreed, alreadySent)
        let pending = tailStart < words.count ? Array(words[tailStart...]) : []

        return Step(settled: settled.joined(separator: " "), pending: pending.joined(separator: " "))
    }

    /// The speaker stopped. Everything not yet settled is settled now — there
    /// will be no further pass to agree with.
    public mutating func finish(_ text: String) -> String {
        let words = Self.words(in: text)
        let alreadySent = min(committed.count, words.count)
        let rest = alreadySent < words.count ? Array(words[alreadySent...]) : []
        reset()
        return rest.joined(separator: " ")
    }

    public mutating func reset() {
        committed = []
        previous = []
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Case and punctuation are ignored: Whisper moves commas and capitals
    /// between passes while the words themselves stay put.
    private static func same(_ one: String, _ two: String) -> Bool {
        one.lowercased().filter { $0.isLetter || $0.isNumber }
            == two.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
