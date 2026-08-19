import XCTest
@testable import CompanionCore

final class HostClockTests: XCTestCase {
    /// Apple Silicon: 125/3 nanoseconds per tick, about 41.67.
    private let appleSilicon = HostClock(numerator: 125, denominator: 3)

    func testTicksBecomeSecondsOnThisKindOfMachine() {
        // 24 million ticks x 41.67 ns is one second.
        XCTAssertEqual(appleSilicon.seconds(fromTicks: 24_000_000), 1.0, accuracy: 0.0001)
    }

    /// The bug this type exists for: treating ticks as nanoseconds made every
    /// duration about 41 times too small, so a two second pause between
    /// speakers became 48 milliseconds and the transcript order collapsed.
    func testTreatingTicksAsNanosecondsWouldBeFortyOneTimesWrong() {
        let ticks: UInt64 = 24_000_000
        let wrong = TimeInterval(ticks) / 1_000_000_000
        let right = appleSilicon.seconds(fromTicks: ticks)
        XCTAssertEqual(right / wrong, 125.0 / 3.0, accuracy: 0.01)
    }

    func testRoundTripsThroughSeconds() {
        let ticks = appleSilicon.ticks(fromSeconds: 0.25)
        XCTAssertEqual(appleSilicon.seconds(fromTicks: ticks), 0.25, accuracy: 0.0001)
    }

    func testNegativeSecondsGiveNoTicks() {
        XCTAssertEqual(appleSilicon.ticks(fromSeconds: -1), 0)
    }

    /// A zero denominator would divide by zero on every single sample.
    func testADegenerateTimebaseCannotDivideByZero() {
        let broken = HostClock(numerator: 0, denominator: 0)
        XCTAssertEqual(broken.seconds(fromTicks: 1_000_000_000), 1.0, accuracy: 0.0001)
        XCTAssertFalse(broken.seconds(fromTicks: 1).isNaN)
    }

    func testTheTimelineUsesTheClock() {
        let timeline = AudioTimeline(originHostTime: 0, clock: appleSilicon)
        XCTAssertEqual(timeline.seconds(for: 24_000_000, speaker: .me), 1.0, accuracy: 0.0001)
    }

    func testTheTimelineStillHandlesTimeBeforeTheOrigin() {
        let timeline = AudioTimeline(originHostTime: 24_000_000, clock: appleSilicon)
        XCTAssertEqual(timeline.seconds(for: 0, speaker: .me), -1.0, accuracy: 0.0001)
    }
}
