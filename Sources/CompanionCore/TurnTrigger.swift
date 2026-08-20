import Foundation

/// Why Companion decided to think.
public enum TurnReason: String, Equatable, Sendable {
    /// The user pressed the key. Always allowed.
    case asked
    /// The other person finished a sentence that reads like a question.
    case questionAsked
    /// The other person stopped talking and the user has not started.
    case turnHandedOver
    /// Something changed on screen that looks like a problem.
    case screenChanged
}

/// Decides when there is a reason to think, without a timer.
///
/// A clock is the wrong instrument. It fires in the middle of a sentence, wastes
/// a turn when nothing has happened, and misses the moment when things move
/// fast. Every trigger here is an event that actually occurred.
public struct TurnTrigger: Sendable {
    /// A question mark, or an opening that almost always ends in one.
    static let questionOpenings = [
        "how do", "how does", "how did", "how can", "how would", "how should",
        "what is", "what are", "what does", "what do", "what if", "what about",
        "why is", "why does", "why did", "why do",
        "where is", "where does", "when does", "when did",
        "should we", "should i", "could we", "could you", "can we", "can you",
        "do you know", "any idea", "does anyone",
    ]

    public init() {}

    /// Whether a settled line reads like a question aimed at the user.
    public func isQuestion(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return false }
        if cleaned.hasSuffix("?") { return true }
        return Self.questionOpenings.contains { cleaned.hasPrefix($0) }
    }

    /// Evaluates a new settled line from the transcript.
    ///
    /// - Parameters:
    ///   - text: what was said.
    ///   - speaker: who said it.
    ///   - userIsSpeaking: whether the user is talking right now. Interrupting
    ///     someone mid-sentence with a suggestion they cannot read is the
    ///     fastest way to get the feature turned off.
    public func evaluate(
        text: String,
        speaker: CaptureSpeaker,
        userIsSpeaking: Bool
    ) -> TurnReason? {
        // Never think about the user's own words as if they were a prompt.
        guard speaker == .them else { return nil }
        guard !userIsSpeaking else { return nil }

        if isQuestion(text) { return .questionAsked }
        return .turnHandedOver
    }
}

/// Decides whether a thought is worth showing.
///
/// The trigger says something happened. This says whether saying so is worth
/// interrupting a live conversation for — which is a different and harder
/// question, and the one that decides if the feature survives its first call.
public struct SuggestionGate: Sendable {
    /// Never more than this many unprompted suggestions per minute.
    public let maximumPerMinute: Int
    /// Never twice within this many seconds, whatever happens.
    public let minimumGap: TimeInterval
    /// How similar to the previous suggestion counts as repeating itself.
    public let noveltyThreshold: Double

    public init(maximumPerMinute: Int = 3, minimumGap: TimeInterval = 12, noveltyThreshold: Double = 0.6) {
        self.maximumPerMinute = maximumPerMinute
        self.minimumGap = minimumGap
        self.noveltyThreshold = noveltyThreshold
    }

    public struct State: Equatable, Sendable {
        public var recentTimes: [TimeInterval] = []
        public var lastText: String = ""

        public init() {}
    }

    public enum Decision: Equatable, Sendable {
        case show
        case tooSoon
        case tooMany
        case repeating
        /// The model chose silence, which is the normal case.
        case nothingToSay
    }

    public func admit(
        _ text: String,
        at now: TimeInterval,
        state: inout State
    ) -> Decision {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .nothingToSay }

        if let last = state.recentTimes.last, now - last < minimumGap { return .tooSoon }

        state.recentTimes.removeAll { now - $0 > 60 }
        if state.recentTimes.count >= maximumPerMinute { return .tooMany }

        if similarity(cleaned, state.lastText) >= noveltyThreshold { return .repeating }

        state.recentTimes.append(now)
        state.lastText = cleaned
        return .show
    }

    /// Share of words in common. Crude on purpose — it only has to catch the
    /// model saying the same thing twice in slightly different words.
    func similarity(_ left: String, _ right: String) -> Double {
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let a = Set(left.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }))
        let b = Set(right.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count))
    }
}
