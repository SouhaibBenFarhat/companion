import XCTest
@testable import CompanionCore

final class AgentContextTests: XCTestCase {
    private let repo = URL(fileURLWithPath: "/Users/someone/code/project")
    private let home = URL(fileURLWithPath: "/Users/someone")

    /// Asked what it was, the agent said "Claude Code running in your
    /// terminal". It had never been told otherwise: everything Companion sent
    /// it was about how to write, nothing about where it was.
    func testSaysWhatItIsRunningIn() {
        let prompt = AgentContext.systemPrompt(repository: repo, hasRepository: true)
        XCTAssertTrue(prompt.contains("Companion"))
        XCTAssertTrue(prompt.contains("not in a terminal"))
        XCTAssertTrue(prompt.contains("hidden from screen sharing"))
    }

    func testNamesTheChosenFolder() {
        let prompt = AgentContext.systemPrompt(repository: repo, hasRepository: true)
        XCTAssertTrue(prompt.contains("/Users/someone/code/project"))
        XCTAssertFalse(prompt.contains("No project folder has been chosen"))
    }

    /// The home-folder fallback is not a project, and an agent that treats it
    /// as one answers questions about "this repo" using the whole machine.
    func testSaysSoWhenNoFolderWasChosen() {
        let prompt = AgentContext.systemPrompt(repository: home, hasRepository: false)
        XCTAssertTrue(prompt.contains("No project folder has been chosen"))
        XCTAssertTrue(prompt.contains("pick a folder"))
    }

    func testTheStyleRuleIsAlwaysThere() {
        for hasRepository in [true, false] {
            let prompt = AgentContext.systemPrompt(repository: repo, hasRepository: hasRepository)
            XCTAssertTrue(prompt.contains("Lead with the answer"))
        }
    }

    func testCarriesTheUsersOwnInstructions() {
        let prompt = AgentContext.systemPrompt(
            repository: repo,
            hasRepository: true,
            extra: "Always answer in French."
        )
        XCTAssertTrue(prompt.contains("Always answer in French."))
    }

    /// Settings ships the style rule as the default value of the user's own
    /// field, so without this it appears twice in every prompt.
    func testDoesNotRepeatTheStyleRule() {
        let prompt = AgentContext.systemPrompt(
            repository: repo,
            hasRepository: true,
            extra: AgentContext.style
        )
        let occurrences = prompt.components(separatedBy: "Lead with the answer").count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func testWatchingIsOnlyIncludedWhenListening() {
        let quiet = AgentContext.systemPrompt(repository: repo, hasRepository: true)
        XCTAssertFalse(quiet.contains("listening to a live call"))

        let live = AgentContext.systemPrompt(
            repository: repo,
            hasRepository: true,
            watching: AwarenessPrompt.watchingInstruction
        )
        XCTAssertTrue(live.contains("listening to a live call"))
    }

    func testEmptyExtraAddsNothing() {
        let prompt = AgentContext.systemPrompt(repository: repo, hasRepository: true, extra: "   \n ")
        XCTAssertFalse(prompt.hasSuffix("\n"))
    }

    // MARK: - Knowing what the app can do

    /// Asked "can you listen to calls and help me answer in real time" — the
    /// thing this app exists for — the agent said no, it could only see what
    /// was typed. It was describing the CLI, because nobody had told it what it
    /// was plugged into.
    func testKnowsCompanionCanListenAndWatch() {
        let prompt = AgentContext.systemPrompt(repository: repo, hasRepository: true)
        XCTAssertTrue(prompt.contains("Listen to a call"))
        XCTAssertTrue(prompt.contains("Watch the screen"))
    }

    func testSaysListeningIsOffAndHowToTurnItOn() {
        let prompt = AgentContext.systemPrompt(repository: repo, hasRepository: true, isListening: false)
        XCTAssertTrue(prompt.contains("Listening is OFF"))
        XCTAssertTrue(prompt.contains("microphone button"))
        XCTAssertTrue(prompt.contains("do not tell them you"))
    }

    func testSaysListeningIsOnWhenItIs() {
        let prompt = AgentContext.systemPrompt(repository: repo, hasRepository: true, isListening: true)
        XCTAssertTrue(prompt.contains("Listening is ON"))
        XCTAssertFalse(prompt.contains("Listening is OFF"))
    }

    /// Local capture is a selling point and a promise; it has to be stated.
    func testSaysNothingIsUploaded() {
        let prompt = AgentContext.systemPrompt(repository: repo, hasRepository: true)
        XCTAssertTrue(prompt.contains("Nothing is uploaded"))
    }
}
