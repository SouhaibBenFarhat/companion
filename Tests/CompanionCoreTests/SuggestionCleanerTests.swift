import XCTest
@testable import CompanionCore

final class SuggestionCleanerTests: XCTestCase {
    /// Straight from the panel, twice, on two different calls. The model was
    /// handed a labelled transcript and wrote the next turn of it.
    func testRejectsTheLineThatKeptReachingTheScreen() {
        XCTAssertNil(SuggestionCleaner.clean("Human: whats the most recent claude model?"))
        XCTAssertNil(SuggestionCleaner.clean("Human: what's the name of the platform he is describing?"))
    }

    func testRejectsEveryLabelledQuestion() {
        for label in ["Human", "Assistant", "User", "AI", "You", "The call", "Claude"] {
            XCTAssertNil(SuggestionCleaner.clean("\(label): so what do you think?"), label)
        }
    }

    /// A label on top of a real answer is the right words in the wrong costume.
    /// Take the costume off rather than throw the answer away.
    func testStripsALabelFromAStatement() {
        XCTAssertEqual(
            SuggestionCleaner.clean("Assistant: The most recent model is Opus 5."),
            "The most recent model is Opus 5."
        )
    }

    func testStripsMoreThanOneLabel() {
        XCTAssertEqual(SuggestionCleaner.clean("Human: Assistant: It ships on Tuesday."), "It ships on Tuesday.")
    }

    /// Several labelled turns is a script, and no stripping makes it a note.
    func testRejectsAWholeScript() {
        let script = """
            Human: what should we do about the regex?
            Assistant: use a parser instead.
            """
        XCTAssertNil(SuggestionCleaner.clean(script))
    }

    // MARK: - What must survive

    func testKeepsAnOrdinaryNote() {
        let note = "Their retry limit is 3, not 5 — the docs they are quoting are out of date."
        XCTAssertEqual(SuggestionCleaner.clean(note), note)
    }

    /// A note that was never labelled may legitimately end in a question mark.
    func testKeepsAnUnlabelledQuestion() {
        let note = "Worth asking whether their sandbox has network access?"
        XCTAssertEqual(SuggestionCleaner.clean(note), note)
    }

    func testKeepsAColonThatIsNotALabel() {
        let note = "One cause: the tap is stereo and you are reading it as mono."
        XCTAssertEqual(SuggestionCleaner.clean(note), note)
    }

    /// Staying quiet is the normal case.
    func testSilenceIsNothing() {
        XCTAssertNil(SuggestionCleaner.clean(""))
        XCTAssertNil(SuggestionCleaner.clean("   \n  "))
        XCTAssertNil(SuggestionCleaner.clean("Assistant:"))
    }
}

final class AwarenessPromptOrderTests: XCTestCase {
    /// The transcript is a labelled script, and a script asks to be continued.
    /// An instruction underneath it competes with everything above.
    func testTheInstructionComesBeforeTheTranscript() {
        let prompt = AwarenessPrompt.build(
            question: "anything to say?",
            conversation: "The call: we should use a parser",
            instruction: "You are writing a private note to one person."
        )

        let instructionAt = prompt.range(of: "private note")!.lowerBound
        let transcriptAt = prompt.range(of: "<call>")!.lowerBound
        XCTAssertLessThan(instructionAt, transcriptAt)
    }

    func testAnEmptyInstructionAddsNothing() {
        let prompt = AwarenessPrompt.build(question: "hello", conversation: "", instruction: "  ")
        XCTAssertEqual(prompt, "hello")
    }
}
