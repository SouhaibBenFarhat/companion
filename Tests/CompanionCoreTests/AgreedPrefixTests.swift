import XCTest
@testable import CompanionCore

final class AgreedPrefixTests: XCTestCase {
    /// The reported symptom: a line appears, then changes, then vanishes.
    /// Only the words two passes agree on should ever be shown.
    func testKeepsOnlyWhatBothGuessesSay() {
        XCTAssertEqual(
            AgreedPrefix.of("we recently added a wave", "we recently added a waveform debugger"),
            // Not "waveform": the earlier pass said "wave", which is a
            // different word. It appears once the next pass says it too.
            "we recently added a"
        )
    }

    /// Half of "waveform" is not a word.
    func testNeverShowsHalfAWord() {
        XCTAssertEqual(AgreedPrefix.of("a wavef", "a waveform"), "a")
    }

    /// Whisper moves commas and capitals between passes while the words stay
    /// put. Punctuation must not reset the agreement.
    func testPunctuationAndCaseDoNotBreakAgreement() {
        let agreed = AgreedPrefix.of("So the problem is", "so, the problem is that")
        XCTAssertEqual(agreed, "so, the problem is")
    }

    func testCompleteDisagreementShowsNothing() {
        XCTAssertEqual(AgreedPrefix.of("thank you", "the student lacks awareness"), "")
    }

    func testAnEmptyGuessAgreesOnNothing() {
        XCTAssertEqual(AgreedPrefix.of("", "anything at all"), "")
        XCTAssertEqual(AgreedPrefix.of("anything at all", ""), "")
    }

    /// The line may only ever grow. Feeding successive guesses must never
    /// produce something shorter than what was already shown.
    func testAgreementOnlyEverGrowsThroughASession() {
        let guesses = [
            "the platform",
            "the platform contains",
            "the platform contains thousands",
            "the platform contains thousands of interview",
            "the platform contains thousands of interview questions",
        ]

        var shown = ""
        var previous = ""
        for guess in guesses {
            let agreed = AgreedPrefix.of(previous, guess)
            if agreed.count >= shown.count { shown = agreed }
            previous = guess
        }
        XCTAssertEqual(shown, "the platform contains thousands of interview")
    }
}

final class RepetitionLoopTests: XCTestCase {
    /// Straight from the panel. Whisper's worst failure is not mishearing a
    /// word, it is repeating one, and this reads as something the other person
    /// actually said.
    func testCatchesTheLoopThatReachedTheScreen() {
        let seen = "She knows she'll need certain variables to store the result and count, "
            + String(repeating: "and type, ", count: 40) + "and type"
        XCTAssertTrue(TranscriptionNoise.isRepetitionLoop(seen))
    }

    func testCatchesASingleWordRepeated() {
        XCTAssertTrue(TranscriptionNoise.isRepetitionLoop(String(repeating: "okay ", count: 40)))
    }

    /// People repeat themselves honestly, and a short line must be left alone.
    func testLeavesRealSpeechAlone() {
        let real = "The platform contains thousands of interview questions asked by top quant "
            + "firms, coding problems, roadmaps, almost everything. We recently added a "
            + "waveform debugger for the system."
        XCTAssertFalse(TranscriptionNoise.isRepetitionLoop(real))
    }

    func testLeavesShortRepetitionAlone() {
        XCTAssertFalse(TranscriptionNoise.isRepetitionLoop("no, no, no"))
        XCTAssertFalse(TranscriptionNoise.isRepetitionLoop("yeah yeah yeah exactly"))
    }

    /// A long sentence with ordinary repeated words — "the", "and", "that" —
    /// must survive.
    func testLeavesALongOrdinarySentenceAlone() {
        let real = "So the thing about a lot of these models is that when you use them you "
            + "don't know what you don't know, and that is the part that makes it hard to "
            + "tell whether the answer is right or whether it just sounds right to you."
        XCTAssertFalse(TranscriptionNoise.isRepetitionLoop(real))
    }
}
