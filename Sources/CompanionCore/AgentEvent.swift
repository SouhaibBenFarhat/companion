import Foundation

/// The useful parts of one line of an agent's streaming output.
///
/// Both CLIs (command line interfaces) emit JSON Lines — one JSON (a text
/// format for data) object per line — with far more detail than a chat panel
/// needs. This is the subset the panel actually renders.
public enum AgentEvent: Equatable, Sendable {
    /// The agent's own session, reported on its first line. Store it and pass
    /// it back on the next question so follow-ups keep the thread.
    case sessionStarted(id: String)
    /// A chunk of the answer.
    case assistantText(String)
    /// The agent reached for a tool — shown as a small "reading X" line so the
    /// panel doesn't look frozen during the slow part.
    case toolUse(name: String)
    /// The run ended.
    case finished(result: String?, isError: Bool)
}

/// Turns one output line into zero or more `AgentEvent`s.
///
/// Deliberately forgiving: an unknown line type yields nothing rather than
/// throwing. These formats change between CLI releases, and a panel that goes
/// blank because of one unrecognised line would be worse than one that skips it.
public enum AgentEventDecoder {
    /// - Parameter partialMessages: whether the run was started with
    ///   `--include-partial-messages`. It changes which lines carry the answer:
    ///   with partials on, the text arrives as deltas AND again as a complete
    ///   assistant message at the end, so one of the two has to be ignored or
    ///   every answer appears twice.
    public static func decode(
        line: String,
        kind: AgentKind,
        partialMessages: Bool = false
    ) -> [AgentEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any]
        else { return [] }

        switch kind {
        case .claude: return decodeClaude(json, partialMessages: partialMessages)
        case .codex: return decodeCodex(json)
        }
    }

    // MARK: - Claude Code

    private static func decodeClaude(_ json: [String: Any], partialMessages: Bool) -> [AgentEvent] {
        let type = json["type"] as? String

        switch type {
        case "stream_event":
            guard partialMessages,
                  let event = json["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String,
                  !text.isEmpty
            else { return [] }
            return [.assistantText(text)]

        case "system":
            guard json["subtype"] as? String == "init",
                  let id = json["session_id"] as? String
            else { return [] }
            return [.sessionStarted(id: id)]

        case "assistant":
            guard let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { return [] }
            return content.compactMap { block in
                switch block["type"] as? String {
                case "text":
                    // Already delivered word by word; taking it again would
                    // repeat the whole answer under itself.
                    guard !partialMessages else { return nil }
                    guard let text = block["text"] as? String, !text.isEmpty else { return nil }
                    return .assistantText(text)
                case "tool_use":
                    guard let name = block["name"] as? String else { return nil }
                    return .toolUse(name: name)
                default:
                    return nil
                }
            }

        case "result":
            let isError = json["is_error"] as? Bool ?? false
            return [.finished(result: json["result"] as? String, isError: isError)]

        default:
            return []
        }
    }

    // MARK: - Codex

    // Codex reports a thread rather than a session, and wraps output in
    // "item" envelopes. Kept tolerant on purpose — verify the exact shapes
    // against `codex exec --json` output when the CLI is installed.
    private static func decodeCodex(_ json: [String: Any]) -> [AgentEvent] {
        let type = json["type"] as? String ?? ""

        if type.hasSuffix("thread.started") || type == "session.created" {
            if let id = json["thread_id"] as? String ?? json["session_id"] as? String {
                return [.sessionStarted(id: id)]
            }
            return []
        }

        if type == "turn.completed" || type == "turn.failed" {
            return [.finished(result: nil, isError: type == "turn.failed")]
        }

        guard type.hasPrefix("item."), let item = json["item"] as? [String: Any] else { return [] }

        switch item["type"] as? String {
        case "agent_message":
            guard let text = item["text"] as? String, !text.isEmpty else { return [] }
            return [.assistantText(text)]
        case "command_execution":
            return [.toolUse(name: "Bash")]
        case "file_change":
            return [.toolUse(name: "Edit")]
        case "error":
            return [.finished(result: item["message"] as? String, isError: true)]
        default:
            return []
        }
    }
}
