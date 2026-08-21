import XCTest
@testable import CompanionCore

final class AudioInputTests: XCTestCase {
    private let builtIn = AudioInputDevice(uid: "built-in", name: "MacBook Pro Microphone")
    private let scarlett = AudioInputDevice(uid: "scarlett", name: "Scarlett 2i2 USB")
    private let iPhone = AudioInputDevice(uid: "iphone", name: "iPhone Microphone", isSystemDefault: true)

    private var available: [AudioInputDevice] { [iPhone, scarlett, builtIn] }

    func testAChosenDeviceIsUsed() {
        XCTAssertEqual(
            AudioInputSelection.resolve(preferredUID: "scarlett", available: available),
            scarlett
        )
    }

    /// Choosing nothing means following macOS, which is the old behaviour.
    func testNoChoiceFallsBackToTheSystemDefault() {
        XCTAssertEqual(AudioInputSelection.resolve(preferredUID: "", available: available), iPhone)
    }

    /// A microphone gets unplugged mid-day. Recording the wrong one is bad;
    /// recording nothing is worse, and the choice is kept for its return.
    func testAnUnpluggedChoiceFallsBackRatherThanFailing() {
        let withoutScarlett = [iPhone, builtIn]
        XCTAssertEqual(
            AudioInputSelection.resolve(preferredUID: "scarlett", available: withoutScarlett),
            iPhone
        )
    }

    func testTheInterfaceCanTellTheUserTheirChoiceIsMissing() {
        XCTAssertTrue(
            AudioInputSelection.isPreferredMissing(preferredUID: "scarlett", available: [iPhone])
        )
        XCTAssertFalse(
            AudioInputSelection.isPreferredMissing(preferredUID: "scarlett", available: available)
        )
    }

    /// Following the system default is not a missing choice.
    func testNoChoiceIsNeverReportedAsMissing() {
        XCTAssertFalse(AudioInputSelection.isPreferredMissing(preferredUID: "", available: available))
    }

    func testNoDevicesAtAllResolvesToNothing() {
        XCTAssertNil(AudioInputSelection.resolve(preferredUID: "scarlett", available: []))
    }

    /// With no system default flagged, anything beats nothing.
    func testFallsBackToTheFirstDeviceWhenNoneIsDefault() {
        XCTAssertEqual(
            AudioInputSelection.resolve(preferredUID: "", available: [scarlett, builtIn]),
            scarlett
        )
    }
}
