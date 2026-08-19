import XCTest
@testable import CompanionCore

final class RedactionTests: XCTestCase {
    private func assertMasked(_ text: String, _ secret: String, file: StaticString = #filePath, line: UInt = #line) {
        let scrubbed = Redaction.scrub(text)
        XCTAssertFalse(scrubbed.contains(secret), "leaked: \(scrubbed)", file: file, line: line)
        XCTAssertTrue(scrubbed.contains(Redaction.mask), "not masked: \(scrubbed)", file: file, line: line)
    }

    private func assertUntouched(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Redaction.scrub(text), text, file: file, line: line)
    }

    // MARK: - Secrets that must never reach disk

    func testMasksVendorKeys() {
        assertMasked("key sk-ant-api03-abcdefghijklmnop0123", "sk-ant-api03-abcdefghijklmnop0123")
        assertMasked("token ghp_abcdefghijklmnopqrstuvwxyz0123", "ghp_abcdefghijklmnopqrstuvwxyz0123")
        assertMasked("pat github_pat_11ABCDEFG0abcdefghijklmno", "github_pat_11ABCDEFG0abcdefghijklmno")
        assertMasked("slack xoxb-123456789012-abcdefghijkl", "xoxb-123456789012-abcdefghijkl")
        assertMasked("aws AKIAIOSFODNN7EXAMPLE", "AKIAIOSFODNN7EXAMPLE")
        assertMasked("google AIzaSyC1234567890abcdefghijklmnopqrstuv", "AIzaSyC1234567890abcdefghijklmnopqrstuv")
    }

    func testMasksAuthorizationHeaders() {
        assertMasked(
            "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345",
            "abcdefghijklmnopqrstuvwxyz012345"
        )
    }

    /// The header and footer stay so the log still says what was removed.
    func testMasksAWholePrivateKeyBlock() {
        let text = """
            -----BEGIN RSA PRIVATE KEY-----
            MIIEowIBAAKCAQEAxGdlP0Vs9m1QmvvNSFQ4
            -----END RSA PRIVATE KEY-----
            """
        let scrubbed = Redaction.scrub(text)
        XCTAssertFalse(scrubbed.contains("MIIEowIBAAKCAQEAxGdlP0Vs9m1QmvvNSFQ4"))
        XCTAssertEqual(scrubbed, Redaction.mask)
    }

    func testMasksJSONWebTokens() {
        assertMasked(
            "cookie eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27u",
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27u"
        )
    }

    /// Anchored on the variable NAME, so the value's shape does not matter.
    func testMasksSecretLookingAssignments() {
        assertMasked("ANTHROPIC_API_KEY=sk-test-value-here", "sk-test-value-here")
        assertMasked("DATABASE_PASSWORD: hunter2butlonger", "hunter2butlonger")
        assertMasked("MY_SERVICE_TOKEN = abc123def456", "abc123def456")
    }

    // MARK: - False positives matter more

    /// A log that masks ordinary code is a log nobody reads.
    func testLeavesOrdinaryCodeAlone() {
        assertUntouched("let total = price * quantity")
        assertUntouched("func build(kind: AgentKind) -> AgentCommand {")
        assertUntouched("git commit -m \"fix the retry loop\"")
        assertUntouched("import Foundation")
    }

    func testLeavesHarmlessEnvironmentVariablesAlone() {
        assertUntouched("PATH=/usr/bin:/opt/homebrew/bin")
        assertUntouched("HOME=/Users/me")
        assertUntouched("TERM=dumb")
        assertUntouched("LANG=en_GB.UTF-8")
    }

    func testLeavesOrdinaryProseAlone() {
        assertUntouched("The handler is attached twice, so every chunk fires both copies.")
        assertUntouched("Reading — AgentRunner.swift")
    }

    /// Hyphenated words must not look like a vendor key.
    func testLeavesHyphenatedWordsAlone() {
        assertUntouched("read-only mode is the default while pairing")
        assertUntouched("stream-json output format")
    }

    // MARK: - Behaviour

    func testMasksEveryOccurrenceNotJustTheFirst() {
        let scrubbed = Redaction.scrub("a ghp_aaaaaaaaaaaaaaaaaaaaaaaa b ghp_bbbbbbbbbbbbbbbbbbbbbbbb")
        XCTAssertFalse(scrubbed.contains("ghp_aaaaaaaaaaaaaaaaaaaaaaaa"))
        XCTAssertFalse(scrubbed.contains("ghp_bbbbbbbbbbbbbbbbbbbbbbbb"))
    }

    func testKeepsTheSurroundingText() {
        let scrubbed = Redaction.scrub("using key ghp_abcdefghijklmnopqrstuvwx to push")
        XCTAssertTrue(scrubbed.hasPrefix("using key "))
        XCTAssertTrue(scrubbed.hasSuffix(" to push"))
    }

    func testEmptyStringIsFine() {
        XCTAssertEqual(Redaction.scrub(""), "")
    }
}
