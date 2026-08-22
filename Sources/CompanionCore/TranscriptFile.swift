import Foundation

/// Writes a call transcript to disk, one settled line at a time.
///
/// Append-only, and flushed on every line. A transcript that only exists in
/// memory until the app closes cleanly is a transcript you lose on the one day
/// something crashes mid-call — which is the day you wanted it.
///
/// Off by default and deliberately so: a transcript of a work call is someone
/// else's words, and the safest place for those is nowhere. Turning it on is a
/// decision the user makes about a conversation they are part of.
public struct TranscriptFile: Sendable {
    /// Where transcripts live, under the app's own folder.
    public static func directory(in base: URL) -> URL {
        base.appendingPathComponent("transcripts", isDirectory: true)
    }

    /// One file per listening session, named so it sorts by time.
    ///
    /// Seconds included: two calls in one minute is an ordinary morning.
    public static func name(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02d %02d-%02d-%02d.md",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }

    /// One line, as it goes into the file.
    ///
    /// Markdown, because it is read by a person: a heading per call, then
    /// `[mm:ss] **You:** text`. The timestamp is where the words fall in the
    /// call, not the wall clock, so a transcript can be read against a
    /// recording.
    public static func line(speaker: CaptureSpeaker, text: String, at seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let minutes = Int(clamped) / 60
        let remainder = Int(clamped) % 60
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(format: "[%02d:%02d] **%@:** %@\n", minutes, remainder, speaker.title, trimmed)
    }

    public static func header(for date: Date) -> String {
        let stamp = ISO8601DateFormatter().string(from: date)
        return "# Call transcript\n\n\(stamp)\n\n"
    }

    // MARK: - Writing

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Starts a file, creating the folder if it is not there yet.
    public func begin(at date: Date) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(Self.header(for: date).utf8).write(to: url, options: .atomic)
    }

    /// Adds one settled line.
    ///
    /// Opens, appends, closes. Slower than holding a handle open, and it means
    /// the file on disk is complete after every single line — including the
    /// line before a crash.
    public func append(speaker: CaptureSpeaker, text: String, at seconds: TimeInterval) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let data = Data(Self.line(speaker: speaker, text: trimmed, at: seconds).utf8)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            // No file yet — the first line arrived before begin(), or someone
            // deleted it mid-call. Either way, do not lose the words.
            try data.write(to: url, options: .atomic)
            return
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
