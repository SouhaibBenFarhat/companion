import Foundation

/// A microphone you can choose.
public struct AudioInputDevice: Equatable, Identifiable, Sendable {
    /// The unique identifier macOS gives the device. Stable across unplugging
    /// and reconnecting, unlike the numeric id, which is not.
    public let uid: String
    public let name: String
    /// Whether macOS currently considers this the system input.
    public let isSystemDefault: Bool

    public var id: String { uid }

    public init(uid: String, name: String, isSystemDefault: Bool = false) {
        self.uid = uid
        self.name = name
        self.isSystemDefault = isSystemDefault
    }
}

/// Which microphone to record.
///
/// "Whatever macOS has as the default" is the wrong answer on a machine with
/// several. Continuity can hand a Mac the iPhone microphone without warning,
/// and a call app picks its own input regardless of the system setting — so
/// Companion can end up transcribing a different room from the one in the call.
public enum AudioInputSelection {
    /// The device to open, given what the user chose and what exists now.
    ///
    /// A chosen device that is currently unplugged falls back to the system
    /// default rather than failing: no microphone at all is worse than the
    /// wrong one, and the choice is remembered for when it comes back.
    public static func resolve(
        preferredUID: String,
        available: [AudioInputDevice]
    ) -> AudioInputDevice? {
        guard !available.isEmpty else { return nil }

        if !preferredUID.isEmpty,
           let chosen = available.first(where: { $0.uid == preferredUID }) {
            return chosen
        }
        return available.first(where: \.isSystemDefault) ?? available.first
    }

    /// Whether the chosen device is missing right now, so the interface can say
    /// so instead of silently recording something else.
    public static func isPreferredMissing(
        preferredUID: String,
        available: [AudioInputDevice]
    ) -> Bool {
        guard !preferredUID.isEmpty else { return false }
        return !available.contains { $0.uid == preferredUID }
    }
}
