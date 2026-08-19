import XCTest
@testable import CompanionCore

final class PCMChunkTests: XCTestCase {
    private func chunk(_ samples: [Float], rate: Double = 16_000, host: UInt64 = 1_000) -> PCMChunk {
        PCMChunk(speaker: .me, hostTimeNanoseconds: host, sampleRate: rate, samples: samples)
    }

    func testDurationFromFrameCountAndRate() {
        XCTAssertEqual(chunk([Float](repeating: 0, count: 16_000)).duration, 1.0, accuracy: 0.0001)
        XCTAssertEqual(chunk([Float](repeating: 0, count: 8_000)).duration, 0.5, accuracy: 0.0001)
    }

    func testDurationIsZeroWithoutARate() {
        XCTAssertEqual(chunk([1, 2, 3], rate: 0).duration, 0)
    }

    func testEndTimeAdvancesByTheDuration() {
        let block = chunk([Float](repeating: 0, count: 16_000), host: 1_000_000)
        XCTAssertEqual(block.endHostTimeNanoseconds, 1_000_000 + 1_000_000_000)
    }

    /// Root mean square, not peak — a meter driven by peak jumps on one click.
    func testLevelIsRootMeanSquare() {
        XCTAssertEqual(chunk([1, 1, 1, 1]).level, 1, accuracy: 0.0001)
        XCTAssertEqual(chunk([0, 0, 0, 0]).level, 0, accuracy: 0.0001)
        // ±0.5 has the same energy as a steady 0.5, which peak would miss.
        XCTAssertEqual(chunk([0.5, -0.5, 0.5, -0.5]).level, 0.5, accuracy: 0.0001)
    }

    func testLevelOfNothingIsZero() {
        XCTAssertEqual(chunk([]).level, 0)
    }

    func testSpeakerTitlesReadAsPeople() {
        XCTAssertEqual(CaptureSpeaker.me.title, "You")
        XCTAssertEqual(CaptureSpeaker.them.title, "The call")
    }
}
