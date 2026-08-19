import Foundation

/// Which side of the call a sound came from.
///
/// Labelled at the source rather than worked out afterwards. Two separate
/// capture paths — the microphone and what the Mac plays — means no speaker
/// diarization is needed to tell you from the person you are talking to, which
/// is the single largest simplification in the whole design.
public enum CaptureSpeaker: String, Codable, CaseIterable, Sendable {
    case me
    case them

    public var title: String {
        switch self {
        case .me: return "You"
        case .them: return "The call"
        }
    }
}

/// A block of audio, already converted to the transcriber's format.
///
/// PCM is pulse code modulation — plain uncompressed samples. Mono `Float`
/// between -1 and 1.
public struct PCMChunk: Equatable, Sendable {
    public let speaker: CaptureSpeaker
    /// Mach host time of the first frame, in nanoseconds.
    ///
    /// The two streams come from different devices with unrelated clocks, so
    /// this is the only thing that lets their transcripts be interleaved in the
    /// order the words were actually said.
    public let hostTimeNanoseconds: UInt64
    public let sampleRate: Double
    public let samples: [Float]

    public init(speaker: CaptureSpeaker, hostTimeNanoseconds: UInt64, sampleRate: Double, samples: [Float]) {
        self.speaker = speaker
        self.hostTimeNanoseconds = hostTimeNanoseconds
        self.sampleRate = sampleRate
        self.samples = samples
    }

    public var frameCount: Int { samples.count }

    public var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }

    public var endHostTimeNanoseconds: UInt64 {
        hostTimeNanoseconds &+ UInt64(duration * 1_000_000_000)
    }

    /// Root mean square, the honest measure of loudness for a meter.
    ///
    /// Peak would make a meter jump on a single click; this tracks what a
    /// person hears.
    public var level: Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }
}
