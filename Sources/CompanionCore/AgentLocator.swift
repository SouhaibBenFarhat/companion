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

    /// Roots that hold one folder per installed runtime version.
    ///
    /// Version managers do not put binaries anywhere fixed. fnm in particular
    /// puts the copy on your PATH inside a per-shell folder named after the
    /// shell's process id, which no other process can ever see — so a tool
    /// installed there is invisible to a launched app unless the real
    /// versioned directory is searched instead.
    public static let versionedRoots: [(root: String, binSuffix: String)] = [
        ("~/.local/share/fnm/node-versions", "installation/bin"),
        ("~/.fnm/node-versions", "installation/bin"),
        ("~/.nvm/versions/node", "bin"),
        ("~/.asdf/installs/nodejs", "bin"),
    ]

    /// Expands those roots into real directories, newest version first.
    public static func versionedSearchPaths(fileManager: FileManager = .default) -> [String] {
        versionedRoots.flatMap { root, suffix -> [String] in
            let base = (root as NSString).expandingTildeInPath
            let versions = (try? fileManager.contentsOfDirectory(atPath: base)) ?? []
            return versions
                .sorted { isNewer($0, than: $1) }
                .map { "\(base)/\($0)/\(suffix)" }
        }
    }

    /// Compares version folder names so v22 beats v9, which a plain string
    /// sort gets backwards.
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        func parts(_ name: String) -> [Int] {
            name.drop(while: { !$0.isNumber })
                .split(separator: ".")
                .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(lhs), b = parts(rhs)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Every place worth looking: the fixed folders plus whatever version
    /// managers currently have installed.
    public static func allSearchPaths(fileManager: FileManager = .default) -> [String] {
        defaultSearchPaths + versionedSearchPaths(fileManager: fileManager)
    }

    /// - Parameter searchPaths: pass nil for the full default list. Passing an
    ///   explicit list means exactly that list, nothing appended.
    public static func locate(
        _ kind: AgentKind,
        searchPaths: [String]? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        for path in searchPaths ?? allSearchPaths(fileManager: fileManager) {
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
        _ searchPaths: [String]? = nil,
        inheriting inherited: String? = nil
    ) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        let candidates = (searchPaths ?? allSearchPaths())
            + (inherited?.components(separatedBy: ":") ?? [])

        for path in candidates {
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
        searchPaths: [String]? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        let expanded = (configuredPath as NSString).expandingTildeInPath
        if !expanded.isEmpty, fileManager.isExecutableFile(atPath: expanded) {
            return URL(fileURLWithPath: expanded)
        }
        return locate(kind, searchPaths: searchPaths, fileManager: fileManager)
    }
}
