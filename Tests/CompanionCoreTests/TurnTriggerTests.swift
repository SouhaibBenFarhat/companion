import XCTest
@testable import CompanionCore

final class TurnTriggerTests: XCTestCase {
    private let trigger = TurnTrigger()

    // MARK: - Recognising a question

    func testAQuestionMarkIsAQuestion() {
        XCTAssertTrue(trigger.isQuestion("why does the retry fire twice?"))
    }

    /// Speech recognisers rarely add punctuation, so the opening matters more
    /// than the question mark.
    func testAQuestionOpeningCountsWithoutPunctuation() {
        XCTAssertTrue(trigger.isQuestion("how do we handle the timeout"))
        XCTAssertTrue(trigger.isQuestion("can you explain the retry loop"))
        XCTAssertTrue(trigger.isQuestion("any idea why it hangs"))
    }

    func testAStatementIsNotAQuestion() {
        XCTAssertFalse(trigger.isQuestion("the retry loop fires twice"))
        XCTAssertFalse(trigger.isQuestion("I will fix that now"))
        XCTAssertFalse(trigger.isQuestion(""))
    }

    // MARK: - When to think

    func testTheOtherPersonAskingIsAReason() {
        XCTAssertEqual(
            trigger.evaluate(text: "how do we test this?", speaker: .them, userIsSpeaking: false),
            .questionAsked
        )
    }

    func testTheOtherPersonFinishingHandsOverTheTurn() {
        XCTAssertEqual(
            trigger.evaluate(text: "so that is the plan", speaker: .them, userIsSpeaking: false),
            .turnHandedOver
        )
    }

    /// The user's own words are not a prompt. Treating them as one means
    /// answering yourself.
    func testTheUsersOwnSpeechIsNeverATrigger() {
        XCTAssertNil(trigger.evaluate(text: "how do we test this?", speaker: .me, userIsSpeaking: false))
    }

    /// Interrupting somebody mid-sentence with something they cannot read is
    /// the fastest way to get the feature switched off.
    func testNothingFiresWhileTheUserIsTalking() {
        XCTAssertNil(trigger.evaluate(text: "why is it slow?", speaker: .them, userIsSpeaking: true))
    }
}

final class SuggestionGateTests: XCTestCase {
    private let gate = SuggestionGate(maximumPerMinute: 3, minimumGap: 12)

    func testTheFirstSuggestionIsShown() {
        var state = SuggestionGate.State()
        XCTAssertEqual(gate.admit("check the retry loop", at: 0, state: &state), .show)
    }

    func testSilenceIsNotASuggestion() {
        var state = SuggestionGate.State()
        XCTAssertEqual(gate.admit("   ", at: 0, state: &state), .nothingToSay)
    }

    func testTwoInQuickSuccessionIsTooSoon() {
        var state = SuggestionGate.State()
        _ = gate.admit("first thing", at: 0, state: &state)
        XCTAssertEqual(gate.admit("second thing", at: 3, state: &state), .tooSoon)
    }

    func testMoreThanTheBudgetInAMinuteIsRefused() {
        var state = SuggestionGate.State()
        XCTAssertEqual(gate.admit("alpha one", at: 0, state: &state), .show)
        XCTAssertEqual(gate.admit("beta two", at: 20, state: &state), .show)
        XCTAssertEqual(gate.admit("gamma three", at: 40, state: &state), .show)
        XCTAssertEqual(gate.admit("delta four", at: 55, state: &state), .tooMany)
    }

    func testTheBudgetRefillsAsTheMinutePasses() {
        var state = SuggestionGate.State()
        for (index, text) in ["alpha one", "beta two", "gamma three"].enumerated() {
            _ = gate.admit(text, at: Double(index) * 20, state: &state)
        }
        XCTAssertEqual(gate.admit("delta four", at: 200, state: &state), .show)
    }

    /// Saying the same thing again in different words is worse than silence.
    func testRepeatingItselfIsRefused() {
        var state = SuggestionGate.State()
        _ = gate.admit("the retry loop fires twice because the handler is attached twice", at: 0, state: &state)
        XCTAssertEqual(
            gate.admit("the handler is attached twice so the retry fires twice", at: 30, state: &state),
            .repeating
        )
    }

    func testSomethingGenuinelyNewIsShown() {
        var state = SuggestionGate.State()
        _ = gate.admit("the retry loop fires twice", at: 0, state: &state)
        XCTAssertEqual(gate.admit("the certificate expires on Friday", at: 30, state: &state), .show)
    }
}
