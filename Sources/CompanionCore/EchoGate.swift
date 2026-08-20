import Foundation

/// Spots the other person's voice leaking into the microphone.
///
/// On headphones this never happens. On speakers it always does: what the call
/// plays comes back through the microphone a few milliseconds later, so the
/// same sentence is captured on both streams and the transcript shows the user
/// saying what the other person just said.
///
/// macOS voice processing removes some of it, but only what our own engine
/// renders — it knows nothing about what Chrome is playing. So this is the
/// defence that actually holds, and it works on energy rather than audio: if
/// the microphone got loud only where the call was already loud a moment
/// earlier, that stretch is an echo.
///
/// The delay is not fixed. Built-in speakers land around 30 to 60 milliseconds;
/// Bluetooth headsets commonly 150 to 300. So a window is searched rather than
/// one value assumed.
public struct EchoGate: Sendable {
    /// Smallest delay to consider, in seconds.
    public let minimumDelay: TimeInterval
    /// Largest delay to consider. Covers Bluetooth.
    public let maximumDelay: TimeInterval
    /// How much of the microphone's energy must be explained by the call's
    /// energy before a stretch is called an echo. Above 1 would mean the
    /// microphone is louder than the source, which a real echo never is.
    public let correlationThreshold: Float
    /// Below this the microphone is quiet enough that nothing was said anyway.
    public let silenceFloor: Float
    /// How much microphone energy may appear where the delayed call is silent
    /// before the stretch is treated as somebody actually talking.
    ///
    /// This is the check that protects the user from being deleted out of their
    /// own transcript. Correlation alone cannot separate an echo from two
    /// voices that happen to rise and fall together — but an echo is only ever
    /// an attenuated copy, so it cannot carry energy the source did not have.
    /// Speech in the gaps means a second person.
    public let residualTolerance: Float

    public init(
        minimumDelay: TimeInterval = 0.02,
        maximumDelay: TimeInterval = 0.35,
        correlationThreshold: Float = 0.62,
        silenceFloor: Float = 0.012,
        residualTolerance: Float = 0.22
    ) {
        self.minimumDelay = minimumDelay
        self.maximumDelay = maximumDelay
        self.correlationThreshold = correlationThreshold
        self.silenceFloor = silenceFloor
        self.residualTolerance = residualTolerance
    }

    /// A run of energy readings, evenly spaced.
    public struct EnergyTrack: Sendable {
        public let levels: [Float]
        public let secondsPerSample: TimeInterval

        public init(levels: [Float], secondsPerSample: TimeInterval) {
            self.levels = levels
            self.secondsPerSample = secondsPerSample
        }
    }

    public struct Verdict: Equatable, Sendable {
        public let isEcho: Bool
        /// The delay that explained it best, in seconds.
        public let delay: TimeInterval
        public let correlation: Float
    }

    /// Decides whether the microphone track is a delayed copy of the call track.
    public func inspect(microphone: EnergyTrack, call: EnergyTrack) -> Verdict {
        let quiet = Verdict(isEcho: false, delay: 0, correlation: 0)

        guard !microphone.levels.isEmpty, !call.levels.isEmpty,
              microphone.secondsPerSample > 0
        else { return quiet }

        // Nothing was said into the microphone, so nothing to suppress.
        let micEnergy = mean(microphone.levels)
        guard micEnergy >= silenceFloor else { return quiet }

        // The call was silent, so the microphone cannot be echoing it. This is
        // the case that keeps the user's own speech: they talk, the call does
        // not, and no delay can explain it.
        guard mean(call.levels) >= silenceFloor else { return quiet }

        let minimumShift = Int((minimumDelay / microphone.secondsPerSample).rounded())
        let maximumShift = Int((maximumDelay / microphone.secondsPerSample).rounded())
        guard maximumShift > minimumShift else { return quiet }

        var bestShift = minimumShift
        var bestScore: Float = 0
        for shift in minimumShift...maximumShift {
            let score = correlation(microphone.levels, call.levels, shift: shift)
            guard score > bestScore else { continue }
            bestScore = score
            bestShift = shift
        }

        // Shape alone is not enough. An echo is an attenuated copy, so it can
        // carry no energy the source did not have. If the microphone is loud in
        // the gaps where the delayed call is quiet, that is a person speaking.
        let looksLikeACopy = bestScore >= correlationThreshold
        let residual = residualEnergy(microphone.levels, call.levels, shift: bestShift)

        return Verdict(
            isEcho: looksLikeACopy && residual <= residualTolerance,
            delay: TimeInterval(bestShift) * microphone.secondsPerSample,
            correlation: bestScore
        )
    }

    /// Share of the microphone's energy sitting where the delayed call is
    /// silent. Zero means every loud moment is explained by the call.
    private func residualEnergy(_ microphone: [Float], _ call: [Float], shift: Int) -> Float {
        let count = min(microphone.count, call.count - shift)
        guard count > 0, shift >= 0 else { return 1 }

        var unexplained: Float = 0
        var total: Float = 0
        for index in 0..<count {
            let mic = microphone[index + shift]
            total += mic
            if call[index] < silenceFloor { unexplained += mic }
        }
        guard total > 0 else { return 0 }
        return unexplained / total
    }

    /// Normalised similarity between the microphone and the call delayed by
    /// `shift` samples. 1 means the same shape, 0 means unrelated.
    private func correlation(_ microphone: [Float], _ call: [Float], shift: Int) -> Float {
        let count = min(microphone.count, call.count - shift)
        guard count > 1, shift >= 0 else { return 0 }

        var dot: Float = 0
        var micSquared: Float = 0
        var callSquared: Float = 0

        for index in 0..<count {
            let mic = microphone[index + shift]
            let source = call[index]
            dot += mic * source
            micSquared += mic * mic
            callSquared += source * source
        }

        let denominator = (micSquared * callSquared).squareRoot()
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }

    private func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }
}
