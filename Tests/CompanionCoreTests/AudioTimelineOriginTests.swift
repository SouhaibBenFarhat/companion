import XCTest
@testable import CompanionCore

/// The arithmetic behind "Audio input timestamp overlaps or precedes prior
/// audio input" — the error that ended transcription for the rest of a call.
final class AudioTimelineOriginTests: XCTestCase {
    private let clock = HostClock(numerator: 125, denominator: 3)

    /// Hardware latency is subtracted from the capture time, so the first
    /// buffers of a session sit just before the origin. A negative start reads
    /// to the analyzer as preceding input it has already taken.
    func testTheFirstBufferCanLandBeforeTheOrigin() {
        let origin: UInt64 = 1_000_000
        let timeline = AudioTimeline(originHostTime: origin, clock: clock)

        // A buffer captured a moment after listening began, minus 20ms of
        // hardware delay.
        let latency = clock.ticks(fromSeconds: 0.02)
        let captured = origin + clock.ticks(fromSeconds: 0.005) - latency

        XCTAssertLessThan(timeline.seconds(for: captured, speaker: .me), 0)
    }

    /// A rebuild that took a fresh origin sent audio back to zero while the
    /// analyzer was still holding the earlier part of the call.
    func testAFreshOriginSendsTimeBackwards() {
        let start: UInt64 = 1_000_000
        let thirtySeconds = clock.ticks(fromSeconds: 30)

        let first = AudioTimeline(originHostTime: start, clock: clock)
        let atThirty = first.seconds(for: start + thirtySeconds, speaker: .me)
        XCTAssertEqual(atThirty, 30, accuracy: 0.001)

        // What a rebuild used to do: a new origin, taken now.
        let rebuilt = AudioTimeline(originHostTime: start + thirtySeconds, clock: clock)
        let sameMoment = rebuilt.seconds(for: start + thirtySeconds, speaker: .me)
        XCTAssertEqual(sameMoment, 0, accuracy: 0.001)
        XCTAssertLessThan(sameMoment, atThirty, "the clock went backwards")
    }

    /// Keeping the origin is what makes a rebuild invisible to the analyzer.
    func testKeepingTheOriginKeepsTimeMovingForwards() {
        let start: UInt64 = 1_000_000
        let timeline = AudioTimeline(originHostTime: start, clock: clock)

        var last = -Double.infinity
        for second in stride(from: 0.0, through: 60.0, by: 0.5) {
            let now = timeline.seconds(for: start + clock.ticks(fromSeconds: second), speaker: .me)
            XCTAssertGreaterThan(now, last)
            last = now
        }
    }
}
