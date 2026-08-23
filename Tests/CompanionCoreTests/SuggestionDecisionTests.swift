import XCTest
@testable import CompanionCore

final class SuggestionDecisionTests: XCTestCase {
    /// Silence is now an answer the model can give, rather than an absence it
    /// has to manage. "Reply with nothing at all" competes with everything a
    /// model is built to do, and it loses.
    func testSilenceIsADecision() {
        let decision = SuggestionDecision.parse(#"{"speak": false}"#)
        XCTAssertEqual(decision?.speak, false)
        XCTAssertNil(decision?.note)
    }

    func testANoteCarriesItsKind() {
        let decision = SuggestionDecision.parse(
            #"{"speak": true, "kind": "correction", "text": "Their retry limit is 3, not 5."}"#
        )
        XCTAssertEqual(decision?.kind, .correction)
        XCTAssertEqual(decision?.note, "Their retry limit is 3, not 5.")
    }

    /// Models wrap JSON in a fence, and write a sentence either side of it.
    /// Neither is a reason to lose a good note.
    func testReadsThroughACodeFence() {
        let raw = """
            Here is my decision:

            ```json
            {"speak": true, "kind": "fact", "text": "The flag is --tools on this version."}
            ```

            Let me know if you need more.
            """
        XCTAssertEqual(SuggestionDecision.parse(raw)?.note, "The flag is --tools on this version.")
    }

    // MARK: - Everything that is not a decision is silence

    /// The shapes that actually reached the panel, before this existed.
    func testProseIsNotADecision() {
        XCTAssertNil(SuggestionDecision.parse("Tell me about Claude's personality"))
        XCTAssertNil(SuggestionDecision.parse(
            "The speaker is correct — closures capture live references, not copies."
        ))
        XCTAssertNil(SuggestionDecision.parse("Human: what's the name of the platform?"))
        XCTAssertNil(SuggestionDecision.parse(""))
    }

    func testAMalformedObjectIsSilence() {
        XCTAssertNil(SuggestionDecision.parse(#"{"speak": true"#))
        XCTAssertNil(SuggestionDecision.parse(#"{"speak": "yes"}"#))
    }

    /// Saying it wants to speak and then not saying anything is silence.
    func testSpeakingWithNothingToSayIsSilence() {
        XCTAssertNil(SuggestionDecision.parse(#"{"speak": true, "kind": "fact"}"#)?.note)
        XCTAssertNil(SuggestionDecision.parse(#"{"speak": true, "kind": "fact", "text": "  "}"#)?.note)
        XCTAssertNil(SuggestionDecision.parse(#"{"speak": true, "text": "no kind given"}"#)?.note)
    }

    /// An unknown kind is not a kind. The set is closed so that every value is
    /// something the user can act on, leaving no box for a remark.
    func testAnInventedKindIsSilence() {
        XCTAssertNil(SuggestionDecision.parse(#"{"speak": true, "kind": "observation", "text": "hm"}"#))
    }

    func testEveryKindHasAName() {
        for kind in SuggestionDecision.Kind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
        }
    }
}
