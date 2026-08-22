import XCTest
@testable import CompanionCore

final class SentenceSplitterTests: XCTestCase {
    /// Straight from the panel: fifteen seconds of speech arriving as one wall
    /// of text, with the next wall landing on top of it.
    func testCutsAWindowIntoTheSentencesThatWereSaid() {
        let window = "In this case, I'm not completely against using it. "
            + "The way a lot of us learn to program even before AI was not through "
            + "diligent study. I'm kind of curious what your policies are."

        XCTAssertEqual(SentenceSplitter.split(window).count, 3)
        XCTAssertEqual(SentenceSplitter.split(window).first, "In this case, I'm not completely against using it.")
    }

    /// A full stop is not always the end of a sentence.
    func testDoesNotCutInsideAVersionOrAFilename() {
        XCTAssertEqual(SentenceSplitter.split("it needs macOS 26.6 to build").count, 1)
        XCTAssertEqual(SentenceSplitter.split("look in AVFoundation.framework for it").count, 1)
    }

    func testKeepsQuestionsAndExclamations() {
        let split = SentenceSplitter.split("Does it work? It does! Every time.")
        XCTAssertEqual(split, ["Does it work?", "It does!", "Every time."])
    }

    func testAnUnfinishedSentenceIsStillALine() {
        XCTAssertEqual(SentenceSplitter.split("and then we"), ["and then we"])
    }

    func testSilenceProducesNothing() {
        XCTAssertTrue(SentenceSplitter.split("   \n ").isEmpty)
    }

    // MARK: - Placing them in time

    /// The order has to be right, or the two speakers interleave wrongly.
    func testTimesRunForwardsAndStayInsideTheWindow() {
        let sentences = ["Short one.", "A considerably longer sentence than the first.", "Mid."]
        let times = SentenceSplitter.times(for: sentences, from: 100, over: 12)

        XCTAssertEqual(times.count, 3)
        XCTAssertEqual(times[0], 100, accuracy: 0.001)
        XCTAssertTrue(times[0] < times[1] && times[1] < times[2])
        XCTAssertLessThan(times[2], 112)
    }

    /// A long sentence took longer to say, so the one after it starts later.
    func testALongSentencePushesTheNextOneFurtherOut() {
        let even = SentenceSplitter.times(for: ["aaaa.", "bbbb."], from: 0, over: 10)
        let uneven = SentenceSplitter.times(
            for: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.", "bbbb."], from: 0, over: 10
        )
        XCTAssertGreaterThan(uneven[1], even[1])
    }

    /// A window with no duration must still produce times that sort.
    func testZeroDurationStillOrdersThem() {
        let times = SentenceSplitter.times(for: ["one.", "two.", "three."], from: 5, over: 0)
        XCTAssertTrue(times[0] < times[1] && times[1] < times[2])
    }

    func testNoSentencesNoTimes() {
        XCTAssertTrue(SentenceSplitter.times(for: [], from: 0, over: 10).isEmpty)
    }
}
