import Foundation

/// Why a run is failing, read from the agent's own debug file.
///
/// The CLI does report authentication failures — but only after retrying about
/// eleven times, which takes over three minutes. Until then it prints nothing
/// at all. Watching its debug file turns that silence into an answer in a few
/// seconds instead of a long wait followed by a wall of retry noise.
public enum AgentFailure: Equatable, Sendable {
    case expiredLogin
    case rateLimited
    case other(String)

    /// What the panel shows. Says what to do, not what went wrong internally.
    public var message: String {
        switch self {
        case .expiredLogin:
            return "Your agent login has expired. Run `claude` in a terminal and sign in with /login."
        case .rateLimited:
            return "The agent is rate limited right now. Wait a little and try again."
        case .other(let detail):
            return detail
        }
    }

    /// A stable name the interface can branch on, so the panel can offer the
    /// right button instead of parsing the message text.
    public var code: String {
        switch self {
        case .expiredLogin: return "expiredLogin"
        case .rateLimited: return "rateLimited"
        case .other: return "other"
        }
    }

    /// Whether to stop the run immediately rather than let it keep retrying.
    public var isFatal: Bool {
        switch self {
        case .expiredLogin, .rateLimited: return true
        case .other: return false
        }
    }
}

public enum AgentDiagnostics {
    /// Where Claude Code writes a debug file per session.
    public static func debugLogURL(
        sessionID: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home
            .appendingPathComponent(".claude/debug", isDirectory: true)
            .appendingPathComponent("\(sessionID).txt")
    }

    /// Lines about a connector rather than the agent's own API access.
    ///
    /// An unauthorised MCP (Model Context Protocol) server logs an
    /// authentication error too. Matching the whole file for that phrase
    /// reported "your login expired" at users who were perfectly signed in —
    /// their Jira or Drive connector was the thing that had lapsed.
    static func isAboutAConnector(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("mcp server") || lowered.contains("mcp client")
    }

    /// Reads a failure out of debug output. Nil means nothing has gone wrong yet.
    ///
    /// Line by line, because one file holds several unrelated subsystems and a
    /// whole-file search cannot tell whose error it found.
    public static func classify(_ text: String) -> AgentFailure? {
        for line in text.components(separatedBy: .newlines) {
            guard !isAboutAConnector(line) else { continue }
            let lowered = line.lowercased()

            // Anchored on the API's own auth: the phrase the model endpoint
            // returns, or the CLI telling you to sign in.
            if lowered.contains("oauth access token has expired")
                || lowered.contains("please run /login")
                || (lowered.contains("authentication_error") && lowered.contains("api")) {
                return .expiredLogin
            }
            if lowered.contains("rate_limit_error") {
                return .rateLimited
            }
        }
        return nil
    }

    /// Same, straight from the session's debug file.
    public static func inspect(
        sessionID: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> AgentFailure? {
        let url = debugLogURL(sessionID: sessionID, home: home)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return classify(text)
    }
}
