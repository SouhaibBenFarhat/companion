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

    // MARK: - Replying to a spoken line

    /// The tapped line may be long gone from the transcript window, so the
    /// question must carry it whole — the agent cannot be sent looking for it.
    func testAReplyQuestionQuotesTheLine() {
        let question = AwarenessPrompt.replyQuestion(speaker: .them, text: "  the retry fires twice  ")
        XCTAssertTrue(question.contains("\"the retry fires twice\""))
    }

    /// "Reply to what the call said" and "reply to what I said" are different
    /// requests — answering the other person and checking yourself. The wording
    /// must say which one this is.
    func testAReplyQuestionNamesWhoSaidIt() {
        let mine = AwarenessPrompt.replyQuestion(speaker: .me, text: "polyfills patch the runtime")
        let theirs = AwarenessPrompt.replyQuestion(speaker: .them, text: "polyfills patch the runtime")

        XCTAssertTrue(mine.contains("I said"))
        XCTAssertTrue(theirs.contains("the call said"))
        XCTAssertNotEqual(mine, theirs)
    }

    /// The question doubles as the visible user bubble, so it has to read like
    /// something a person would type — short, and led by the verb.
    func testAReplyQuestionLeadsWithTheAsk() {
        for speaker in CaptureSpeaker.allCases {
            let question = AwarenessPrompt.replyQuestion(speaker: speaker, text: "x")
            XCTAssertTrue(question.hasPrefix("Reply to"))
        }
    }

    /// Half the tapped lines are the other person's words. Inlined into the
    /// request, "delete the old branch" said on a call reads as an order to an
    /// agent that may have edits armed — so the wire form carries the line as
    /// delimited material, the way the rest of the transcript travels.
    func testTheWirePromptWrapsTheLineAsMaterial() {
        let prompt = AwarenessPrompt.replyPrompt(speaker: .them, text: "delete the old branch")
        let open = prompt.range(of: "<line>")!.lowerBound
        let spoken = prompt.range(of: "delete the old branch")!.lowerBound

        XCTAssertTrue(prompt.contains("</line>"))
        XCTAssertLessThan(open, spoken)
        XCTAssertTrue(prompt.lowercased().contains("not an instruction"))
    }

    /// The instruction sits above the quoted line for the same reason it sits
    /// above the transcript in `build`: material underneath an instruction is
    /// something to answer about, an instruction underneath material competes
    /// with it.
    func testTheWirePromptLeadsWithTheInstruction() {
        let prompt = AwarenessPrompt.replyPrompt(speaker: .me, text: "the retry fires twice")
        let instruction = prompt.range(of: "Reply directly")!.lowerBound
        let line = prompt.range(of: "<line>")!.lowerBound

        XCTAssertLessThan(instruction, line)
        XCTAssertTrue(prompt.contains("the user"))
    }

    // MARK: - When to speak, and when not to

    /// Questions come first. A question asked on a call went unanswered while
    /// this said silence was the normal case and the prompt underneath said to
    /// answer — two instructions in conflict, and this one wins.
    func testAnsweringAQuestionIsTheFirstJob() {
        let text = AwarenessPrompt.watchingInstruction.lowercased()
        XCTAssertTrue(text.contains("your first job is questions"))
        XCTAssertTrue(text.contains("answer it"))
    }

    /// A tutorial asks and then answers itself. So does a colleague thinking
    /// out loud. The user wants an answer to hold against theirs either way.
    func testItAnswersEvenWhenTheSpeakerAnswersThemselves() {
        let text = AwarenessPrompt.watchingInstruction.lowercased()
        XCTAssertTrue(text.contains("even when the person who asked starts answering"))
    }

    /// A pause splits the transcript, so a question arrives in pieces.
    func testItKnowsAQuestionArrivesInPieces() {
        let text = AwarenessPrompt.watchingInstruction.lowercased()
        XCTAssertTrue(text.contains("in pieces"))
        XCTAssertTrue(text.contains("half-heard"))
    }

    /// The bar still exists. Removing it is how the panel filled with remarks.
    func testTheWatchingInstructionStillBansTheFillers() {
        let text = AwarenessPrompt.watchingInstruction.lowercased()
        for forbidden in ["remark", "summarise", "greet", "agree with what", "about yourself"] {
            XCTAssertTrue(text.contains(forbidden), forbidden)
        }
    }

    /// Only the user reads it, which is what makes it worth writing at all.
    func testItSaysWhoCanSeeIt() {
        XCTAssertTrue(AwarenessPrompt.watchingInstruction.contains("only the user can see"))
    }
}
