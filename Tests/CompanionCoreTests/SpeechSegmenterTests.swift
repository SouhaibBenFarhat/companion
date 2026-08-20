import XCTest
@testable import CompanionCore

final class SpeechSegmenterTests: XCTestCase {
    private let frame: TimeInterval = 0.1
    private let loud: Float = 0.4
    private let quiet: Float = 0.001

    /// Feeds a pattern of levels, one per 100 ms, and collects what closes.
    private func run(
        _ levels: [Float],
        segmenter: SpeechSegmenter = SpeechSegmenter(),
        flush: Bool = true
    ) -> [SpeechSegment] {
        var state = SpeechSegmenter.State()
        var segments: [SpeechSegment] = []
        for (index, level) in levels.enumerated() {
            if let segment = segmenter.consume(
                level: level,
                at: Double(index) * frame,
                duration: frame,
                state: &state
            ) {
                segments.append(segment)
            }
        }
        if flush, let last = segmenter.flush(state: &state) { segments.append(last) }
        return segments
    }

    func testSilenceProducesNothing() {
        XCTAssertTrue(run([Float](repeating: quiet, count: 30)).isEmpty)
    }

    func testOneUtterance() {
        let levels = [Float](repeating: quiet, count: 3)
            + [Float](repeating: loud, count: 10)
            + [Float](repeating: quiet, count: 12)

        let segments = run(levels)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].startSeconds, 0.3, accuracy: 0.001)
        XCTAssertEqual(segments[0].duration, 1.0, accuracy: 0.001)
    }

    /// The whole reason the hangover window exists. Speech has gaps inside it,
    /// and closing on the first quiet frame chops every sentence into pieces.
    func testAShortGapStaysOneSegment() {
        let levels = [Float](repeating: loud, count: 5)
            + [Float](repeating: quiet, count: 2) // 200 ms, inside the window
            + [Float](repeating: loud, count: 5)
            + [Float](repeating: quiet, count: 12)

        XCTAssertEqual(run(levels).count, 1)
    }

    func testALongGapSplitsInTwo() {
        let levels = [Float](repeating: loud, count: 5)
            + [Float](repeating: quiet, count: 20) // 2 s, well past the window
            + [Float](repeating: loud, count: 5)
            + [Float](repeating: quiet, count: 12)

        XCTAssertEqual(run(levels).count, 2)
    }

    /// A cough or a key press is not an utterance.
    func testTooShortToBeSpeechIsDropped() {
        let levels = [Float](repeating: quiet, count: 2)
            + [loud] // 100 ms, under the minimum
            + [Float](repeating: quiet, count: 12)

        XCTAssertTrue(run(levels).isEmpty)
    }

    /// Whatever was being said when the user pressed stop is usually the part
    /// they wanted.
    func testStoppingMidSentenceStillYieldsTheSegment() {
        let levels = [Float](repeating: loud, count: 10)
        let segments = run(levels)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].duration, 1.0, accuracy: 0.001)
    }

    func testWithoutFlushAnOpenSegmentIsNotReported() {
        XCTAssertTrue(run([Float](repeating: loud, count: 10), flush: false).isEmpty)
    }

    func testFlushingTwiceReportsOnce() {
        var state = SpeechSegmenter.State()
        let segmenter = SpeechSegmenter()
        for index in 0..<10 {
            _ = segmenter.consume(level: loud, at: Double(index) * frame, duration: frame, state: &state)
        }
        XCTAssertNotNil(segmenter.flush(state: &state))
        XCTAssertNil(segmenter.flush(state: &state))
    }

    func testTheSegmentEndsAtTheLastLoudFrameNotTheEndOfSilence() {
        let levels = [Float](repeating: loud, count: 5) + [Float](repeating: quiet, count: 15)
        let segments = run(levels)
        XCTAssertEqual(segments.count, 1)
        // 0.5 s of speech, not 0.5 plus the hangover.
        XCTAssertEqual(segments[0].endSeconds, 0.5, accuracy: 0.001)
    }
}
