import XCTest
@testable import CompanionCore

final class EchoGateTests: XCTestCase {
    private let step: TimeInterval = 0.01 // one energy reading per 10 ms
    private let gate = EchoGate()

    /// A burst of energy, as the call would produce.
    private func burst(count: Int = 200, from: Int = 20, length: Int = 60, level: Float = 0.5) -> [Float] {
        var track = [Float](repeating: 0.002, count: count)
        for index in from..<min(from + length, count) {
            // Shaped rather than flat, so correlation has something to match on.
            let position = Float(index - from) / Float(length)
            track[index] = level * (0.5 + 0.5 * sin(position * .pi))
        }
        return track
    }

    private func delayed(_ track: [Float], bySamples shift: Int, gain: Float = 0.6) -> [Float] {
        var output = [Float](repeating: 0.002, count: track.count)
        for index in 0..<track.count where index + shift < track.count {
            output[index + shift] = track[index] * gain
        }
        return output
    }

    private func inspect(microphone: [Float], call: [Float]) -> EchoGate.Verdict {
        gate.inspect(
            microphone: EchoGate.EnergyTrack(levels: microphone, secondsPerSample: step),
            call: EchoGate.EnergyTrack(levels: call, secondsPerSample: step)
        )
    }

    // MARK: - Echo, at the delays real hardware produces

    func testCatchesABuiltInSpeakerEchoAround40ms() {
        let call = burst()
        let verdict = inspect(microphone: delayed(call, bySamples: 4), call: call)
        XCTAssertTrue(verdict.isEcho)
        XCTAssertEqual(verdict.delay, 0.04, accuracy: 0.015)
    }

    func testCatchesABluetoothEchoAround150ms() {
        let call = burst()
        let verdict = inspect(microphone: delayed(call, bySamples: 15), call: call)
        XCTAssertTrue(verdict.isEcho)
        XCTAssertEqual(verdict.delay, 0.15, accuracy: 0.02)
    }

    func testCatchesASlowBluetoothEchoAround300ms() {
        let call = burst(count: 300)
        let verdict = inspect(microphone: delayed(call, bySamples: 30), call: call)
        XCTAssertTrue(verdict.isEcho)
        XCTAssertEqual(verdict.delay, 0.30, accuracy: 0.03)
    }

    // MARK: - Speech that must never be suppressed

    /// The case that matters most. Getting this wrong deletes the user from
    /// their own transcript.
    func testTheUserTalkingWhileTheCallIsSilentIsKept() {
        let speech = burst()
        let silence = [Float](repeating: 0.002, count: speech.count)
        XCTAssertFalse(inspect(microphone: speech, call: silence).isEcho)
    }

    /// The user answers over the other person and keeps talking after they
    /// stop. The overlap alone correlates; the part where only the user is
    /// speaking is what proves a second voice.
    func testBothTalkingAtOnceIsKept() {
        let call = burst(count: 300, from: 20, length: 60)
        var mic = [Float](repeating: 0.002, count: 300)
        for index in 50..<160 {
            let position = Float(index - 50) / 110
            mic[index] = 0.45 * (0.5 + 0.5 * sin(position * .pi))
        }
        XCTAssertFalse(inspect(microphone: mic, call: call).isEcho)
    }

    /// The narrow case the residual check exists for: the microphone tracks the
    /// call exactly during the overlap, then carries on alone.
    func testSpeechContinuingAfterTheCallStopsIsKept() {
        let call = burst(count: 300, from: 20, length: 60)
        var mic = delayed(call, bySamples: 5)
        for index in 120..<200 { mic[index] = 0.4 }
        XCTAssertFalse(inspect(microphone: mic, call: call).isEcho)
    }

    func testSilenceOnBothSidesIsNotAnEcho() {
        let quiet = [Float](repeating: 0.001, count: 100)
        XCTAssertFalse(inspect(microphone: quiet, call: quiet).isEcho)
    }

    /// Headphones: the call plays but nothing comes back through the mic.
    func testCallAudioWithASilentMicrophoneIsNotAnEcho() {
        let call = burst()
        let quiet = [Float](repeating: 0.001, count: call.count)
        XCTAssertFalse(inspect(microphone: quiet, call: call).isEcho)
    }

    // MARK: - Edges

    func testEmptyTracksAreSafe() {
        XCTAssertFalse(inspect(microphone: [], call: []).isEcho)
        XCTAssertFalse(inspect(microphone: [0.5], call: []).isEcho)
    }

    /// An echo arriving faster than the window can explain is not matched, so a
    /// wired headset with almost no delay cannot silence the user.
    func testADelayShorterThanTheWindowIsNotMatched() {
        let call = burst()
        let verdict = inspect(microphone: delayed(call, bySamples: 0), call: call)
        XCTAssertLessThan(verdict.delay, gate.minimumDelay + 0.02)
    }

    func testAZeroSampleRateIsSafe() {
        let verdict = gate.inspect(
            microphone: EchoGate.EnergyTrack(levels: [0.5, 0.5], secondsPerSample: 0),
            call: EchoGate.EnergyTrack(levels: [0.5, 0.5], secondsPerSample: 0)
        )
        XCTAssertFalse(verdict.isEcho)
    }
}
