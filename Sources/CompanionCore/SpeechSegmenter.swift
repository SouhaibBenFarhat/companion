import Foundation

/// One stretch of someone talking.
public struct SpeechSegment: Equatable, Sendable {
    public let speaker: CaptureSpeaker
    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval

    public init(speaker: CaptureSpeaker, startSeconds: TimeInterval, endSeconds: TimeInterval) {
        self.speaker = speaker
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    public var duration: TimeInterval { endSeconds - startSeconds }
}

/// Finds where speech starts and stops in one stream.
///
/// VAD is voice activity detection. This is the cheap energy kind, not a model:
/// it drives the level meters, tells the app when the user is talking so it can
/// stay quiet, and marks utterance boundaries for the trigger layer.
///
/// It deliberately does NOT decide where transcript segments end — the speech
/// framework does that far better, using the words themselves.
///
/// The hangover window is the part that matters. Speech has gaps inside it:
/// between words, and before a consonant. Ending a segment at the first quiet
/// frame chops every sentence into fragments.
public struct SpeechSegmenter: Sendable {
    /// Root mean square above which a frame counts as speech. Ordinary room
    /// noise sits well below this; a person talking sits well above.
    public let threshold: Float
    /// How long silence must last before a segment is closed.
    public let hangover: TimeInterval
    /// Segments shorter than this are noise — a cough, a key press.
    public let minimumDuration: TimeInterval

    public init(threshold: Float = 0.012, hangover: TimeInterval = 0.7, minimumDuration: TimeInterval = 0.25) {
        self.threshold = threshold
        self.hangover = hangover
        self.minimumDuration = minimumDuration
    }

    /// Mutable position within one stream.
    public struct State: Equatable, Sendable {
        public var speaking = false
        public var segmentStart: TimeInterval = 0
        public var lastLoudAt: TimeInterval = 0

        public init() {}
    }

    /// Feeds one chunk in. Returns a segment when one has just closed.
    ///
    /// - Parameter at: the chunk's start, in seconds from the session start.
    public func consume(
        level: Float,
        at time: TimeInterval,
        duration: TimeInterval,
        state: inout State
    ) -> SpeechSegment? {
        let loud = level >= threshold
        let end = time + duration

        if loud {
            if !state.speaking {
                state.speaking = true
                state.segmentStart = time
            }
            state.lastLoudAt = end
            return nil
        }

        guard state.speaking else { return nil }
        // Still inside the hangover window: a gap between words, not the end.
        guard end - state.lastLoudAt >= hangover else { return nil }

        state.speaking = false
        let segment = SpeechSegment(
            speaker: .me,
            startSeconds: state.segmentStart,
            endSeconds: state.lastLoudAt
        )
        return segment.duration >= minimumDuration ? segment : nil
    }

    /// Closes an open segment when the stream stops.
    ///
    /// Without this, whatever was being said when the user pressed stop is
    /// thrown away — which is usually the part they wanted.
    public func flush(state: inout State) -> SpeechSegment? {
        guard state.speaking else { return nil }
        state.speaking = false
        let segment = SpeechSegment(
            speaker: .me,
            startSeconds: state.segmentStart,
            endSeconds: state.lastLoudAt
        )
        return segment.duration >= minimumDuration ? segment : nil
    }
}
