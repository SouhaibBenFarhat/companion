import XCTest
@testable import CompanionCore

final class SettingsTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func testDefaultsAreSafeForPairing() {
        let settings = Settings()
        XCTAssertEqual(settings.agent, .claude)
        // Read only by default: an assistant must not edit the code you are
        // demonstrating to someone.
        XCTAssertEqual(settings.permission, .readOnly)
        XCTAssertEqual(settings.systemPrompt, DefaultSystemPrompt.text)
    }

    func testRoundTripsThroughJSON() throws {
        var settings = Settings()
        settings.agent = .codex
        settings.agentPath = "/opt/homebrew/bin/codex"
        settings.defaultRepositoryPath = "~/code/project"
        settings.permission = .acceptEdits
        settings.panelOriginX = 120
        settings.panelOriginY = 340

        let restored = try decoder.decode(Settings.self, from: encoder.encode(settings))
        XCTAssertEqual(restored, settings)
    }

    /// An older settings file must still load. Resetting every preference
    /// because one key is missing would be worse than any missing feature.
    func testMissingKeysFallBackToDefaults() throws {
        let json = Data(#"{"agent":"codex"}"#.utf8)
        let settings = try decoder.decode(Settings.self, from: json)

        XCTAssertEqual(settings.agent, .codex)
        XCTAssertEqual(settings.permission, Settings().permission)
        XCTAssertEqual(settings.panelWidth, Settings().panelWidth)
        XCTAssertEqual(settings.hotKeyCode, Settings().hotKeyCode)
        XCTAssertEqual(settings.systemPrompt, DefaultSystemPrompt.text)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        let settings = try decoder.decode(Settings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings, Settings())
    }

    func testRepositoryURLExpandsTheTilde() {
        var settings = Settings()
        settings.defaultRepositoryPath = "~/code/project"
        let path = settings.repositoryURL().path
        XCTAssertFalse(path.contains("~"))
        XCTAssertTrue(path.hasSuffix("/code/project"))
    }

    /// A fresh install has no repo set; spawning must still work rather than
    /// failing with an unusable working directory.
    func testRepositoryURLFallsBackToHome() {
        XCTAssertEqual(Settings().repositoryURL(), FileManager.default.homeDirectoryForCurrentUser)
    }

    func testPanelDefaultsAreLargeEnoughToRead() {
        // The panel only covers the user's own view — viewers of a shared
        // screen lose nothing — so there is no reason for a cramped strip.
        XCTAssertGreaterThanOrEqual(Settings().panelWidth, 360)
        XCTAssertGreaterThanOrEqual(Settings().panelHeight, 400)
    }
}
