import XCTest
@testable import CompanionCore

final class AudioTimelineTests: XCTestCase {
    private let origin: UInt64 = 1_000_000_000

    func testConvertsHostTimeToSecondsFromTheStart() {
        let timeline = AudioTimeline(originHostTime: origin)
        XCTAssertEqual(timeline.seconds(for: origin, speaker: .me), 0, accuracy: 0.0001)
        XCTAssertEqual(timeline.seconds(for: origin + 500_000_000, speaker: .me), 0.5, accuracy: 0.0001)
    }

    /// Host time is unsigned, so a timestamp from before the origin must go
    /// negative rather than wrap to something near 18 billion.
    func testATimestampBeforeTheStartGoesNegative() {
        let timeline = AudioTimeline(originHostTime: origin)
        XCTAssertEqual(timeline.seconds(for: origin - 250_000_000, speaker: .me), -0.25, accuracy: 0.0001)
    }

    func testAppliesThePerStreamOffset() {
        let timeline = AudioTimeline(originHostTime: origin, offsets: [.me: -0.05, .them: 0.1])
        XCTAssertEqual(timeline.seconds(for: origin, speaker: .me), -0.05, accuracy: 0.0001)
        XCTAssertEqual(timeline.seconds(for: origin, speaker: .them), 0.1, accuracy: 0.0001)
    }

    func testAStreamWithNoOffsetIsUnshifted() {
        let timeline = AudioTimeline(originHostTime: origin, offsets: [.me: 0.2])
        XCTAssertEqual(timeline.seconds(for: origin, speaker: .them), 0, accuracy: 0.0001)
    }

    // MARK: - Merging

    private func segment(_ speaker: CaptureSpeaker, _ start: Double, _ end: Double) -> SpeechSegment {
        SpeechSegment(speaker: speaker, startSeconds: start, endSeconds: end)
    }

    func testMergesIntoTheOrderThingsWereSaid() {
        let merged = AudioTimeline.merge(
            [segment(.me, 1.0, 2.0), segment(.me, 5.0, 6.0)],
            [segment(.them, 0.0, 0.9), segment(.them, 3.0, 4.0)]
        )
        XCTAssertEqual(merged.map(\.speaker), [.them, .me, .them, .me])
    }

    /// People talk over each other, so overlap is normal and must not reorder.
    func testOverlappingSpeechKeepsStartOrder()  {
        let merged = AudioTimeline.merge(
            [segment(.me, 1.0, 4.0)],
            [segment(.them, 2.0, 3.0)]
        )
        XCTAssertEqual(merged.map(\.startSeconds), [1.0, 2.0])
    }

    /// When both start at the same instant it is almost always the other person
    /// still going while the user begins.
    func testAnExactTieReadsTheOtherPersonFirst() {
        let merged = AudioTimeline.merge(
            [segment(.me, 2.0, 3.0)],
            [segment(.them, 2.0, 2.5)]
        )
        XCTAssertEqual(merged.map(\.speaker), [.them, .me])
    }

    /// Segments close whenever their stream goes quiet, so they do not arrive
    /// in order.
    func testOutOfOrderArrivalIsSorted() {
        let merged = AudioTimeline.merge([
            segment(.me, 9.0, 10.0),
            segment(.me, 1.0, 2.0),
            segment(.me, 5.0, 6.0),
        ])
        XCTAssertEqual(merged.map(\.startSeconds), [1.0, 5.0, 9.0])
    }

    func testMergingNothingIsEmpty() {
        XCTAssertTrue(AudioTimeline.merge([], []).isEmpty)
    }
}
