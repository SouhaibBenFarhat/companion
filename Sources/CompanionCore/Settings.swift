import Foundation

/// User preferences plus the bits of window state we want back after a restart.
///
/// Decoding fills in defaults for anything missing, so an older settings file
/// (or a hand-edited one) still loads instead of resetting everything.
public struct Settings: Codable, Equatable, Sendable {
    /// Which CLI (command line interface) answers questions.
    public var agent: AgentKind

    /// Absolute path to that binary.
    ///
    /// Absolute on purpose. A launched `.app` does not inherit your shell PATH,
    /// so `claude` resolves fine in Terminal and not at all from the app
    /// bundle. Empty means "look in the usual install spots at startup".
    public var agentPath: String

    /// Repo the agent runs in. Everything it can read is scoped to this.
    public var defaultRepositoryPath: String

    /// Whether the agent may change files. Read only while pairing.
    public var permission: AgentPermission

    /// Appended to the agent's own system prompt, never replacing it.
    public var systemPrompt: String

    /// Panel frame in screen points, nil until first move or resize.
    public var panelOriginX: Double?
    public var panelOriginY: Double?
    public var panelWidth: Double
    public var panelHeight: Double

    /// Show/hide shortcut. Carbon key code plus modifier mask.
    public var hotKeyCode: UInt32
    public var hotKeyModifiers: UInt32

    public init(
        agent: AgentKind = .claude,
        agentPath: String = "",
        defaultRepositoryPath: String = "",
        permission: AgentPermission = .readOnly,
        systemPrompt: String = DefaultSystemPrompt.text,
        panelOriginX: Double? = nil,
        panelOriginY: Double? = nil,
        panelWidth: Double = 460,
        panelHeight: Double = 560,
        hotKeyCode: UInt32 = 49, // Space
        hotKeyModifiers: UInt32 = 2048 // Option
    ) {
        self.agent = agent
        self.agentPath = agentPath
        self.defaultRepositoryPath = defaultRepositoryPath
        self.permission = permission
        self.systemPrompt = systemPrompt
        self.panelOriginX = panelOriginX
        self.panelOriginY = panelOriginY
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
        self.hotKeyCode = hotKeyCode
        self.hotKeyModifiers = hotKeyModifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        agent = try container.decodeIfPresent(AgentKind.self, forKey: .agent) ?? defaults.agent
        agentPath = try container.decodeIfPresent(String.self, forKey: .agentPath) ?? defaults.agentPath
        defaultRepositoryPath = try container.decodeIfPresent(String.self, forKey: .defaultRepositoryPath)
            ?? defaults.defaultRepositoryPath
        permission = try container.decodeIfPresent(AgentPermission.self, forKey: .permission) ?? defaults.permission
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? defaults.systemPrompt
        panelOriginX = try container.decodeIfPresent(Double.self, forKey: .panelOriginX)
        panelOriginY = try container.decodeIfPresent(Double.self, forKey: .panelOriginY)
        panelWidth = try container.decodeIfPresent(Double.self, forKey: .panelWidth) ?? defaults.panelWidth
        panelHeight = try container.decodeIfPresent(Double.self, forKey: .panelHeight) ?? defaults.panelHeight
        hotKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotKeyCode) ?? defaults.hotKeyCode
        hotKeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotKeyModifiers)
            ?? defaults.hotKeyModifiers
    }

    /// The repo to run in, falling back to the home directory so a fresh
    /// install still answers instead of failing to spawn.
    public func repositoryURL(fileManager: FileManager = .default) -> URL {
        guard !defaultRepositoryPath.isEmpty else { return fileManager.homeDirectoryForCurrentUser }
        return URL(fileURLWithPath: (defaultRepositoryPath as NSString).expandingTildeInPath)
    }
}
