import Foundation

/// Finds the agent binary on disk.
///
/// This exists because of one specific bug: a launched `.app` does not inherit
/// your shell PATH. `claude` works perfectly in Terminal and then fails with
/// "command not found" from the app bundle, which looks like the CLI (command
/// line interface) is broken when nothing is wrong. So we look in the places
/// these tools actually install to, and store an absolute path.
public enum AgentLocator {
    /// Install locations, most specific first. Node version managers come
    /// before the system directories because that is where these tools land.
    public static let defaultSearchPaths: [String] = [
        "~/.volta/bin",
        "~/.claude/local",
        "~/.local/bin",
        "~/.bun/bin",
        "~/.npm-global/bin",
        "~/.yarn/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
    ]

    public static func locate(
        _ kind: AgentKind,
        searchPaths: [String] = defaultSearchPaths,
        fileManager: FileManager = .default
    ) -> URL? {
        for path in searchPaths {
            let directory = (path as NSString).expandingTildeInPath
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(kind.executableName)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// A PATH value to hand the spawned agent.
    ///
    /// Not the same problem as finding the binary, and easy to miss: these
    /// CLIs are Node scripts starting with `#!/usr/bin/env node`. Launching one
    /// by absolute path from an app with an empty PATH still fails, because the
    /// shebang cannot find `node`. So the child gets a PATH covering the same
    /// install spots, with anything it already inherited kept on the end.
    public static func searchPathValue(
        _ searchPaths: [String] = defaultSearchPaths,
        inheriting inherited: String? = nil
    ) -> String {
        var seen = Set<String>()
        var parts: [String] = []

        for path in searchPaths + (inherited?.components(separatedBy: ":") ?? []) {
            let expanded = (path as NSString).expandingTildeInPath
            guard !expanded.isEmpty, seen.insert(expanded).inserted else { continue }
            parts.append(expanded)
        }
        return parts.joined(separator: ":")
    }

    /// The configured path if it still exists, otherwise a fresh search.
    ///
    /// Re-checking matters: these CLIs get upgraded and moved, and a stale
    /// stored path would leave the panel silently unable to answer.
    public static func resolve(
        kind: AgentKind,
        configuredPath: String,
        searchPaths: [String] = defaultSearchPaths,
        fileManager: FileManager = .default
    ) -> URL? {
        let expanded = (configuredPath as NSString).expandingTildeInPath
        if !expanded.isEmpty, fileManager.isExecutableFile(atPath: expanded) {
            return URL(fileURLWithPath: expanded)
        }
        return locate(kind, searchPaths: searchPaths, fileManager: fileManager)
    }
}
