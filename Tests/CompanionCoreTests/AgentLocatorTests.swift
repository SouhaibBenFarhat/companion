import XCTest
@testable import CompanionCore

final class AgentLocatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("companion-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeExecutable(_ name: String, in folder: String) throws -> URL {
        let directory = root.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func searchPaths(_ folders: [String]) -> [String] {
        folders.map { root.appendingPathComponent($0).path }
    }

    func testFindsTheBinary() throws {
        let expected = try makeExecutable("claude", in: "bin")
        XCTAssertEqual(AgentLocator.locate(.claude, searchPaths: searchPaths(["bin"])), expected)
    }

    func testReturnsNilWhenNothingIsInstalled() {
        XCTAssertNil(AgentLocator.locate(.codex, searchPaths: searchPaths(["bin"])))
    }

    func testSearchesInOrder() throws {
        let first = try makeExecutable("claude", in: "first")
        try makeExecutable("claude", in: "second")
        XCTAssertEqual(
            AgentLocator.locate(.claude, searchPaths: searchPaths(["first", "second"])),
            first
        )
    }

    func testSkipsMissingDirectories() throws {
        let expected = try makeExecutable("claude", in: "real")
        XCTAssertEqual(
            AgentLocator.locate(.claude, searchPaths: searchPaths(["nope", "real"])),
            expected
        )
    }

    /// A file that is not executable is not the binary we want.
    func testIgnoresNonExecutableFiles() throws {
        let directory = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("claude")
        try Data("just a note".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        XCTAssertNil(AgentLocator.locate(.claude, searchPaths: searchPaths(["bin"])))
    }

    func testDistinguishesTheTwoAgents() throws {
        try makeExecutable("claude", in: "bin")
        XCTAssertNotNil(AgentLocator.locate(.claude, searchPaths: searchPaths(["bin"])))
        XCTAssertNil(AgentLocator.locate(.codex, searchPaths: searchPaths(["bin"])))
    }

    func testResolvePrefersTheConfiguredPath() throws {
        let configured = try makeExecutable("claude", in: "configured")
        try makeExecutable("claude", in: "searched")

        XCTAssertEqual(
            AgentLocator.resolve(
                kind: .claude,
                configuredPath: configured.path,
                searchPaths: searchPaths(["searched"])
            ),
            configured
        )
    }

    /// These tools get upgraded and moved; a stale stored path would leave the
    /// panel silently unable to answer.
    func testResolveFallsBackWhenTheConfiguredPathIsStale() throws {
        let found = try makeExecutable("claude", in: "searched")
        XCTAssertEqual(
            AgentLocator.resolve(
                kind: .claude,
                configuredPath: "/nowhere/claude",
                searchPaths: searchPaths(["searched"])
            ),
            found
        )
    }

    func testResolveSearchesWhenNothingIsConfigured() throws {
        let found = try makeExecutable("claude", in: "searched")
        XCTAssertEqual(
            AgentLocator.resolve(kind: .claude, configuredPath: "", searchPaths: searchPaths(["searched"])),
            found
        )
    }

    /// The whole reason this type exists: a launched .app has no shell PATH,
    /// so the defaults have to cover where these tools really install.
    func testDefaultSearchPathsCoverTheUsualInstallSpots() {
        XCTAssertTrue(AgentLocator.defaultSearchPaths.contains("~/.volta/bin"))
        XCTAssertTrue(AgentLocator.defaultSearchPaths.contains("/opt/homebrew/bin"))
        XCTAssertTrue(AgentLocator.defaultSearchPaths.contains("/usr/local/bin"))
    }

    // MARK: - Version managers

    /// Newest wins, and a plain string sort would put v9 above v22.
    func testVersionOrderingIsNumericNotAlphabetical() {
        XCTAssertTrue(AgentLocator.isNewer("v22.22.3", than: "v22.21.1"))
        XCTAssertTrue(AgentLocator.isNewer("v22.0.0", than: "v9.99.99"))
        XCTAssertTrue(AgentLocator.isNewer("v18.20.8", than: "v18.20.7"))
        XCTAssertFalse(AgentLocator.isNewer("v18.20.8", than: "v22.0.0"))
    }

    func testVersionOrderingHandlesUnevenLengths() {
        XCTAssertTrue(AgentLocator.isNewer("v22.1", than: "v22"))
        XCTAssertFalse(AgentLocator.isNewer("v22", than: "v22.1"))
    }

    /// The gap that hid a working Codex install: fnm puts the copy on your
    /// PATH inside a per-shell folder no other process can see, so only the
    /// real versioned directory is findable from an app.
    func testVersionedRootsCoverTheCommonManagers() {
        let roots = AgentLocator.versionedRoots.map(\.root)
        XCTAssertTrue(roots.contains("~/.local/share/fnm/node-versions"))
        XCTAssertTrue(roots.contains("~/.nvm/versions/node"))
    }

    func testVersionedRootsPointAtTheBinFolder() {
        let fnm = AgentLocator.versionedRoots.first { $0.root.contains("fnm") }
        XCTAssertEqual(fnm?.binSuffix, "installation/bin")
    }

    // MARK: - PATH handed to the child process

    func testSearchPathValueExpandsTildes() {
        let value = AgentLocator.searchPathValue(["~/.volta/bin"])
        XCTAssertFalse(value.contains("~"))
        XCTAssertTrue(value.hasSuffix("/.volta/bin"))
    }

    func testSearchPathValueJoinsWithColons() {
        XCTAssertEqual(
            AgentLocator.searchPathValue(["/one", "/two"]),
            "/one:/two"
        )
    }

    func testSearchPathValueKeepsWhatTheProcessInherited() {
        let value = AgentLocator.searchPathValue(["/one"], inheriting: "/inherited")
        XCTAssertEqual(value, "/one:/inherited")
    }

    /// Our own directories come first, so a newer install wins over an old one
    /// left on the inherited PATH.
    func testSearchPathValueDropsDuplicates() {
        XCTAssertEqual(
            AgentLocator.searchPathValue(["/one", "/two"], inheriting: "/two:/three"),
            "/one:/two:/three"
        )
    }

    func testSearchPathValueIgnoresEmptySegments() {
        XCTAssertEqual(
            AgentLocator.searchPathValue(["/one"], inheriting: "::/two:"),
            "/one:/two"
        )
    }
}
