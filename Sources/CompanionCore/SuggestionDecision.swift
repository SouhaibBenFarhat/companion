import Foundation

/// What the model decided about interrupting, as a structure rather than prose.
///
/// Asking for free text and hoping for silence is the weakest instruction there
/// is: "reply with nothing at all" competes with everything a model is built to
/// do, and it loses. What came back was agreement with the speaker, textbook
/// asides, its own confusion, and once the prompt read back verbatim.
///
/// Asking it to fill in `speak` instead turns silence into an answer it can
/// give rather than an absence it has to manage. The kind field does the same
/// work from the other side: every value is something the user can act on, so
/// there is no box to put a remark in.
public struct SuggestionDecision: Codable, Equatable, Sendable {
    /// Why this is worth breaking into a conversation for.
    ///
    /// A closed set on purpose. "Nothing fits" is the common case and the
    /// honest answer, and it has somewhere to go: `speak` is false.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A question was asked on the call and this answers it.
        case answer
        /// Something said is wrong, and this is what is actually true.
        case correction
        /// A fact they are missing and would want — a limit, a version, a name.
        case fact

        public var title: String {
            switch self {
            case .answer: return "Answer"
            case .correction: return "Correction"
            case .fact: return "Worth knowing"
            }
        }
    }

    public let speak: Bool
    public let kind: Kind?
    public let text: String?

    public init(speak: Bool, kind: Kind? = nil, text: String? = nil) {
        self.speak = speak
        self.kind = kind
        self.text = text
    }

    /// Reads a decision out of whatever the model produced.
    ///
    /// Tolerant of a code fence and of prose either side of the object, because
    /// both happen and neither is a reason to lose a good note. Anything that
    /// is not a decision is silence — the safe direction, since the cost of a
    /// missed note is nothing and the cost of a wrong one is an interruption.
    public static func parse(_ raw: String) -> SuggestionDecision? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else {
            return nil
        }
        let json = String(raw[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        guard let decision = try? JSONDecoder().decode(SuggestionDecision.self, from: data) else {
            return nil
        }
        return decision
    }

    /// The note to show, or nil when the answer was silence.
    public var note: String? {
        guard speak, kind != nil else { return nil }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}
