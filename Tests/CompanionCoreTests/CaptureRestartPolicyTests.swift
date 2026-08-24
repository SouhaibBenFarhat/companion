import XCTest
@testable import CompanionCore

final class CaptureRestartPolicyTests: XCTestCase {
    private let policy = CaptureRestartPolicy()

    /// A graph that came up long ago, on the devices it still sees. The
    /// starting point for every test about what a *change* should do.
    private func settled(devices: String = "1/2") -> CaptureRestartPolicy.State {
        var state = CaptureRestartPolicy.State()
        state.started(at: -100, fingerprint: devices)
        return state
    }

    private func ask(
        _ state: inout CaptureRestartPolicy.State,
        at now: TimeInterval,
        devices: String = "9/9"
    ) -> CaptureRestartPolicy.Decision {
        policy.requestRebuild(at: now, fingerprint: devices, state: &state)
    }

    // MARK: - Real changes

    /// Unplugging headphones fires several notifications within milliseconds.
    /// Rebuilding on each tears down a tap that is still being built.
    func testABurstYieldsOneRebuild() {
        var state = settled()
        var rebuilds = 0

        for offset in stride(from: 0.0, through: 0.02, by: 0.005) {
            if ask(&state, at: offset) == .rebuild { rebuilds += 1 }
        }
        XCTAssertEqual(rebuilds, 1)
    }

    func testWaitReportsHowLongIsLeft() {
        var state = settled()
        XCTAssertEqual(ask(&state, at: 0), .rebuild)

        guard case .wait(let remaining) = ask(&state, at: 0.1) else {
            return XCTFail("expected to wait")
        }
        XCTAssertEqual(remaining, 0.3, accuracy: 0.001)
    }

    func testAChangeAfterTheQuietPeriodRebuildsAgain() {
        var state = settled()
        XCTAssertEqual(ask(&state, at: 0), .rebuild)
        XCTAssertEqual(ask(&state, at: 1.0), .rebuild)
    }

    func testTheFirstRequestAlwaysRebuilds() {
        var state = settled()
        XCTAssertEqual(ask(&state, at: 123.456), .rebuild)
    }

    // MARK: - Changes that are not changes

    /// Building the capture graph moves devices around, and Core Audio reports
    /// that like any other change. Acting on it meant the graph rebuilt because
    /// it had just started, then rebuilt because it had just restarted — about
    /// one cycle a second, forever, with a transcription error on each pass.
    func testIgnoresAnythingWhileTheGraphIsStillComingUp() {
        var state = CaptureRestartPolicy.State()
        state.started(at: 0, fingerprint: "1/2")

        XCTAssertEqual(ask(&state, at: 0.1, devices: "9/9"), .ignore("still starting"))
        XCTAssertEqual(ask(&state, at: 1.9, devices: "9/9"), .ignore("still starting"))
        XCTAssertEqual(ask(&state, at: 2.5, devices: "9/9"), .rebuild)
    }

    /// Core Audio reports changes that move nothing.
    func testIgnoresANotificationThatLeavesTheDevicesAlone() {
        var state = settled(devices: "1/2")
        XCTAssertEqual(ask(&state, at: 10, devices: "1/2"), .ignore("same devices"))
    }

    func testANotificationThatIgnoresCostsNoAttempt() {
        var state = settled(devices: "1/2")
        for tick in 0..<50 {
            _ = ask(&state, at: Double(tick), devices: "1/2")
        }
        XCTAssertEqual(ask(&state, at: 99, devices: "9/9"), .rebuild, "ignoring must not burn the budget")
    }

    // MARK: - Giving up

    /// A device that keeps changing must not spin forever.
    func testGivesUpAfterTooManyAttempts() {
        var state = settled()
        for attempt in 0..<policy.maximumConsecutiveAttempts {
            XCTAssertEqual(ask(&state, at: Double(attempt), devices: "\(attempt)/x"), .rebuild)
        }
        XCTAssertEqual(ask(&state, at: 99), .giveUp)
    }

    /// Audio flowing again means the previous trouble is over — but only if it
    /// keeps flowing. A trickle between two failures used to reset the counter,
    /// which is why a graph that rebuilt every second never gave up.
    func testSuccessClearsTheAttemptCountOnlyOnceAudioHasLasted() {
        var state = CaptureRestartPolicy.State()
        state.started(at: 0, fingerprint: "1/2")
        for attempt in 0..<policy.maximumConsecutiveAttempts {
            _ = ask(&state, at: Double(attempt) + 3, devices: "\(attempt)/x")
        }

        // Half a second of audio right after a restart proves nothing.
        policy.succeeded(at: 0.5, state: &state)
        XCTAssertEqual(ask(&state, at: 99), .giveUp)

        // Long enough to mean the graph is actually up.
        policy.succeeded(at: policy.successRequires + 1, state: &state)
        XCTAssertEqual(ask(&state, at: 200), .rebuild)
    }

    /// The loop as it was reported: every rebuild is followed by a fresh start,
    /// a notification the start itself caused, and a moment of audio.
    func testTheReportedLoopCannotHappen() {
        var state = CaptureRestartPolicy.State()
        var rebuilds = 0
        var now = 0.0

        for _ in 0..<40 {
            state.started(at: now, fingerprint: "1/2")
            now += 0.3
            // The notification our own setup caused.
            if ask(&state, at: now, devices: "1/2") == .rebuild { rebuilds += 1 }
            now += 0.7
            policy.succeeded(at: now, state: &state)
        }

        XCTAssertEqual(rebuilds, 0, "the graph must not rebuild because it started")
    }
}
