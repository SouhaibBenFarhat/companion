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

final class SentenceBufferingTests: XCTestCase {
    /// Words settle a few at a time, which is what keeps the transcript up with
    /// the call. Shown as they arrived, one sentence became five bubbles:
    /// "I got a bit too deep", "reality.", "into the rabbit hole."
    func testAnUnfinishedSentenceWaits() {
        let (sentences, remainder) = SentenceSplitter.complete(in: "I got a bit too deep")
        XCTAssertTrue(sentences.isEmpty)
        XCTAssertEqual(remainder, "I got a bit too deep")
    }

    func testASentenceAppearsWhenItEnds() {
        let (sentences, remainder) = SentenceSplitter.complete(in: "I got a bit too deep into the rabbit hole.")
        XCTAssertEqual(sentences, ["I got a bit too deep into the rabbit hole."])
        XCTAssertEqual(remainder, "")
    }

    /// A buffer can hold a finished sentence and the start of the next one.
    func testFinishedSentencesLeaveAndTheRestStays() {
        let (sentences, remainder) = SentenceSplitter.complete(
            in: "I started reading books. And it introduced me to"
        )
        XCTAssertEqual(sentences, ["I started reading books."])
        XCTAssertEqual(remainder, "And it introduced me to")
    }

    func testNothingInNothingOut() {
        let (sentences, remainder) = SentenceSplitter.complete(in: "   ")
        XCTAssertTrue(sentences.isEmpty)
        XCTAssertEqual(remainder, "")
    }
}

final class ForeignScriptTests: XCTestCase {
    /// "全世界的" appeared in the middle of an English call — a hallucination on
    /// a window the model could not make sense of.
    func testDropsAHanLineFromAnEnglishCall() {
        XCTAssertTrue(TranscriptionNoise.isForeignScript("全世界的", expecting: "en"))
        XCTAssertTrue(TranscriptionNoise.isForeignScript("字幕をご覧いただき", expecting: "en"))
    }

    func testKeepsEnglish() {
        XCTAssertFalse(TranscriptionNoise.isForeignScript("That our universe is stacked", expecting: "en"))
    }

    /// A name or a borrowed word must survive.
    func testKeepsEnglishWithAnAccentedWord() {
        XCTAssertFalse(TranscriptionNoise.isForeignScript("we deployed it to São Paulo", expecting: "en"))
        XCTAssertFalse(TranscriptionNoise.isForeignScript("it is a naïve approach", expecting: "en"))
    }

    /// On another language, or on automatic detection, this must do nothing —
    /// it would throw away exactly the text it exists to support.
    func testDoesNothingWhenTheCallIsNotInEnglish() {
        XCTAssertFalse(TranscriptionNoise.isForeignScript("全世界的", expecting: "zh"))
        XCTAssertFalse(TranscriptionNoise.isForeignScript("全世界的", expecting: nil))
    }

    func testPunctuationAloneIsNotForeign() {
        XCTAssertFalse(TranscriptionNoise.isForeignScript("...", expecting: "en"))
    }
}
