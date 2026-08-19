import XCTest
@testable import CompanionCore

final class AwarenessSettingsTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Listening is off until asked for. An assistant that starts recording on
    /// launch is one nobody installs twice.
    func testListeningIsOffByDefault() {
        XCTAssertFalse(AwarenessSettings().enabled)
    }

    /// A transcript of a work call is someone else's words.
    func testTheTranscriptIsNotKeptByDefault() {
        XCTAssertFalse(AwarenessSettings().persistTranscript)
    }

    /// Listening is useful on its own. Interrupting has to be asked for.
    func testSpeakingUnpromptedIsOffByDefault() {
        XCTAssertFalse(AwarenessSettings().suggestionsEnabled)
    }

    func testListeningAndSuggestingAreSeparateSwitches() {
        var settings = AwarenessSettings()
        settings.enabled = true
        XCTAssertTrue(settings.enabled)
        XCTAssertFalse(settings.suggestionsEnabled)
    }

    func testBothSidesAreCapturedByDefault() {
        XCTAssertTrue(AwarenessSettings().capturesBothSides)
        XCTAssertTrue(AwarenessSettings().echoCancellationEnabled)
    }

    func testOneSideAloneIsNotBothSides() {
        var settings = AwarenessSettings()
        settings.captureSystemAudio = false
        XCTAssertFalse(settings.capturesBothSides)
    }

    func testRoundTrips() throws {
        var settings = AwarenessSettings()
        settings.enabled = true
        settings.transcriptWindowSeconds = 900
        settings.persistTranscript = true

        let restored = try decoder.decode(AwarenessSettings.self, from: encoder.encode(settings))
        XCTAssertEqual(restored, settings)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let settings = try decoder.decode(AwarenessSettings.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.transcriptWindowSeconds, AwarenessSettings().transcriptWindowSeconds)
        XCTAssertFalse(settings.persistTranscript)
        XCTAssertFalse(settings.suggestionsEnabled)
    }

    /// A settings file written before any of this existed must still load.
    func testAnOlderSettingsFileGetsDefaultAwareness() throws {
        let old = Data(#"{"agent":"claude","panelWidth":500}"#.utf8)
        let settings = try decoder.decode(Settings.self, from: old)
        XCTAssertEqual(settings.awareness, AwarenessSettings())
        XCTAssertFalse(settings.awareness.enabled)
        XCTAssertEqual(settings.panelWidth, 500)
    }

    func testSettingsStillRoundTripWithAwareness() throws {
        var settings = Settings()
        settings.awareness.enabled = true
        settings.awareness.transcriptWindowSeconds = 120

        let restored = try decoder.decode(Settings.self, from: encoder.encode(settings))
        XCTAssertEqual(restored, settings)
    }

    /// The shortcut was being torn down and rebuilt on every keystroke in the
    /// settings sheet.
    func testHotKeyChangeIsDetectedOnItsOwn() {
        let original = Settings()
        var sameShortcut = original
        sameShortcut.awareness.enabled = true
        XCTAssertFalse(sameShortcut.hotKeyChanged(from: original))

        var different = original
        different.hotKeyCode = 50
        XCTAssertTrue(different.hotKeyChanged(from: original))
    }
}
