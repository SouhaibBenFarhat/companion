import Foundation

/// Renders a conversation into a file the user keeps.
///
/// Kept pure so the exact shape of an export is testable: an export is the one
/// copy of a conversation that leaves Companion's own folder, so its format is
/// a promise, not an implementation detail.
///
/// Both formats scrub credentials the way `ConversationStore.save` does. The
/// in-memory conversation keeps raw text for the session, but a file the user
/// hands to someone else must not carry a pasted key with it.
public enum ConversationExport {
    public enum Format: String, CaseIterable, Sendable {
        case markdown
        case json

        public var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .json: return "json"
            }
        }
    }

    /// The suggested file name, from the title.
    ///
    /// Slashes and colons are path machinery on macOS, not letters — a title
    /// that contains them must not decide where the file lands.
    public static func fileName(for conversation: Conversation, format: Format) -> String {
        // Scrubbed like the content: the title is cut from the first typed
        // message, and a pasted key must not become a file name in Finder.
        let cleaned = Redaction.scrub(conversation.title)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Conversation" : cleaned
        return "\(base).\(format.fileExtension)"
    }

    /// The whole thread as Markdown: a title, three lines of provenance, then
    /// one labelled block per message. Message text is written verbatim below
    /// its label rather than inline with it, so code fences inside an answer
    /// survive as code fences.
    public static func markdown(_ conversation: Conversation) -> String {
        let title = Redaction.scrub(conversation.title)
        var lines: [String] = [
            "# \(title.isEmpty ? "Conversation" : title)",
            "",
            "Repository: \(conversation.repositoryPath)",
            "Agent: \(conversation.agent.title)",
            "Started: \(iso.string(from: conversation.createdAt))",
        ]

        for message in conversation.messages {
            let text = Redaction.scrub(message.text)
            lines.append("")
            lines.append("**\(label(for: message.role, agent: conversation.agent))**")
            lines.append("")
            if message.role.isSpoken {
                // Speech is quoted, not parsed. A spoken line is not markdown,
                // and a blockquote both says so visually and keeps a stray
                // leading character from becoming document structure.
                lines.append(
                    text.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { "> \($0)" }
                        .joined(separator: "\n")
                )
            } else {
                lines.append(closingUnbalancedFence(in: text))
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// An answer cut off mid-stream can carry an odd number of code fences,
    /// and one open fence swallows every message after it — the rest of the
    /// export renders as one code blob. Balanced, not escaped: the well-formed
    /// majority must keep rendering as the markdown it is.
    static func closingUnbalancedFence(in text: String) -> String {
        let fences = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .count
        return fences.isMultiple(of: 2) ? text : text + "\n```"
    }

    /// The whole thread as JSON — the same shape the app stores on disk, so a
    /// script written against one works against the other.
    public static func json(_ conversation: Conversation) throws -> Data {
        var scrubbed = conversation
        scrubbed.title = Redaction.scrub(conversation.title)
        // The agent's own session id stays home. It is an internal handle —
        // enough to resume the session on this machine — and a stranger
        // reading the export has no use for it. The field is optional, so the
        // file still decodes as a Conversation.
        scrubbed.agentSessionID = nil
        scrubbed.messages = conversation.messages.map { message in
            var copy = message
            copy.text = Redaction.scrub(message.text)
            return copy
        }
        return try encoder.encode(scrubbed)
    }

    /// Who said it, in words a reader outside the app understands.
    static func label(for role: MessageRole, agent: AgentKind) -> String {
        switch role {
        case .user: return "You"
        case .assistant: return agent.title
        case .spokenByUser: return "You, on the call"
        case .spokenByCall: return "The call"
        case .noticed: return "Companion, unprompted"
        }
    }

    private static let iso = ISO8601DateFormatter()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
