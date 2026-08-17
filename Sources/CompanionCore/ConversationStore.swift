import Foundation

/// Conversations on disk, one JSON (a text format for data) file each.
///
/// A file per thread rather than one database: easy to read when something
/// looks wrong, and easy to delete a single conversation by hand. For personal
/// use the whole folder stays small enough that listing it is instant.
public struct ConversationStore {
    public let directory: URL
    private let fileManager: FileManager

    /// - Parameter directory: the conversations folder itself, not the parent.
    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public static func inApplicationSupport(fileManager: FileManager = .default) -> ConversationStore {
        let base = StorageLocation.applicationSupportDirectory(fileManager: fileManager)
        return ConversationStore(
            directory: StorageLocation.conversationsDirectory(in: base),
            fileManager: fileManager
        )
    }

    public func save(_ conversation: Conversation) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(conversation)
        try data.write(to: url(for: conversation.id), options: .atomic)
    }

    public func load(id: String) -> Conversation? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? Self.decoder.decode(Conversation.self, from: data)
    }

    /// Every conversation, newest activity first. Unreadable files are skipped
    /// rather than failing the whole list.
    public func all() -> [Conversation] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Conversation? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? Self.decoder.decode(Conversation.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Threads about one repo. Paths are compared after resolving `~` and any
    /// trailing slash, so the same repo typed two ways still matches.
    public func forRepository(_ path: String) -> [Conversation] {
        let wanted = Self.normalize(path)
        return all().filter { Self.normalize($0.repositoryPath) == wanted }
    }

    public func delete(id: String) throws {
        let target = url(for: id)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    public func url(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    static func normalize(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return expanded.hasSuffix("/") && expanded.count > 1 ? String(expanded.dropLast()) : expanded
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
