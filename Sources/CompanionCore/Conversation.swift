import Foundation

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    /// Something said out loud on the call, by the user.
    ///
    /// Kept in the conversation rather than in a transcript that evaporates.
    /// A call is the thing being worked on, so it belongs in the record of the
    /// work — you can scroll back to it, it survives a restart, and the agent
    /// is answering about a conversation it can see rather than a summary of
    /// one it was handed once.
    case spokenByUser
    /// Something said out loud by the person on the other end.
    case spokenByCall

    /// Whether this was said aloud rather than typed.
    public var isSpoken: Bool { self == .spokenByUser || self == .spokenByCall }

    public init(spokenBy speaker: CaptureSpeaker) {
        self = speaker == .me ? .spokenByUser : .spokenByCall
    }

    /// Who said it, for a transcript line.
    public var speaker: CaptureSpeaker? {
        switch self {
        case .spokenByUser: return .me
        case .spokenByCall: return .them
        case .user, .assistant: return nil
        }
    }
}

public struct Message: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var role: MessageRole
    public var text: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, role: MessageRole, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

/// One thread in the panel.
///
/// Holds two identities on purpose: `id` is ours, `agentSessionID` is the
/// agent's own session. Keeping both is what lets a follow-up reach an agent
/// that still remembers what it read, instead of one starting from nothing.
public struct Conversation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    /// Repo this thread is about. Conversations are listed per repo, so opening
    /// the panel while pairing on one project shows only its threads.
    public var repositoryPath: String
    public var agentSessionID: String?
    public var agent: AgentKind
    public var messages: [Message]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String = "",
        repositoryPath: String,
        agentSessionID: String? = nil,
        agent: AgentKind = .claude,
        messages: [Message] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.repositoryPath = repositoryPath
        self.agentSessionID = agentSessionID
        self.agent = agent
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// A short label for the sidebar, taken from the first thing you asked.
    /// Falls back to a placeholder so an empty thread is still selectable.
    public static func title(fromFirstMessage text: String, limit: Int = 48) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "New conversation" }
        guard cleaned.count > limit else { return cleaned }
        // Cut on a word boundary so the label doesn't end mid-word.
        let cut = cleaned.prefix(limit)
        if let lastSpace = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: lastSpace) > limit / 2 {
            return String(cut[cut.startIndex..<lastSpace]) + "…"
        }
        return String(cut) + "…"
    }

    public mutating func append(_ message: Message) {
        // Named after the first thing YOU asked, not the first thing said.
        //
        // The check used to require an empty conversation, which worked while
        // the first message was always a typed question. A call now fills the
        // record before anyone types, so that test never passed again and every
        // conversation stayed untitled.
        if title.isEmpty, message.role == .user {
            title = Self.title(fromFirstMessage: message.text)
        }
        messages.append(message)
        updatedAt = message.createdAt
    }
}
