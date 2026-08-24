import Foundation

/// A macOS permission Companion needs, and what it blocks.
///
/// TCC is Transparency, Consent and Control — the part of macOS that holds
/// these grants. Each one is asked for separately, at a different moment, and
/// any of them can be taken away later without telling the app. So this is a
/// model of what is missing and what that costs, not a one-off check at launch.
public enum Permission: String, CaseIterable, Codable, Sendable {
    /// Your own voice.
    case microphone
    /// Everything the Mac plays, which is the other person on the call.
    /// Granted through Screen Recording even when no pixels are wanted.
    case systemAudio
    /// What is on screen, and the text of the window you are working in.
    case accessibility

    public var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "Screen Recording"
        case .accessibility: return "Accessibility"
        }
    }

    /// Said in terms of what stops working, not in terms of the API.
    public var reason: String {
        switch self {
        case .microphone:
            return "Hear your side of the call."
        case .systemAudio:
            return "Hear the other person. macOS puts system audio behind Screen Recording, so this is needed even though Companion captures no pixels."
        case .accessibility:
            return "See which file and window you are working in, and read the code on screen."
        }
    }

    /// The System Settings pane that grants it.
    public var settingsURL: URL {
        let pane: String
        switch self {
        case .microphone: pane = "Privacy_Microphone"
        case .systemAudio: pane = "Privacy_ScreenCapture"
        case .accessibility: pane = "Privacy_Accessibility"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }

    /// Whether the user must quit and reopen Companion after granting.
    ///
    /// Accessibility and Screen Recording are read once per process on first
    /// use. Granting them while the app is running leaves it believing it is
    /// still denied, which reads as the feature being broken.
    /// What this permission is called in the privacy database.
    ///
    /// Needed because a grant is filed against what the app's signature says,
    /// and replacing an unsigned build with a signed one leaves the old entry
    /// behind. macOS then has a decision on record for this bundle identifier,
    /// so it never prompts again — and the row in System Settings shows on
    /// while the app is refused. Clearing the entry is the only way out, and
    /// only the user can do it.
    public var tccService: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "ScreenCapture"
        case .accessibility: return "Accessibility"
        }
    }

    public func resetCommand(bundleIdentifier: String) -> String {
        "tccutil reset \(tccService) \(bundleIdentifier)"
    }

    public var needsRestartAfterGranting: Bool {
        switch self {
        case .microphone: return false
        case .systemAudio, .accessibility: return true
        }
    }
}

public enum PermissionState: String, Codable, Sendable {
    case granted
    case denied
    /// Never asked. Different from denied: it can still be resolved by a prompt
    /// rather than a trip to System Settings.
    case notAsked
}

public struct PermissionStatus: Codable, Equatable, Sendable {
    public let permission: Permission
    public let state: PermissionState

    public init(permission: Permission, state: PermissionState) {
        self.permission = permission
        self.state = state
    }

    public var isBlocking: Bool { state != .granted }
}

/// What a set of permission states allows.
///
/// Pure, so the rules are testable without a machine that has been granted
/// anything — which is otherwise impossible to arrange in CI (continuous
/// integration).
public struct PermissionReport: Equatable, Sendable {
    public let statuses: [PermissionStatus]

    public init(statuses: [PermissionStatus]) {
        self.statuses = statuses
    }

    public func state(of permission: Permission) -> PermissionState {
        statuses.first { $0.permission == permission }?.state ?? .notAsked
    }

    public var missing: [Permission] {
        statuses.filter(\.isBlocking).map(\.permission)
    }

    /// Listening needs both halves of the conversation. One without the other
    /// gives a transcript of a person talking to themselves, which is worse
    /// than none — so this is deliberately all or nothing.
    public var canListen: Bool {
        state(of: .microphone) == .granted && state(of: .systemAudio) == .granted
    }

    /// Screen awareness stands alone; it is useful with no audio at all.
    public var canSeeScreen: Bool {
        state(of: .accessibility) == .granted
    }

    public var isReady: Bool { canListen && canSeeScreen }

    /// The one thing to ask for next, most useful first, so the interface
    /// never presents three prompts at once.
    public var nextToRequest: Permission? {
        for permission in [Permission.microphone, .systemAudio, .accessibility]
        where state(of: permission) != .granted {
            return permission
        }
        return nil
    }

    /// Plain summary for the panel.
    public var summary: String {
        if isReady { return "Ready to listen." }
        let names = missing.map(\.title)
        switch names.count {
        case 0: return "Ready to listen."
        case 1: return "\(names[0]) is needed before Companion can listen."
        case 2: return "\(names[0]) and \(names[1]) are needed before Companion can listen."
        default:
            return "\(names.dropLast().joined(separator: ", ")) and \(names.last!) are needed before Companion can listen."
        }
    }
}
