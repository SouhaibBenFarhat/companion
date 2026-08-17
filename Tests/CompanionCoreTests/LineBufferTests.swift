import XCTest
@testable import CompanionCore

final class LineBufferTests: XCTestCase {
    func testReturnsCompleteLines() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append("one\ntwo\n"), ["one", "two"])
    }

    /// The important case: a pipe read can stop halfway through a JSON object.
    func testHoldsBackAPartialLineUntilItCompletes() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(#"{"type":"assis"#), [])
        XCTAssertEqual(buffer.append("tant\"}\n"), [#"{"type":"assistant"}"#])
    }

    func testJoinsALineSplitAcrossThreeChunks() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append("a"), [])
        XCTAssertEqual(buffer.append("b"), [])
        XCTAssertEqual(buffer.append("c\n"), ["abc"])
    }

    func testHandlesSeveralLinesArrivingAtOnce() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append("one\ntwo\nthr"), ["one", "two"])
        XCTAssertEqual(buffer.append("ee\n"), ["three"])
    }

    func testSkipsBlankLines() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append("one\n\n  \ntwo\n"), ["one", "two"])
    }

    /// Some runs end without a trailing newline; that last line still matters.
    func testFlushReturnsTheTrailingPartialLine() {
        var buffer = LineBuffer()
        _ = buffer.append("done")
        XCTAssertEqual(buffer.flush(), ["done"])
    }

    func testFlushIsEmptyWhenNothingIsPending() {
        var buffer = LineBuffer()
        _ = buffer.append("one\n")
        XCTAssertEqual(buffer.flush(), [])
    }

    func testFlushClearsTheBuffer() {
        var buffer = LineBuffer()
        _ = buffer.append("done")
        XCTAssertEqual(buffer.flush(), ["done"])
        XCTAssertEqual(buffer.flush(), [])
    }
}
