import Foundation

/// The environment handed to a spawned agent.
///
/// Two separate problems, both of which look like "the app is broken":
///
/// 1. **PATH.** These CLIs (command line interfaces) are Node scripts starting
///    with `#!/usr/bin/env node`. A launched `.app` inherits no shell PATH, so
///    even an absolute path to the binary fails — the shebang cannot find node.
///
/// 2. **Nested-session markers.** A Claude Code session exports `CLAUDECODE`,
///    `CLAUDE_CODE_*` and friends into every process it starts. An agent that
///    sees them believes it is running inside another agent and waits forever
///    on a session socket that does not belong to it. The panel just spins on
///    "Thinking" with nothing on stderr to explain why.
public enum AgentEnvironment {
    /// Exact variables that mark "you are inside a running agent session".
    public static let nestedSessionKeys: Set<String> = [
        "CLAUDECODE",
        "CLAUDE_PID",
        "CLAUDE_AGENT_SDK_VERSION",
        "CODEX_SANDBOX",
        "CODEX_SANDBOX_NETWORK_DISABLED",
    ]

    /// Whole families of the same thing.
    public static let nestedSessionPrefixes: [String] = [
        "CLAUDE_CODE_",
    ]

    /// Credentials and endpoints belonging to whoever launched us.
    ///
    /// Companion's whole premise is that the CLI already holds your
    /// subscription login. Forwarding these contradicts it: an inherited
    /// `ANTHROPIC_BASE_URL` switches the CLI out of subscription mode into
    /// API-key mode, and with no key it creates a session and then hangs
    /// without ever printing why. Whatever launched the app — a terminal, a
    /// parent agent — its API configuration is not ours to pass on.
    public static let inheritedCredentialKeys: Set<String> = [
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_MODEL",
        "OPENAI_BASE_URL",
        "OPENAI_API_KEY",
    ]

    public static func isNestedSessionKey(_ key: String) -> Bool {
        nestedSessionKeys.contains(key) || nestedSessionPrefixes.contains { key.hasPrefix($0) }
    }

    public static func shouldDrop(_ key: String) -> Bool {
        isNestedSessionKey(key) || inheritedCredentialKeys.contains(key)
    }

    /// Builds the child environment from the app's own.
    ///
    /// The CLI reads its own credentials from the keychain and its own config
    /// files. Anything it needs, it already has; anything we forward can only
    /// override that with settings meant for a different process.
    public static func forAgent(
        inheriting parent: [String: String],
        searchPaths: [String]? = nil
    ) -> [String: String] {
        var environment = parent.filter { !shouldDrop($0.key) }

        environment["PATH"] = AgentLocator.searchPathValue(searchPaths, inheriting: parent["PATH"])
        // No terminal here, so colour escape codes would be rendered as text.
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"

        return environment
    }
}
