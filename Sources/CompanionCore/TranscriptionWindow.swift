import Foundation

/// A stretch of one speaker's audio, ready to decode.
public struct TranscriptionWindow: Equatable, Sendable {
    public let speaker: CaptureSpeaker
    /// Mono Float samples at 16 kHz.
    public let samples: [Float]
    /// Where this window begins on the session clock, in seconds.
    ///
    /// Measured from the mach host time of the chunk that opened it, not
    /// counted from a running total — a dropped ring buffer would make a
    /// running total drift, and the two speakers would drift apart.
    public let startSeconds: TimeInterval
    /// False while the speaker is still talking: a preview, to be replaced.
    public let isClosed: Bool

    public var duration: TimeInterval { Double(samples.count) / 16_000 }
}

/// Cuts one stream into windows a non-streaming recogniser can decode.
///
/// Whisper is not a streaming recogniser: it takes a block of audio and returns
/// text for all of it. Something has to decide where the block ends, and
/// cutting on a fixed timer splits words in half — which destroys exactly the
/// long identifiers this engine was chosen for.
///
/// So the cut is made on silence, using `SpeechSegmenter`, which is already
/// tested and stays untouched. This type adds the two things the segmenter has
/// no concept of: it holds the samples, and it never lets a window grow past
/// `maximumSeconds`.
///
/// Measured on this Mac (M4 Pro, large-v3-turbo, vocabulary prompt on,
/// `temperatureFallbackCount: 0`): a fresh 3 s window decodes in 0.77 s, 10 s
/// in 0.95 s, 15 s in 1.10 s, 20 s in 1.29 s. The cap is what keeps that true.
public struct TranscriptionWindower: Sendable {
    public static let sampleRate: Double = 16_000

    public let speaker: CaptureSpeaker
    /// Hard cap. A window closes here whether or not anybody stopped talking.
    ///
    /// 15 s, not 30. Three reasons, all measured or read: decode cost rises
    /// with window length; a window longer than 30 s costs a second encoder
    /// pass; and the decoder can only sample `Constants.maxTokenContext - 1`
    /// (223) positions in total, of which the vocabulary prompt already spends
    /// 40-60, so a long dense window silently loses its tail.
    public let maximumSeconds: TimeInterval
    /// Windows shorter than this are a cough or a key press, not speech.
    public let minimumSeconds: TimeInterval
    /// Audio kept from before the first loud chunk, so the first syllable is
    /// not clipped off the front of the window.
    public let prerollSeconds: TimeInterval
    /// How much audio a preview needs before it is worth decoding one.
    public let previewEverySeconds: TimeInterval

    private let segmenter: SpeechSegmenter

    public init(
        speaker: CaptureSpeaker,
        maximumSeconds: TimeInterval = 15,
        minimumSeconds: TimeInterval = 0.4,
        prerollSeconds: TimeInterval = 0.3,
        previewEverySeconds: TimeInterval = 1.5,
        // Shorter than SpeechSegmenter's 0.7 default. That value was tuned for
        // a level meter, where being late costs nothing. Here it is the floor
        // on how long a settled line takes to appear, and a settled line is
        // what triggers a suggestion and what reaches the agent prompt.
        segmenter: SpeechSegmenter = SpeechSegmenter(hangover: 0.45)
    ) {
        self.speaker = speaker
        self.maximumSeconds = maximumSeconds
        self.minimumSeconds = minimumSeconds
        self.prerollSeconds = prerollSeconds
        self.previewEverySeconds = previewEverySeconds
        self.segmenter = segmenter
    }

    /// Mutable position within one stream.
    public struct State: Equatable, Sendable {
        var segmenter = SpeechSegmenter.State()
        /// Audio for the window being built, or the pre-roll while idle.
        var samples: [Float] = []
        /// Session seconds of the first sample in `samples`.
        var startSeconds: TimeInterval = 0
        /// Stream seconds, only ever used to drive the segmenter. Counted from
        /// audio, so it is monotonic even if the session clock is not.
        var elapsed: TimeInterval = 0
        /// How long `samples` was when the last preview was taken.
        var previewedAt: Int = 0

        public init() {}
    }

