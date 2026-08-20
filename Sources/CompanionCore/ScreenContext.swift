import Foundation

/// What the user is looking at.
///
/// Deliberately small. The agent reads the repo itself, so this only carries
/// what it could not work out: which app, which window, which file, and the
/// visible text when the app will give it up.
public struct ScreenContext: Equatable, Sendable {
    public var appName: String
    public var bundleIdentifier: String?
    public var windowTitle: String?
    /// Resolved from the window title where possible, so an editor that will
    /// not give up its buffer can still say which file is open.
    public var filePath: String?
    /// The page a browser is on.
    public var url: String?
    /// Text from the focused element, when the app exposes it.
    public var selectionOrText: String?

    public init(
        appName: String,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        filePath: String? = nil,
        url: String? = nil,
        selectionOrText: String? = nil
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.filePath = filePath
        self.url = url
        self.selectionOrText = selectionOrText
    }

    /// One or two lines for the model. Nothing is padded — an empty field is
    /// left out rather than described as unknown.
    public var summary: String {
        var lines: [String] = []
        lines.append("App: \(appName)")
        if let filePath { lines.append("File: \(filePath)") }
        else if let windowTitle, !windowTitle.isEmpty { lines.append("Window: \(windowTitle)") }
        if let url { lines.append("URL: \(url)") }

        if let text = selectionOrText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            // Bounded. A whole file would swamp the question, and the agent can
            // read the file itself if it wants more.
            let clipped = text.count > 1_500 ? String(text.prefix(1_500)) + "…" : text
            lines.append("Visible text:\n\(Redaction.scrub(clipped))")
        }
        return lines.joined(separator: "\n")
    }

    public var isEmpty: Bool {
        appName.isEmpty && windowTitle == nil && filePath == nil && url == nil
    }
}

/// Pulls a file path out of a window title.
///
/// The fallback that makes Electron editors usable. VS Code will not give up
/// its buffer through the accessibility tree, but its window title names the
/// file — and a path is enough, because the agent can read the file itself,
/// which is both exact and free.
public enum WindowTitleParser {
    /// Folders never worth walking. A node_modules tree can be a hundred
    /// thousand files, and the answer is never in there.
    static let skippedDirectories: Set<String> = [
        "node_modules", ".git", ".build", "dist", "build", "Pods",
        ".next", ".venv", "venv", "target", "DerivedData", ".swiftpm",
    ]

    /// Titles look like "file.swift — folder — Visual Studio Code" or
    /// "file.swift (Edited) — MyApp". Separators vary by app and by locale.
    private static let separators = [" — ", " – ", " - ", " | "]

    /// The document part of a window title, with decorations removed.
    public static func documentName(from title: String) -> String? {
        var head = title
        for separator in separators {
            if let range = head.range(of: separator) {
                head = String(head[head.startIndex..<range.lowerBound])
                break
            }
        }

        // Editors mark unsaved work in the title.
        for marker in [" (Edited)", " (Modified)", " — Edited", " •"] {
            head = head.replacingOccurrences(of: marker, with: "")
        }
        head = head.trimmingCharacters(in: .whitespaces)
        // A leading bullet is the other common unsaved marker.
        if head.hasPrefix("• ") { head = String(head.dropFirst(2)) }

        return head.isEmpty ? nil : head
    }

    /// Whether the name looks like a file rather than a page or a chat.
    public static func looksLikeAFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, ext.count <= 5 else { return false }
        // A dot in a sentence is not an extension.
        return !ext.contains(" ") && ext.rangeOfCharacter(from: .letters) != nil
    }

    /// Resolves a bare filename against the repo the agent is pointed at.
    ///
    /// A title gives "AgentRunner.swift", not a path, so it is searched for.
    /// Returns nil rather than guessing when there is no single match.
    public static func resolve(
        documentName name: String,
        inRepository repository: URL,
        fileManager: FileManager = .default
    ) -> String? {
        guard looksLikeAFile(name) else { return nil }

        let direct = repository.appendingPathComponent(name)
        if fileManager.fileExists(atPath: direct.path) { return direct.path }

        guard let walker = fileManager.enumerator(
            at: repository,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var matches: [String] = []
        var visited = 0
        for case let url as URL in walker {
            if skippedDirectories.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            visited += 1
            // A bound, so a huge repository cannot stall the reader. Giving up
            // costs one piece of context; walking a million files costs the
            // responsiveness of the whole panel.
            if visited > 20_000 { return nil }

            guard url.lastPathComponent == name else { continue }
            matches.append(url.path)
            // Two files with the same name means the title cannot tell them
            // apart, so nothing is better than the wrong one.
            if matches.count > 1 { return nil }
        }
        return matches.first
    }
}
