import XCTest
@testable import CompanionCore

final class ExternalLinkTests: XCTestCase {
    func testOpensOrdinaryWebLinks() {
        XCTAssertEqual(ExternalLink.url(from: "https://example.com/docs")?.host, "example.com")
        XCTAssertEqual(ExternalLink.url(from: "http://localhost:3000")?.port, 3000)
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertNotNil(ExternalLink.url(from: "  https://example.com\n"))
    }

    /// The link text comes from an agent reading files, so it is not trusted.
    func testRefusesAnythingThatIsNotWeb() {
        for raw in [
            "file:///etc/passwd",
            "javascript:alert(1)",
            "data:text/html,<script>alert(1)</script>",
            "companion://settings",
            "mailto:someone@example.com",
        ] {
            XCTAssertNil(ExternalLink.url(from: raw), "\(raw) must not open")
        }
    }

    func testRefusesAWebSchemeWithNowhereToGo() {
        XCTAssertNil(ExternalLink.url(from: "https://"))
        XCTAssertNil(ExternalLink.url(from: "not a url"))
    }

    /// Upper case in the scheme must not be a way past the check.
    func testSchemeComparisonIgnoresCase() {
        XCTAssertNotNil(ExternalLink.url(from: "HTTPS://example.com"))
        XCTAssertNil(ExternalLink.url(from: "JavaScript:alert(1)"))
    }
}
