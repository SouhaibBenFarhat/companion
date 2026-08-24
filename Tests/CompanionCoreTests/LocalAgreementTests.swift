import XCTest
@testable import CompanionCore

final class LocalAgreementTests: XCTestCase {
    private var agreement = LocalAgreement()

    override func setUp() {
        super.setUp()
        agreement = LocalAgreement()
    }

    /// Nothing is settled on the first pass: there is nothing to agree with.
    func testTheFirstPassSettlesNothing() {
        let step = agreement.offer("the platform contains")
        XCTAssertEqual(step.settled, "")
        XCTAssertEqual(step.pending, "the platform contains")
    }

    /// The point of the whole thing: words settle while the speaker is still
    /// talking, instead of when they stop.
    func testWordsSettleAsSoonAsTwoPassesAgree() {
        _ = agreement.offer("the platform contains")
        let step = agreement.offer("the platform contains thousands of")

        XCTAssertEqual(step.settled, "the platform contains")
        XCTAssertEqual(step.pending, "thousands of")
    }

    /// A word already on screen is never sent twice.
    func testSettledWordsAreNeverRepeated() {
        _ = agreement.offer("one two")
        _ = agreement.offer("one two three four")
        let step = agreement.offer("one two three four five six")

        XCTAssertEqual(step.settled, "three four")
        XCTAssertEqual(step.pending, "five six")
    }

    /// Whisper revises. A word it changes its mind about must not have been
    /// settled — and once settled, must never be unsaid.
    func testARevisedTailDoesNotUnsayWhatWasSettled() {
        _ = agreement.offer("we added a wave")
        let first = agreement.offer("we added a waveform debugger")
        XCTAssertEqual(first.settled, "we added a")

        let second = agreement.offer("we added a waveform debugger for the system")
        XCTAssertEqual(second.settled, "waveform debugger")
    }

    /// Punctuation and capitals move between passes while the words stay put.
    func testPunctuationDoesNotBlockAgreement() {
        _ = agreement.offer("so the problem is")
        let step = agreement.offer("So, the problem is that")
        XCTAssertEqual(step.settled, "So, the problem is")
    }

    /// The speaker stopped, so there is no further pass to agree with.
    func testFinishSettlesTheRemainder() {
        _ = agreement.offer("one two")
        _ = agreement.offer("one two three")
        // Only "one two" was ever agreed twice, so "three" is still pending
        // and settles here along with "four".
        XCTAssertEqual(agreement.finish("one two three four"), "three four")
    }

    func testFinishResetsForTheNextSentence() {
        _ = agreement.offer("one two")
        _ = agreement.offer("one two")
        _ = agreement.finish("one two")

        let step = agreement.offer("completely different words")
        XCTAssertEqual(step.settled, "")
    }

    /// A pass can come back shorter than the one before it.
    func testAShorterPassDoesNotCrashOrUnsay() {
        _ = agreement.offer("one two three four five")
        _ = agreement.offer("one two three four five")
        let step = agreement.offer("one two")

        XCTAssertEqual(step.settled, "")
        XCTAssertEqual(step.pending, "")
    }

    /// Read back, the settled words must reproduce the sentence in order.
    func testTheSettledStreamReadsAsTheSentence() {
        let passes = [
            "the platform",
            "the platform contains",
            "the platform contains thousands",
            "the platform contains thousands of interview",
            "the platform contains thousands of interview questions",
        ]

        var settled: [String] = []
        for pass in passes {
            let step = agreement.offer(pass)
            if !step.settled.isEmpty { settled.append(step.settled) }
        }
        settled.append(agreement.finish(passes.last!))

        XCTAssertEqual(
            settled.joined(separator: " ").trimmingCharacters(in: .whitespaces),
            "the platform contains thousands of interview questions"
        )
    }
}
