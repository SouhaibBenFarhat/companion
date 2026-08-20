import XCTest
@testable import CompanionCore

final class ScreenContextTests: XCTestCase {
    // MARK: - Summary

    func testSummaryNamesTheApp() {
        XCTAssertTrue(ScreenContext(appName: "Xcode").summary.contains("App: Xcode"))
    }

    func testAFilePathBeatsAWindowTitle() {
        let context = ScreenContext(
            appName: "Code",
            windowTitle: "AgentRunner.swift — companion",
            filePath: "/Users/me/companion/Sources/AgentRunner.swift"
        )
        XCTAssertTrue(context.summary.contains("File: /Users/me/companion"))
        XCTAssertFalse(context.summary.contains("Window:"))
    }

    func testTheWindowTitleIsUsedWhenThereIsNoPath() {
        let context = ScreenContext(appName: "Slack", windowTitle: "general — parcelLab")
        XCTAssertTrue(context.summary.contains("Window: general"))
    }

    /// Empty fields are left out rather than described as unknown, which would
    /// spend tokens saying nothing.
    func testNothingIsPaddedOut() {
        let summary = ScreenContext(appName: "Finder").summary
        XCTAssertFalse(summary.contains("URL"))
        XCTAssertFalse(summary.contains("File"))
        XCTAssertFalse(summary.contains("Visible text"))
    }

    /// A whole file would swamp the question, and the agent can read the file
    /// itself if it wants more.
    func testVisibleTextIsBounded() {
        let context = ScreenContext(appName: "Xcode", selectionOrText: String(repeating: "x", count: 5_000))
        XCTAssertLessThan(context.summary.count, 1_700)
        XCTAssertTrue(context.summary.hasSuffix("…"))
    }

    /// A key on screen is exactly the kind of thing that ends up in a prompt.
    func testSecretsOnScreenAreMasked() {
        let context = ScreenContext(
            appName: "Terminal",
            selectionOrText: "export GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwx"
        )
        XCTAssertFalse(context.summary.contains("ghp_abcdefghijklmnopqrstuvwx"))
    }

    // MARK: - Window titles

    func testStripsTheAppNameFromATitle() {
        XCTAssertEqual(
            WindowTitleParser.documentName(from: "AgentRunner.swift — companion — Visual Studio Code"),
            "AgentRunner.swift"
        )
    }

    func testHandlesTheOtherSeparators() {
        XCTAssertEqual(WindowTitleParser.documentName(from: "notes.md - Sublime"), "notes.md")
        XCTAssertEqual(WindowTitleParser.documentName(from: "app.ts | Editor"), "app.ts")
        XCTAssertEqual(WindowTitleParser.documentName(from: "main.rs – Zed"), "main.rs")
    }

    /// Editors mark unsaved work in the title, and the marker is not part of
    /// the filename.
    func testStripsUnsavedMarkers() {
        XCTAssertEqual(WindowTitleParser.documentName(from: "App.swift (Edited) — MyApp"), "App.swift")
        XCTAssertEqual(WindowTitleParser.documentName(from: "• App.swift — Code"), "App.swift")
    }

    func testATitleWithNoSeparatorIsUsedWhole() {
        XCTAssertEqual(WindowTitleParser.documentName(from: "Untitled"), "Untitled")
    }

    func testAnEmptyTitleGivesNothing() {
        XCTAssertNil(WindowTitleParser.documentName(from: ""))
        XCTAssertNil(WindowTitleParser.documentName(from: "   — Code"))
    }

    // MARK: - Telling a file from a page

    func testRecognisesFilenames() {
        XCTAssertTrue(WindowTitleParser.looksLikeAFile("AgentRunner.swift"))
        XCTAssertTrue(WindowTitleParser.looksLikeAFile("index.html"))
        XCTAssertTrue(WindowTitleParser.looksLikeAFile("Package.swift"))
    }

    /// A dot in a sentence is not an extension, and a chat title is not a file.
    func testRejectsThingsThatAreNotFiles() {
        XCTAssertFalse(WindowTitleParser.looksLikeAFile("general"))
        XCTAssertFalse(WindowTitleParser.looksLikeAFile("Inbox (23)"))
        XCTAssertFalse(WindowTitleParser.looksLikeAFile("Meeting notes. Draft"))
        XCTAssertFalse(WindowTitleParser.looksLikeAFile("github.com/user/repo"))
    }

    // MARK: - Resolving against the repo

    func testFindsAFileNestedInTheRepo() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("companion-screen-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("Sources/Deep")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = nested.appendingPathComponent("Target.swift")
        try Data("//".utf8).write(to: file)

        // On macOS /var is a symlink to /private/var, and the enumerator
        // reports the resolved form.
        let found = WindowTitleParser.resolve(documentName: "Target.swift", inRepository: root)
        XCTAssertEqual(
            found.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
            file.resolvingSymlinksInPath().path
        )
    }

    /// Two files with the same name means the title cannot tell them apart, and
    /// the wrong file is worse than none.
    func testAnAmbiguousNameResolvesToNothing() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("companion-screen-\(UUID().uuidString)")
        for folder in ["A", "B"] {
            let directory = root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("//".utf8).write(to: directory.appendingPathComponent("Same.swift"))
        }
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNil(WindowTitleParser.resolve(documentName: "Same.swift", inRepository: root))
    }

    func testANameThatIsNotAFileIsNotSearchedFor() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        XCTAssertNil(WindowTitleParser.resolve(documentName: "general", inRepository: root))
    }
}
