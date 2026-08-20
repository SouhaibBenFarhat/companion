import XCTest
@testable import CompanionCore

final class ContextDebouncerTests: XCTestCase {
    private let debouncer = ContextDebouncer(quietPeriod: 0.6, maximumSilence: 8)

    /// Switching apps should not feel delayed.
    func testTheFirstChangeAfterQuietReportsImmediately() {
        var state = ContextDebouncer.State()
        XCTAssertEqual(debouncer.changed(at: 0, state: &state), .report)
    }

    /// The accessibility API reports every keystroke. Reading the screen on
    /// each one means hundreds of cross-process messages a minute.
    func testTypingDoesNotReportOnEveryKeystroke() {
        var state = ContextDebouncer.State()
        _ = debouncer.changed(at: 0, state: &state)

        var reports = 0
        for keystroke in stride(from: 0.1, through: 1.5, by: 0.1) {
            if debouncer.changed(at: keystroke, state: &state) == .report { reports += 1 }
        }
        XCTAssertEqual(reports, 0)
    }

    func testReportsOnceTheScreenSettles() {
        var state = ContextDebouncer.State()
        _ = debouncer.changed(at: 0, state: &state)
        _ = debouncer.changed(at: 0.1, state: &state)

        XCTAssertEqual(debouncer.changed(at: 1.0, state: &state), .report)
    }

    func testWaitSaysHowLongIsLeft() {
        var state = ContextDebouncer.State()
        _ = debouncer.changed(at: 0, state: &state)

        guard case .wait(let remaining) = debouncer.changed(at: 0.2, state: &state) else {
            return XCTFail("expected to wait")
        }
        XCTAssertEqual(remaining, 0.4, accuracy: 0.001)
    }

    /// A long stretch of steady typing should not be invisible.
    func testReportsAnywayAfterTheMaximumSilence() {
        var state = ContextDebouncer.State()
        _ = debouncer.changed(at: 0, state: &state)

        var reports = 0
        for keystroke in stride(from: 0.1, through: 12.0, by: 0.1) {
            if debouncer.changed(at: keystroke, state: &state) == .report { reports += 1 }
        }
        XCTAssertGreaterThanOrEqual(reports, 1)
    }
}
