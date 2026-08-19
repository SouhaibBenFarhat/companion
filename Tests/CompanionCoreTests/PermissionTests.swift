import XCTest
@testable import CompanionCore

final class PermissionTests: XCTestCase {
    private func report(
        microphone: PermissionState = .granted,
        systemAudio: PermissionState = .granted,
        accessibility: PermissionState = .granted
    ) -> PermissionReport {
        PermissionReport(statuses: [
            PermissionStatus(permission: .microphone, state: microphone),
            PermissionStatus(permission: .systemAudio, state: systemAudio),
            PermissionStatus(permission: .accessibility, state: accessibility),
        ])
    }

    // MARK: - What each state allows

    func testEverythingGrantedIsReady() {
        XCTAssertTrue(report().isReady)
        XCTAssertTrue(report().canListen)
        XCTAssertTrue(report().canSeeScreen)
        XCTAssertTrue(report().missing.isEmpty)
    }

    /// Deliberately all or nothing. One side of a call transcribed alone reads
    /// as a person talking to themselves, which is worse than no transcript.
    func testListeningNeedsBothHalvesOfTheConversation() {
        XCTAssertFalse(report(microphone: .denied).canListen)
        XCTAssertFalse(report(systemAudio: .denied).canListen)
        XCTAssertFalse(report(microphone: .notAsked).canListen)
    }

    /// Screen awareness is useful on its own, so it must not be gated on audio.
    func testScreenAwarenessStandsAlone() {
        let noAudio = report(microphone: .denied, systemAudio: .denied)
        XCTAssertTrue(noAudio.canSeeScreen)
        XCTAssertFalse(noAudio.canListen)
    }

    func testAccessibilityDeniedBlocksOnlyTheScreen() {
        let blind = report(accessibility: .denied)
        XCTAssertTrue(blind.canListen)
        XCTAssertFalse(blind.canSeeScreen)
        XCTAssertFalse(blind.isReady)
    }

    // MARK: - Asking for one at a time

    func testAsksForTheMostUsefulFirst() {
        XCTAssertEqual(report(microphone: .notAsked).nextToRequest, .microphone)
        XCTAssertEqual(report(systemAudio: .notAsked).nextToRequest, .systemAudio)
        XCTAssertEqual(report(accessibility: .denied).nextToRequest, .accessibility)
    }

    func testMicrophoneComesBeforeTheOthers() {
        let none = report(microphone: .notAsked, systemAudio: .notAsked, accessibility: .denied)
        XCTAssertEqual(none.nextToRequest, .microphone)
    }

    func testNothingLeftToAskWhenReady() {
        XCTAssertNil(report().nextToRequest)
    }

    // MARK: - What the user is told

    func testSummaryNamesTheOneMissingPermission() {
        XCTAssertEqual(
            report(microphone: .denied).summary,
            "Microphone is needed before Companion can listen."
        )
    }

    func testSummaryJoinsTwoWithAnd() {
        let text = report(microphone: .denied, systemAudio: .denied).summary
        XCTAssertEqual(text, "Microphone and Screen Recording are needed before Companion can listen.")
    }

    func testSummaryJoinsThreeWithCommasAndAnd() {
        let text = report(microphone: .denied, systemAudio: .denied, accessibility: .denied).summary
        XCTAssertEqual(
            text,
            "Microphone, Screen Recording and Accessibility are needed before Companion can listen."
        )
    }

    func testSummarySaysReadyWhenNothingIsMissing() {
        XCTAssertEqual(report().summary, "Ready to listen.")
    }

    // MARK: - Facts the interface depends on

    /// The one that generates support questions: granting these two while the
    /// app is running leaves it still believing it is denied.
    func testScreenAndAccessibilityNeedARestart() {
        XCTAssertTrue(Permission.systemAudio.needsRestartAfterGranting)
        XCTAssertTrue(Permission.accessibility.needsRestartAfterGranting)
        XCTAssertFalse(Permission.microphone.needsRestartAfterGranting)
    }

    /// System audio is granted through Screen Recording, which surprises people
    /// enough that the reason has to say so.
    func testSystemAudioExplainsTheScreenRecordingSurprise() {
        XCTAssertTrue(Permission.systemAudio.reason.contains("Screen Recording"))
        XCTAssertEqual(Permission.systemAudio.title, "Screen Recording")
    }

    func testEverySettingsLinkTargetsAPrivacyPane() {
        for permission in Permission.allCases {
            let url = permission.settingsURL.absoluteString
            XCTAssertTrue(url.hasPrefix("x-apple.systempreferences:"), "\(permission): \(url)")
            XCTAssertTrue(url.contains("Privacy_"), "\(permission): \(url)")
        }
    }

    func testEveryPermissionSaysWhatItUnlocks() {
        for permission in Permission.allCases {
            XCTAssertGreaterThan(permission.reason.count, 20, "\(permission) has no useful reason")
        }
    }

    func testUnknownPermissionDefaultsToNotAsked() {
        let partial = PermissionReport(statuses: [
            PermissionStatus(permission: .microphone, state: .granted)
        ])
        XCTAssertEqual(partial.state(of: .accessibility), .notAsked)
        XCTAssertFalse(partial.canSeeScreen)
    }
}
