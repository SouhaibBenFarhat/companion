import Foundation

/// Keeps only what happened recently.
///
/// A panel that spawns a subprocess per question can produce a lot of noise,
/// and a log that grows without bound is one more thing to go wrong on someone
/// else's machine. Entries older than the window are dropped, so the file
/// stays small enough to read in one go and old sessions cannot bury the run
/// you are actually debugging.
public enum LogWindow {
    public static let oneHour: TimeInterval = 3600

    /// One entry per line: an ISO 8601 timestamp, a category, then the message.
    /// Single-line on purpose — pruning is a filter over lines, and a message
    /// spanning several would be cut in half.
    public static func format(_ date: Date, _ category: String, _ message: String) -> String {
        let stamp = ISO8601DateFormatter().string(from: date)
        let flat = Redaction.scrub(message)
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        return "\(stamp) [\(category)] \(flat)"
    }

    /// Drops entries older than `window`.
    ///
    /// A line whose timestamp cannot be read is kept: a parsing change should
    /// never silently delete the evidence you are trying to look at.
    public static func prune(
        _ lines: [String],
        now: Date,
        window: TimeInterval = oneHour
    ) -> [String] {
        let cutoff = now.addingTimeInterval(-window)
        let parser = ISO8601DateFormatter()

        return lines.filter { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            guard let stamp = line.split(separator: " ", maxSplits: 1).first,
                  let date = parser.date(from: String(stamp))
            else { return true }
            return date >= cutoff
        }
    }
}

/// A log file holding the last hour.
public final class SessionLog: @unchecked Sendable {
    public static let shared = SessionLog(
        url: StorageLocation.applicationSupportDirectory().appendingPathComponent("companion.log")
    )

    public let url: URL
    private let window: TimeInterval
    private let queue = DispatchQueue(label: "companion.log")
    private var sinceLastPrune = 0

    /// Pruning rewrites the whole file, so it happens every N writes rather
    /// than on each one.
    private let pruneEvery = 40

    public init(url: URL, window: TimeInterval = LogWindow.oneHour) {
        self.url = url
        self.window = window
    }

    public func write(_ category: String, _ message: String, at date: Date = Date()) {
        let line = LogWindow.format(date, category, message)
        queue.async { [self] in
            append(line)
            sinceLastPrune += 1
            if sinceLastPrune >= pruneEvery {
                sinceLastPrune = 0
                pruneFile(now: date)
            }
        }
    }

    public func read() -> [String] {
        queue.sync {
            (try? String(contentsOf: url, encoding: .utf8))?
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty } ?? []
        }
    }

    private func append(_ line: String) {
        let data = Data((line + "\n").utf8)
        let directory = url.deletingLastPathComponent()
        // Owner only. `~/Library` is already private, so this is defence in
        // depth rather than the main control.
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? data.write(to: url)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private func pruneFile(now: Date) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let kept = LogWindow.prune(text.components(separatedBy: "\n"), now: now, window: window)
        try? Data((kept.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }
}
