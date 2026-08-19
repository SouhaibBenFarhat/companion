import XCTest
@testable import CompanionCore

final class SessionLogTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ ageInMinutes: Double, _ message: String = "hello") -> String {
        LogWindow.format(now.addingTimeInterval(-ageInMinutes * 60), "agent", message)
    }

    func testKeepsEntriesInsideTheWindow() {
        let kept = LogWindow.prune([line(5), line(59)], now: now)
        XCTAssertEqual(kept.count, 2)
    }

    func testDropsEntriesOlderThanTheWindow() {
        let kept = LogWindow.prune([line(61), line(5)], now: now)
        XCTAssertEqual(kept.count, 1)
        XCTAssertTrue(kept[0].contains("hello"))
    }

    func testDropsBlankLines() {
        XCTAssertEqual(LogWindow.prune(["", "   ", line(1)], now: now).count, 1)
    }

    /// A parsing change must never silently delete the evidence being read.
    func testKeepsLinesItCannotParse() {
        let kept = LogWindow.prune(["not a log line at all"], now: now)
        XCTAssertEqual(kept, ["not a log line at all"])
    }

    /// Pruning filters lines, so an entry spanning several would be cut in half.
    func testFormatFlattensMultilineMessages() {
        let formatted = LogWindow.format(now, "agent", "first\nsecond")
        XCTAssertFalse(formatted.contains("\n"))
        XCTAssertTrue(formatted.contains("first\\nsecond"))
    }

    func testFormatCarriesCategoryAndMessage() {
        let formatted = LogWindow.format(now, "spawn", "claude -p hi")
        XCTAssertTrue(formatted.contains("[spawn]"))
        XCTAssertTrue(formatted.hasSuffix("claude -p hi"))
    }

    func testWritesAndReadsBack() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("companion-log-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }

        let log = SessionLog(url: url)
        log.write("agent", "spawned")
        log.write("agent", "finished")

        let lines = log.read()
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("spawned"))
        XCTAssertTrue(lines[1].contains("finished"))
    }
}