    /// Feeds one chunk in. Returns a window when one has just closed.
    ///
    /// - Parameters:
    ///   - samples: 16 kHz mono, already converted.
    ///   - level: the chunk's loudness, the same number the meters use, so the
    ///     segmenter's threshold means what it was tuned to mean.
    ///   - sessionSeconds: where this chunk starts on the shared clock.
    public func consume(
        samples: [Float],
        level: Float,
        at sessionSeconds: TimeInterval,
        state: inout State
    ) -> TranscriptionWindow? {
        guard !samples.isEmpty else { return nil }
        let duration = Double(samples.count) / Self.sampleRate

        let wasSpeaking = state.segmenter.speaking
        // The returned segment is thrown away on purpose: it carries a hardcoded
        // `.me` speaker and stream-relative times, and neither is what this
        // needs. What matters is the state transition it drives.
        _ = segmenter.consume(
            level: level,
            at: state.elapsed,
            duration: duration,
            state: &state.segmenter
        )
        state.elapsed += duration
        let isSpeaking = state.segmenter.speaking

        if isSpeaking {
            if !wasSpeaking {
                // Opening. Whatever pre-roll is in hand belongs to this window,
                // and the window starts that far before this chunk.
                let preroll = Double(state.samples.count) / Self.sampleRate
                state.startSeconds = sessionSeconds - preroll
                state.previewedAt = 0
            }
            state.samples.append(contentsOf: samples)

            guard Double(state.samples.count) / Self.sampleRate >= maximumSeconds else { return nil }
            return close(&state, forced: true)
        }

        if wasSpeaking {
            // Just went quiet. The hangover silence goes in too: Whisper reads
            // a trailing pause as the end of a sentence and punctuates it.
            state.samples.append(contentsOf: samples)
            return close(&state, forced: false)
        }

        // Idle. Keep only enough to catch the start of the next word.
        state.samples.append(contentsOf: samples)
        let keep = Int(prerollSeconds * Self.sampleRate)
        if state.samples.count > keep {
            state.samples.removeFirst(state.samples.count - keep)
        }
        return nil
    }

    /// The window as it stands, for a live preview, or nil when there is not
    /// enough new audio to be worth a decode.
    ///
    /// Whisper gives nothing back until it is asked, so the volatile line that
    /// `SpeechAnalyzer` produced for free has to be bought by re-decoding the
    /// open window. `previewEverySeconds` is what stops that costing more than
    /// it is worth.
    public func preview(_ state: inout State) -> TranscriptionWindow? {
        guard state.segmenter.speaking else { return nil }
        let sinceLast = Double(state.samples.count - state.previewedAt) / Self.sampleRate
        guard sinceLast >= previewEverySeconds,
              Double(state.samples.count) / Self.sampleRate >= minimumSeconds
        else { return nil }

        state.previewedAt = state.samples.count
        return TranscriptionWindow(
            speaker: speaker,
            samples: state.samples,
            startSeconds: state.startSeconds,
            isClosed: false
        )
    }

    /// Closes whatever is open when the stream stops.
    ///
    /// Without this, whatever was being said when the user pressed stop is
    /// thrown away — which is usually the part they wanted.
    public func flush(_ state: inout State) -> TranscriptionWindow? {
        guard state.segmenter.speaking else { return nil }
        state.segmenter.speaking = false
        return close(&state, forced: false)
    }

    /// - Parameter forced: true when the cap ended the window rather than a
    ///   pause. The segmenter stays in its speaking state so the next window
    ///   continues the same sentence.
    private func close(_ state: inout State, forced: Bool) -> TranscriptionWindow? {
        let samples = state.samples
        let start = state.startSeconds
        state.samples = []
        state.previewedAt = 0
        if forced {
            // The next window begins where this one ended.
            state.startSeconds = start + Double(samples.count) / Self.sampleRate
        }

        guard Double(samples.count) / Self.sampleRate >= minimumSeconds else { return nil }
        return TranscriptionWindow(
            speaker: speaker,
            samples: samples,
            startSeconds: start,
            isClosed: true
        )
    }
}

/// What Whisper writes when nobody is talking.
///
/// Measured on this Mac: three seconds of digital silence came back as
/// "Thank you." and three seconds of very quiet noise as ".". Both are
/// non-empty strings, so `TranscriptBuffer.appendFinal`'s empty check lets them
/// through, they count as a settled line, and they can trip the suggestion
/// trigger into interrupting a call about nothing.
///
/// Filtered here rather than in `TranscriptBuffer`, which is shared with the
/// Apple engine and does not have this problem.
public enum TranscriptionNoise {
    private static let filler: Set<String> = [
        "thank you", "thanks for watching", "thank you for watching",
        "you", "bye", "bye.", "okay", "so",
        "[blank_audio]", "(silence)", "[silence]", "[music]", "(upbeat music)",
    ]

    /// True when this line is an artefact rather than something somebody said.
    public static func isFiller(_ text: String) -> Bool {
        let bare = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,-"))
            .lowercased()
        if bare.isEmpty { return true }
        return filler.contains(bare)
    }

    /// Whether the recogniser fell into a loop.
    ///
    /// Whisper's worst failure is not mishearing a word, it is repeating one:
    /// a window it cannot make sense of comes back as "and type, and type, and
    /// type" for a hundred words. Its own defence is the compression-ratio
    /// check, which retries the decode at a higher temperature — and that is
    /// switched on. This is the second line, because the first can miss, and
    /// what it lets through does not look like a mistake to a reader. It looks
    /// like the other person said it.
    ///
    /// Judged on distinct words rather than on repeated phrases: a loop always
    /// collapses to a tiny vocabulary spread over a long line, whatever the
    /// length of the phrase it is stuck on.
    public static func isRepetitionLoop(_ text: String, minimumWords: Int = 24) -> Bool {
        let words = text
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        // Short lines repeat honestly. "no, no, no" is something people say.
        guard words.count >= minimumWords else { return false }

        let distinct = Set(words).count
        // Real speech of this length runs well above a third distinct words,
        // even at its most repetitive. A loop sits near a tenth.
        return Double(distinct) / Double(words.count) < 0.22
    }
}
