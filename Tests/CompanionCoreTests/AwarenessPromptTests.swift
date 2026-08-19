import XCTest
@testable import CompanionCore

final class AwarenessPromptTests: XCTestCase {
    func testAPlainQuestionIsSentUnchanged() {
        XCTAssertEqual(AwarenessPrompt.build(question: "why is this slow?"), "why is this slow?")
    }

    func testConversationIsWrappedAndLabelled() {
        let prompt = AwarenessPrompt.build(
            question: "what did they mean?",
            conversation: "The call: the retry fires twice"
        )
        XCTAssertTrue(prompt.contains("<call>"))
        XCTAssertTrue(prompt.contains("</call>"))
        XCTAssertTrue(prompt.contains("the retry fires twice"))
        XCTAssertTrue(prompt.hasSuffix("what did they mean?"))
    }

    /// A live transcript gets words wrong, and an answer built on a misheard
    /// sentence is worse than no answer.
    func testTheModelIsToldTheTranscriptMayBeWrong() {
        let prompt = AwarenessPrompt.build(question: "x", conversation: "The call: hello")
        XCTAssertTrue(prompt.lowercased().contains("may contain mistakes"))
    }

    func testScreenContextIsWrappedSeparately() {
        let prompt = AwarenessPrompt.build(question: "fix it", screen: "AgentRunner.swift, line 58")
        XCTAssertTrue(prompt.contains("<screen>"))
        XCTAssertTrue(prompt.contains("AgentRunner.swift"))
    }

    func testBothContextsAppearBeforeTheQuestion() {
        let prompt = AwarenessPrompt.build(
            question: "the question",
            conversation: "The call: spoken",
            screen: "on screen"
        )
        let call = prompt.range(of: "<call>")!.lowerBound
        let screen = prompt.range(of: "<screen>")!.lowerBound
        let question = prompt.range(of: "the question")!.lowerBound

        XCTAssertLessThan(call, screen)
        XCTAssertLessThan(screen, question)
    }

    func testEmptyContextAddsNothing() {
        let prompt = AwarenessPrompt.build(question: "hi", conversation: "   ", screen: "\n")
        XCTAssertEqual(prompt, "hi")
    }

    // MARK: - Staying quiet

    /// The hard part is not answering, it is not answering. An assistant that
    /// remarks on everything gets switched off after one call.
    func testTheWatchingInstructionMakesSilenceTheDefault() {
        let text = AwarenessPrompt.watchingInstruction.lowercased()
        XCTAssertTrue(text.contains("say nothing unless"))
        XCTAssertTrue(text.contains("stay silent"))
        XCTAssertTrue(text.contains("not a failure"))
    }

    func testTheWatchingInstructionBansTheObviousFillers() {
        let text = AwarenessPrompt.watchingInstruction.lowercased()
        XCTAssertTrue(text.contains("never summarise"))
        XCTAssertTrue(text.contains("never greet"))
    }
}
