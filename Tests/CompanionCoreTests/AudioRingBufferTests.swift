import XCTest
@testable import CompanionCore

final class AudioRingBufferTests: XCTestCase {
    func testStartsEmpty() {
        let buffer = AudioRingBuffer(capacity: 8)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.read(), [])
    }

    func testReadsBackWhatWasWritten() {
        let buffer = AudioRingBuffer(capacity: 8)
        buffer.write([1, 2, 3])
        XCTAssertEqual(buffer.read(), [1, 2, 3])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testReadsOldestFirst() {
        let buffer = AudioRingBuffer(capacity: 8)
        buffer.write([1, 2])
        buffer.write([3, 4])
        XCTAssertEqual(buffer.read(), [1, 2, 3, 4])
    }

    func testPartialRead() {
        let buffer = AudioRingBuffer(capacity: 8)
        buffer.write([1, 2, 3, 4])
        XCTAssertEqual(buffer.read(maximum: 2), [1, 2])
        XCTAssertEqual(buffer.count, 2)
        XCTAssertEqual(buffer.read(), [3, 4])
    }

    /// The index has to wrap without losing or reordering anything.
    func testWrapsAroundTheEnd() {
        let buffer = AudioRingBuffer(capacity: 4)
        buffer.write([1, 2, 3])
        XCTAssertEqual(buffer.read(maximum: 2), [1, 2])
        buffer.write([4, 5, 6])
        XCTAssertEqual(buffer.read(), [3, 4, 5, 6])
    }

    /// A late reader wants what is being said now, not a second ago.
    func testOverflowDropsTheOldest() {
        let buffer = AudioRingBuffer(capacity: 4)
        buffer.write([1, 2, 3, 4, 5, 6])
        XCTAssertEqual(buffer.read(), [3, 4, 5, 6])
        XCTAssertEqual(buffer.droppedFrames, 2)
    }

    /// A single write longer than the whole buffer would otherwise overwrite
    /// itself as it went.
    func testWriteLargerThanCapacityKeepsTheTail() {
        let buffer = AudioRingBuffer(capacity: 3)
        buffer.write([1, 2, 3, 4, 5])
        XCTAssertEqual(buffer.read(), [3, 4, 5])
        XCTAssertEqual(buffer.droppedFrames, 2)
    }

    /// A rising count is the signal that the consumer is too slow.
    func testCountsEveryDroppedFrame() {
        let buffer = AudioRingBuffer(capacity: 2)
        buffer.write([1, 2])
        buffer.write([3, 4])
        XCTAssertEqual(buffer.droppedFrames, 2)
        XCTAssertEqual(buffer.read(), [3, 4])
    }

    func testResetClearsEverything() {
        let buffer = AudioRingBuffer(capacity: 4)
        buffer.write([1, 2, 3, 4, 5])
        buffer.reset()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.droppedFrames, 0)
    }

    func testEmptyWriteIsHarmless() {
        let buffer = AudioRingBuffer(capacity: 4)
        buffer.write([])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testCapacityIsNeverZero() {
        let buffer = AudioRingBuffer(capacity: 0)
        buffer.write([1])
        XCTAssertEqual(buffer.read(), [1])
    }
}
