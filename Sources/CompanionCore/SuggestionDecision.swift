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
    /// Why, in a few words. Asked for only so that "decided to stay quiet" can
    /// be diagnosed instead of guessed at — a run of silences looks identical
    /// whether it saw a question and judged it answered, or never saw one.
    public let because: String?

    public init(speak: Bool, kind: Kind? = nil, text: String? = nil, because: String? = nil) {
        self.speak = speak
        self.kind = kind
        self.text = text
        self.because = because
    }

    /// The shape the reply must take, handed to the CLI as `--json-schema`.
    ///
    /// This is the difference between asking and enforcing. The CLI turns it
    /// into a tool the model has to call, and the runtime checks the arguments
    /// against it before Companion sees them — so a remark has nowhere to go,
    /// rather than being asked politely not to appear.
    ///
    /// `because` is required on purpose. A run of silences looked identical
    /// whether it had seen a question and judged it already answered or never
    /// seen one at all, and that was guessed at for three rounds.
    public static let schema = """
        {"type":"object",\
        "properties":{\
        "speak":{"type":"boolean","description":"Whether to show the user a note right now."},\
        "kind":{"type":"string","enum":["answer","correction","fact"],\
        "description":"answer: somebody on the call asked something and this answers it. correction: something said is wrong and this says what is true. fact: something they are missing and would want."},\
        "text":{"type":"string","description":"One sentence, shown to the user word for word. Required when speak is true."},\
        "because":{"type":"string","description":"A few words on why. Read by a person diagnosing a quiet run."}},\
        "required":["speak","because"]}
        """

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
