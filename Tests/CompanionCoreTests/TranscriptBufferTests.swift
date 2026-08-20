import XCTest
@testable import CompanionCore

final class TranscriptBufferTests: XCTestCase {
    private var buffer = TranscriptBuffer()

    override func setUp() {
        super.setUp()
        buffer = TranscriptBuffer(windowSeconds: 300)
    }

    // MARK: - Order

    func testKeepsWhatWasSaidInOrder() {
        buffer.appendFinal("what does this do?", speaker: .them, at: 1)
        buffer.appendFinal("it retries the request", speaker: .me, at: 3)
        XCTAssertEqual(buffer.entries.map(\.speaker), [.them, .me])
    }

    /// The two streams settle independently, so lines arrive out of order.
    func testSortsLinesThatArriveLate() {
        buffer.appendFinal("second", speaker: .me, at: 5)
        buffer.appendFinal("first", speaker: .them, at: 2)
        XCTAssertEqual(buffer.entries.map(\.text), ["first", "second"])
    }

    // MARK: - The tail the recogniser is still revising

    /// The bug this design exists to prevent: appending revisions instead of
    /// replacing them puts every sentence in the transcript several times.
    func testARevisedTailReplacesRatherThanRepeats() {
        buffer.setVolatile("so the retry", speaker: .them, at: 4)
        buffer.setVolatile("so the retry loop", speaker: .them, at: 4)
        buffer.setVolatile("so the retry loop fires twice", speaker: .them, at: 4)

        XCTAssertEqual(buffer.entries.count, 1)
        XCTAssertEqual(buffer.entries[0].text, "so the retry loop fires twice")
    }

    func testEachSpeakerHasItsOwnTail() {
        buffer.setVolatile("I think", speaker: .me, at: 1)
        buffer.setVolatile("well actually", speaker: .them, at: 2)
        XCTAssertEqual(buffer.entries.count, 2)
    }

    func testSettlingClearsThatSpeakersTail() {
        buffer.setVolatile("so the retry", speaker: .them, at: 4)
        buffer.appendFinal("so the retry loop fires twice", speaker: .them, at: 4)

        XCTAssertEqual(buffer.entries.count, 1)
        XCTAssertFalse(buffer.entries[0].isVolatile)
    }

    func testAnEmptyTailRemovesIt() {
        buffer.setVolatile("hm", speaker: .me, at: 1)
        buffer.setVolatile("", speaker: .me, at: 1)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testATailSortsAfterSettledTextAtTheSameMoment() {
        buffer.appendFinal("settled", speaker: .them, at: 2)
        buffer.setVolatile("still going", speaker: .me, at: 2)
        XCTAssertEqual(buffer.entries.map(\.text), ["settled", "still going"])
    }

    // MARK: - What gets sent to the model

    /// Sending a half-heard sentence means reasoning about words nobody said.
    func testUnsentTextExcludesTheLiveTail() {
        buffer.appendFinal("settled line", speaker: .them, at: 1)
        buffer.setVolatile("half a sen", speaker: .me, at: 2)

        XCTAssertTrue(buffer.unsentText().contains("settled line"))
        XCTAssertFalse(buffer.unsentText().contains("half a sen"))
    }

    func testMarkingSentStopsItBeingSentAgain() {
        buffer.appendFinal("first", speaker: .them, at: 1)
        XCTAssertTrue(buffer.hasUnsent)

        buffer.markSent()
        XCTAssertFalse(buffer.hasUnsent)
        XCTAssertEqual(buffer.unsentText(), "")
    }

    func testNewLinesAfterSendingAreUnsentAgain() {
        buffer.appendFinal("first", speaker: .them, at: 1)
        buffer.markSent()
        buffer.appendFinal("second", speaker: .me, at: 2)

        XCTAssertTrue(buffer.hasUnsent)
        XCTAssertTrue(buffer.unsentText().contains("second"))
        XCTAssertFalse(buffer.unsentText().contains("first"))
    }

    // MARK: - The window

    func testDropsAnythingOlderThanTheWindow() {
        buffer = TranscriptBuffer(windowSeconds: 10)
        buffer.appendFinal("ancient", speaker: .them, at: 0)
        buffer.appendFinal("recent", speaker: .me, at: 30)

        XCTAssertEqual(buffer.entries.map(\.text), ["recent"])
    }

    func testKeepsEverythingInsideTheWindow() {
        buffer = TranscriptBuffer(windowSeconds: 60)
        buffer.appendFinal("one", speaker: .them, at: 0)
        buffer.appendFinal("two", speaker: .me, at: 30)
        XCTAssertEqual(buffer.entries.count, 2)
    }

    func testTextCanBeLimitedToTheRecentPast() {
        buffer.appendFinal("old", speaker: .them, at: 0)
        buffer.appendFinal("new", speaker: .me, at: 100)

        let recent = buffer.text(lastSeconds: 10)
        XCTAssertTrue(recent.contains("new"))
        XCTAssertFalse(recent.contains("old"))
    }

    // MARK: - Shape of the output

    func testTextIsLabelledBySpeaker() {
        buffer.appendFinal("why is it slow?", speaker: .them, at: 1)
        XCTAssertEqual(buffer.text(), "The call: why is it slow?")
    }

    /// Someone reads an API key aloud, or it appears in a shared terminal.
    func testSecretsAreMaskedOnTheWayIn() {
        buffer.appendFinal("the key is ghp_abcdefghijklmnopqrstuvwx ok", speaker: .them, at: 1)
        XCTAssertFalse(buffer.text().contains("ghp_abcdefghijklmnopqrstuvwx"))
    }

    func testBlankLinesAreIgnored() {
        buffer.appendFinal("   ", speaker: .me, at: 1)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testKnowsWhoSpokeLast() {
        buffer.appendFinal("a question", speaker: .them, at: 1)
        XCTAssertTrue(buffer.lastSpeakerWasThem)

        buffer.appendFinal("an answer", speaker: .me, at: 2)
        XCTAssertFalse(buffer.lastSpeakerWasThem)
    }

    func testClearingResetsEverythingIncludingTheWatermark() {
        buffer.appendFinal("something", speaker: .me, at: 1)
        buffer.markSent()
        buffer.clear()

        XCTAssertTrue(buffer.isEmpty)
        buffer.appendFinal("after", speaker: .me, at: 2)
        XCTAssertTrue(buffer.hasUnsent)
    }
}
