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

    /// Whether the panel was open when Companion last quit.
    ///
    /// Restored at launch. A panel that always starts hidden means every
    /// restart costs a keystroke to get back to where you were, which during
    /// development is every few minutes.
    public var panelWasVisible: Bool

    /// Which microphone to record. Empty means the system default.
    ///
    /// Stored as the device's unique identifier rather than its name, so the
    /// choice survives a rename and cannot match the wrong device.
    public var microphoneDeviceUID: String

    /// Whether the panel is hidden from screen capture.
    ///
    /// On by default — it is the reason the app exists. Turned off for demos,
    /// screen recordings, and development, where a window nobody can capture
    /// is a window nobody can show or screenshot.
    public var hideFromScreenShare: Bool

    /// Show/hide shortcut. Carbon key code plus modifier mask.
    public var hotKeyCode: UInt32
    public var hotKeyModifiers: UInt32

    /// Listening and watching.
    public var awareness: AwarenessSettings

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
        panelWasVisible: Bool = false,
        microphoneDeviceUID: String = "",
        hideFromScreenShare: Bool = true,
        hotKeyCode: UInt32 = 49, // Space
        hotKeyModifiers: UInt32 = 2048, // Option
        awareness: AwarenessSettings = AwarenessSettings()
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
        self.panelWasVisible = panelWasVisible
        self.microphoneDeviceUID = microphoneDeviceUID
        self.hideFromScreenShare = hideFromScreenShare
        self.hotKeyCode = hotKeyCode
        self.hotKeyModifiers = hotKeyModifiers
        self.awareness = awareness
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
        panelWasVisible = try container.decodeIfPresent(Bool.self, forKey: .panelWasVisible)
            ?? defaults.panelWasVisible
        microphoneDeviceUID = try container.decodeIfPresent(String.self, forKey: .microphoneDeviceUID)
            ?? defaults.microphoneDeviceUID
        hideFromScreenShare = try container.decodeIfPresent(Bool.self, forKey: .hideFromScreenShare)
            ?? defaults.hideFromScreenShare
        hotKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotKeyCode) ?? defaults.hotKeyCode
        hotKeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotKeyModifiers)
            ?? defaults.hotKeyModifiers
        awareness = try container.decodeIfPresent(AwarenessSettings.self, forKey: .awareness)
            ?? defaults.awareness
    }

    /// Whether the global shortcut actually changed.
    ///
    /// `AppDelegate` re-registers the hotkey whenever settings are saved, which
    /// is on every keystroke in the settings sheet — tearing down and rebuilding
    /// a system-wide shortcut each time.
    public func hotKeyChanged(from other: Settings) -> Bool {
        hotKeyCode != other.hotKeyCode || hotKeyModifiers != other.hotKeyModifiers
    }

    /// The repo to run in, falling back to the home directory so a fresh
    /// install still answers instead of failing to spawn.
    public func repositoryURL(fileManager: FileManager = .default) -> URL {
        guard !defaultRepositoryPath.isEmpty else { return fileManager.homeDirectoryForCurrentUser }
        return URL(fileURLWithPath: (defaultRepositoryPath as NSString).expandingTildeInPath)
    }
}
