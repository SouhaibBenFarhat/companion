import Foundation

/// Reads and writes one Codable value as a JSON file.
///
/// Loading never throws: a missing, unreadable or corrupt file falls back to
/// `fallback`. A damaged conversation file should cost you that conversation,
/// not the ability to launch the app.
public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    public let url: URL
    public let fallback: Value

    public init(url: URL, fallback: Value) {
        self.url = url
        self.fallback = fallback
    }

    public func load() -> Value {
        guard let data = try? Data(contentsOf: url) else { return fallback }
        guard let value = try? Self.decoder.decode(Value.self, from: data) else { return fallback }
        return value
    }

    public func save(_ value: Value) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(value)
        // Atomic, so a crash mid-write can't leave a half-file behind.
        try data.write(to: url, options: .atomic)
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

/// Where Companion keeps its files: `~/Library/Application Support/Companion/`.
///
/// Everything stays on this machine. These are transcripts of work calls, so
/// there is no sync and no upload anywhere.
public enum StorageLocation {
    public static let directoryName = "Companion"

    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func settingsURL(in directory: URL) -> URL {
        directory.appendingPathComponent("settings.json")
    }

    /// One file per conversation, under `conversations/`.
    public static func conversationsDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent("conversations", isDirectory: true)
    }

    public static func conversationURL(id: String, in directory: URL) -> URL {
        conversationsDirectory(in: directory).appendingPathComponent("\(id).json")
    }
}
