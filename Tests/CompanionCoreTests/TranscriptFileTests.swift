import XCTest
@testable import CompanionCore

final class TranscriptFileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file() -> TranscriptFile {
        TranscriptFile(url: TranscriptFile.directory(in: directory).appendingPathComponent("call.md"))
    }

    /// Two calls in one minute is an ordinary morning.
    func testNamesSortByTimeDownToTheSecond() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let at = { (h: Int, m: Int, sec: Int) in
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: h, minute: m, second: sec))!
        }

        let first = TranscriptFile.name(for: at(9, 30, 10), calendar: calendar)
        let second = TranscriptFile.name(for: at(9, 30, 45), calendar: calendar)
        XCTAssertEqual(first, "2026-03-09 09-30-10.md")
        XCTAssertLessThan(first, second)
    }

    /// The timestamp is where the words fall in the call, not the wall clock,
    /// so the transcript can be read against a recording.
    func testLinesCarryTheirPositionInTheCall() {
        let line = TranscriptFile.line(speaker: .them, text: "  it throws on the second buffer  ", at: 125)
        XCTAssertEqual(line, "[02:05] **The call:** it throws on the second buffer\n")
    }

    func testNegativeSecondsCannotProduceAStrangeStamp() {
        XCTAssertTrue(TranscriptFile.line(speaker: .me, text: "hello", at: -4).hasPrefix("[00:00]"))
    }

    func testWritesAHeaderAndThenTheLines() throws {
        let file = self.file()
        try file.begin(at: Date())
        try file.append(speaker: .me, text: "does this compile", at: 3)
        try file.append(speaker: .them, text: "not on macOS 15", at: 7)

        let written = try String(contentsOf: file.url, encoding: .utf8)
        XCTAssertTrue(written.hasPrefix("# Call transcript"))
        XCTAssertTrue(written.contains("[00:03] **You:** does this compile"))
        XCTAssertTrue(written.contains("[00:07] **The call:** not on macOS 15"))
    }

    /// A transcript that only reaches disk on a clean quit is one you lose on
    /// the day something crashes mid-call.
    func testEveryLineIsOnDiskBeforeTheNextArrives() throws {
        let file = self.file()
        try file.begin(at: Date())

        for index in 1...5 {
            try file.append(speaker: .me, text: "line \(index)", at: TimeInterval(index))
            let written = try String(contentsOf: file.url, encoding: .utf8)
            XCTAssertTrue(written.contains("line \(index)"), "line \(index) was not flushed")
        }
    }

    func testSilenceWritesNothing() throws {
        let file = self.file()
        try file.begin(at: Date())
        try file.append(speaker: .me, text: "   \n  ", at: 1)

        let written = try String(contentsOf: file.url, encoding: .utf8)
        XCTAssertEqual(written, TranscriptFile.header(for: Date()).prefix(written.count).description)
    }

    /// Deleting the file mid-call must not throw the words away.
    func testAppendingRecreatesADeletedFile() throws {
        let file = self.file()
        try file.begin(at: Date())
        try FileManager.default.removeItem(at: file.url)

        try file.append(speaker: .them, text: "still here", at: 2)
        XCTAssertTrue(try String(contentsOf: file.url, encoding: .utf8).contains("still here"))
    }

    /// Off by default: a call transcript is mostly someone else's words.
    func testSavingIsOffUntilAskedFor() {
        XCTAssertFalse(AwarenessSettings().persistTranscript)
    }
}
