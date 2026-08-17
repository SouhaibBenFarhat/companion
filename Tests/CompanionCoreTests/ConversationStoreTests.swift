import XCTest
@testable import CompanionCore

final class ConversationStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ConversationStore!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("companion-tests-\(UUID().uuidString)")
        store = ConversationStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSavesAndLoadsAConversation() throws {
        var conversation = Conversation(repositoryPath: "/tmp/repo", agentSessionID: "sess-1")
        conversation.append(Message(role: .user, text: "why?"))
        try store.save(conversation)

        let loaded = store.load(id: conversation.id)
        XCTAssertEqual(loaded?.id, conversation.id)
        XCTAssertEqual(loaded?.agentSessionID, "sess-1")
        XCTAssertEqual(loaded?.messages.count, 1)
    }

    /// Saving must work on a first run, before the folder exists.
    func testCreatesTheFolderOnFirstSave() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        try store.save(Conversation(repositoryPath: "/tmp/repo"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    func testLoadingSomethingMissingReturnsNil() {
        XCTAssertNil(store.load(id: "does-not-exist"))
    }

    func testListingAnEmptyStoreIsEmpty() {
        XCTAssertTrue(store.all().isEmpty)
    }

    func testListsNewestActivityFirst() throws {
        let older = Conversation(
            repositoryPath: "/tmp/repo",
            updatedAt: Date(timeIntervalSince1970: 1000)
        )
        let newer = Conversation(
            repositoryPath: "/tmp/repo",
            updatedAt: Date(timeIntervalSince1970: 2000)
        )
        try store.save(older)
        try store.save(newer)

        XCTAssertEqual(store.all().map(\.id), [newer.id, older.id])
    }

    func testFiltersByRepository() throws {
        try store.save(Conversation(repositoryPath: "/tmp/one"))
        try store.save(Conversation(repositoryPath: "/tmp/two"))

        XCTAssertEqual(store.forRepository("/tmp/one").count, 1)
        XCTAssertEqual(store.forRepository("/tmp/one").first?.repositoryPath, "/tmp/one")
    }

    /// The same repo typed two ways is still the same repo.
    func testRepositoryMatchingIgnoresATrailingSlash() throws {
        try store.save(Conversation(repositoryPath: "/tmp/one/"))
        XCTAssertEqual(store.forRepository("/tmp/one").count, 1)
    }

    func testDeletesAConversation() throws {
        let conversation = Conversation(repositoryPath: "/tmp/repo")
        try store.save(conversation)
        try store.delete(id: conversation.id)
        XCTAssertNil(store.load(id: conversation.id))
    }

    func testDeletingSomethingMissingIsNotAnError() {
        XCTAssertNoThrow(try store.delete(id: "does-not-exist"))
    }

    /// One damaged file must not take the whole history with it.
    func testSkipsUnreadableFilesWhenListing() throws {
        let good = Conversation(repositoryPath: "/tmp/repo")
        try store.save(good)
        try Data("this is not json".utf8).write(to: store.url(for: "broken"))

        XCTAssertEqual(store.all().map(\.id), [good.id])
    }

    func testIgnoresNonJSONFiles() throws {
        try store.save(Conversation(repositoryPath: "/tmp/repo"))
        try Data("notes".utf8).write(to: directory.appendingPathComponent("README.txt"))

        XCTAssertEqual(store.all().count, 1)
    }
}
