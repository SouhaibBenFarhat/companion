import Foundation

/// Finds the built React UI (user interface).
///
/// Three places, in order, because the app runs three ways: against the Vite
/// dev server while working on the UI, out of the app bundle once installed,
/// and out of the source tree during `swift run`.
enum WebContent {
    enum Source {
        /// Vite dev server, for hot reload.
        case remote(URL)
        /// Built files. `readAccess` is the folder WKWebView is allowed to
        /// read from — without it the page loads and every asset 404s.
        case local(index: URL, readAccess: URL)
    }

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default
    ) -> Source? {
        if let raw = environment["COMPANION_WEB_URL"], let url = URL(string: raw), url.scheme != nil {
            return .remote(url)
        }

        if let bundled = bundleResourceURL?.appendingPathComponent("web", isDirectory: true),
           fileManager.fileExists(atPath: bundled.appendingPathComponent("index.html").path) {
            return .local(index: bundled.appendingPathComponent("index.html"), readAccess: bundled)
        }

        if let sourceTree = sourceTreeWebDirectory(fileManager: fileManager) {
            return .local(index: sourceTree.appendingPathComponent("index.html"), readAccess: sourceTree)
        }

        return nil
    }

    /// Walks up from the running binary looking for `web/dist`, so
    /// `swift run Companion` works straight from a checkout.
    private static func sourceTreeWebDirectory(fileManager: FileManager) -> URL? {
        var directory = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()

        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("web/dist", isDirectory: true)
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("index.html").path) {
                return candidate
            }
            let parent = directory.deletingLastPathComponent()
            guard parent != directory else { break }
            directory = parent
        }
        return nil
    }
}
