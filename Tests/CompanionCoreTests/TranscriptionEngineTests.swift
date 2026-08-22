import XCTest
@testable import CompanionCore

final class TranscriptionEngineKindTests: XCTestCase {
    func testWhisperRunsOnAnyMacTheAppSupports() {
        XCTAssertNil(TranscriptionEngineKind.whisper.unmetRequirement)
    }

    /// The old check asked about the operating system. The question is now
    /// about the engine, and "needs macOS 26" is simply false once Whisper is
    /// an option.
    func testAppleStatesItsOwnRequirement() {
        if #available(macOS 26.0, *) {
            XCTAssertNil(TranscriptionEngineKind.apple.unmetRequirement)
        } else {
            XCTAssertNotNil(TranscriptionEngineKind.apple.unmetRequirement)
        }
    }

    func testEveryEngineHasAName() {
        for kind in TranscriptionEngineKind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
        }
    }

    func testRoundTripsThroughJSON() throws {
        var settings = Settings()
        settings.transcriptionEngine = .apple
        let restored = try JSONDecoder().decode(
            Settings.self, from: JSONEncoder().encode(settings)
        )
        XCTAssertEqual(restored.transcriptionEngine, .apple)
    }

    /// An older settings file has no engine key, and must land on the one the
    /// app now recommends rather than failing to decode.
    func testAnOlderFileGetsTheDefault() throws {
        let settings = try JSONDecoder().decode(
            Settings.self, from: Data(#"{"agent":"claude"}"#.utf8)
        )
        XCTAssertEqual(settings.transcriptionEngine, Settings().transcriptionEngine)
    }
}

final class TranscriptionWindowerTests: XCTestCase {
    /// Whisper is not a streaming recogniser: something has to decide where a
    /// block of audio ends. Cutting on a timer splits words in half, which
    /// destroys exactly the long identifiers this engine was chosen for.
    func testAWindowNeverGrowsPastItsCap() {
        let windower = TranscriptionWindower(speaker: .me)
        XCTAssertLessThanOrEqual(windower.maximumSeconds, 30)
        XCTAssertGreaterThan(windower.maximumSeconds, windower.minimumSeconds)
    }

    func testDurationIsFramesOverTheSampleRate() {
        let window = TranscriptionWindow(
            speaker: .them,
            samples: [Float](repeating: 0, count: 32_000),
            startSeconds: 4,
            isClosed: true
        )
        XCTAssertEqual(window.duration, 2, accuracy: 0.0001)
    }
}
