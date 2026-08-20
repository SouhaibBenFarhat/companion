import Foundation

/// One thing somebody said.
public struct TranscriptEntry: Equatable, Identifiable, Sendable {
    public let id: String
    public let speaker: CaptureSpeaker
    public let startSeconds: TimeInterval
    public var text: String
    /// Still being revised. The recogniser rewrites these as it hears more.
    public var isVolatile: Bool

    public init(
        id: String = UUID().uuidString,
        speaker: CaptureSpeaker,
        startSeconds: TimeInterval,
        text: String,
        isVolatile: Bool = false
    ) {
        self.id = id
        self.speaker = speaker
        self.startSeconds = startSeconds
        self.text = text
        self.isVolatile = isVolatile
    }
}

/// The rolling record of a conversation.
///
/// Two streams arrive independently and out of order, and each carries two
/// kinds of result: settled text, and a tail the recogniser is still revising.
/// Getting the second kind wrong is what produces a transcript with every
/// sentence in it twice — so each speaker has exactly one replaceable tail
/// rather than a growing list of near-duplicates.
///
/// Nothing here is written to disk. A window of a few minutes is what a live
/// conversation needs, and an hour of someone else's words is not ours to keep.
public struct TranscriptBuffer: Equatable, Sendable {
    /// How much conversation to hold, in seconds.
    public var windowSeconds: TimeInterval

    private var settled: [TranscriptEntry] = []
    /// One per speaker, replaced wholesale on each update.
    private var volatileTails: [CaptureSpeaker: TranscriptEntry] = [:]
    /// How far through the settled text the reasoning layer has already read.
    private var sentUpTo: TimeInterval = -1

    public init(windowSeconds: TimeInterval = 300) {
        self.windowSeconds = windowSeconds
    }

    // MARK: - Adding

    /// Adds text the recogniser has committed to.
    public mutating func appendFinal(
        _ text: String,
        speaker: CaptureSpeaker,
        at startSeconds: TimeInterval,
        id: String = UUID().uuidString
    ) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        // Whatever was pending for this speaker has now settled.
        volatileTails[speaker] = nil

        settled.append(
            TranscriptEntry(
                id: id,
                speaker: speaker,
                startSeconds: startSeconds,
                text: Redaction.scrub(cleaned)
            )
        )
        settled.sort { $0.startSeconds < $1.startSeconds }
        prune()
    }

    /// Replaces the tail the recogniser is still revising.
    ///
    /// Replaced, never appended. Matching on ranges instead duplicates text
    /// every time the recogniser revises a word.
    public mutating func setVolatile(
        _ text: String,
        speaker: CaptureSpeaker,
        at startSeconds: TimeInterval
    ) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            volatileTails[speaker] = nil
            return
        }
        volatileTails[speaker] = TranscriptEntry(
            id: "volatile-\(speaker.rawValue)",
            speaker: speaker,
            startSeconds: startSeconds,
            text: Redaction.scrub(cleaned),
            isVolatile: true
        )
    }

    public mutating func clear() {
        settled = []
        volatileTails = [:]
        sentUpTo = -1
    }

    // MARK: - Reading

    /// Everything, in the order it was said, with the live tails last.
    public var entries: [TranscriptEntry] {
        (settled + volatileTails.values).sorted { left, right in
            if left.startSeconds != right.startSeconds {
                return left.startSeconds < right.startSeconds
            }
            // A settled line before a tail at the same instant: the tail is
            // still growing and belongs at the end.
            return !left.isVolatile && right.isVolatile
        }
    }

    public var isEmpty: Bool { settled.isEmpty && volatileTails.isEmpty }

    /// The last `seconds` of conversation as plain text, labelled by speaker.
    public func text(lastSeconds seconds: TimeInterval? = nil) -> String {
        let all = entries
        guard let newest = all.last?.startSeconds else { return "" }
        let floor = seconds.map { newest - $0 } ?? -.infinity

        return all
            .filter { $0.startSeconds >= floor }
            .map { "\($0.speaker.title): \($0.text)" }
            .joined(separator: "\n")
    }

    /// Settled text the reasoning layer has not been given yet.
    ///
    /// Volatile tails are deliberately excluded: sending a half-heard sentence
    /// means reasoning about words the speaker did not say.
    public func unsentText() -> String {
        settled
            .filter { $0.startSeconds > sentUpTo }
            .map { "\($0.speaker.title): \($0.text)" }
            .joined(separator: "\n")
    }

    public var hasUnsent: Bool {
        settled.contains { $0.startSeconds > sentUpTo }
    }

    /// Marks everything settled so far as read.
    public mutating func markSent() {
        sentUpTo = settled.last?.startSeconds ?? sentUpTo
    }

    /// The most recent thing said, whoever said it.
    public var lastEntry: TranscriptEntry? { entries.last }

    /// Whether the most recent settled line came from the other person, which
    /// is the usual sign that a question has just landed.
    public var lastSpeakerWasThem: Bool {
        settled.last?.speaker == .them
    }

    // MARK: - Window

    private mutating func prune() {
        guard let newest = settled.last?.startSeconds else { return }
        let floor = newest - windowSeconds
        settled.removeAll { $0.startSeconds < floor }
    }
}
