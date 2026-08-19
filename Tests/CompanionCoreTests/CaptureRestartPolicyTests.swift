import XCTest
@testable import CompanionCore

final class CaptureRestartPolicyTests: XCTestCase {
    private let policy = CaptureRestartPolicy()

    /// Unplugging headphones fires several notifications within milliseconds.
    /// Rebuilding on each tears down a tap that is still being built.
    func testABurstYieldsOneRebuild() {
        var state = CaptureRestartPolicy.State()
        var rebuilds = 0

        for offset in stride(from: 0.0, through: 0.02, by: 0.005) {
            if policy.requestRebuild(at: offset, state: &state) == .rebuild { rebuilds += 1 }
        }
        XCTAssertEqual(rebuilds, 1)
    }

    func testWaitReportsHowLongIsLeft() {
        var state = CaptureRestartPolicy.State()
        XCTAssertEqual(policy.requestRebuild(at: 0, state: &state), .rebuild)

        guard case .wait(let remaining) = policy.requestRebuild(at: 0.1, state: &state) else {
            return XCTFail("expected to wait")
        }
        XCTAssertEqual(remaining, 0.3, accuracy: 0.001)
    }

    func testAChangeAfterTheQuietPeriodRebuildsAgain() {
        var state = CaptureRestartPolicy.State()
        XCTAssertEqual(policy.requestRebuild(at: 0, state: &state), .rebuild)
        XCTAssertEqual(policy.requestRebuild(at: 1.0, state: &state), .rebuild)
    }

    /// A device that keeps changing must not spin forever.
    func testGivesUpAfterTooManyAttempts() {
        var state = CaptureRestartPolicy.State()
        for attempt in 0..<policy.maximumConsecutiveAttempts {
            XCTAssertEqual(policy.requestRebuild(at: Double(attempt), state: &state), .rebuild)
        }
        XCTAssertEqual(policy.requestRebuild(at: 99, state: &state), .giveUp)
    }

    /// Audio flowing again means the previous trouble is over.
    func testSuccessClearsTheAttemptCount() {
        var state = CaptureRestartPolicy.State()
        for attempt in 0..<policy.maximumConsecutiveAttempts {
            _ = policy.requestRebuild(at: Double(attempt), state: &state)
        }
        policy.succeeded(state: &state)
        XCTAssertEqual(policy.requestRebuild(at: 99, state: &state), .rebuild)
    }

    func testTheFirstRequestAlwaysRebuilds() {
        var state = CaptureRestartPolicy.State()
        XCTAssertEqual(policy.requestRebuild(at: 123.456, state: &state), .rebuild)
    }
}
