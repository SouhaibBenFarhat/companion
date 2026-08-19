import Foundation

/// What Companion is allowed to notice, and how much it keeps.
///
/// One nested value rather than eight more fields on `Settings`, which already
/// carries eleven. Every field decodes with a default, so a settings file
/// written before this existed still loads.
public struct AwarenessSettings: Codable, Equatable, Sendable {
    /// The master switch. Off means no capture at all, whatever else says.
    public var enabled: Bool
    public var captureMicrophone: Bool
    public var captureSystemAudio: Bool
    /// Suppress the other person's voice leaking back through the microphone.
    public var echoCancellationEnabled: Bool
    /// How much conversation to keep in memory.
    public var transcriptWindowSeconds: Int
    /// Whether the transcript survives quitting.
    ///
    /// Off by default and deliberately so: a transcript of a work call is
    /// someone else's words, and the safest place for it is nowhere.
    public var persistTranscript: Bool

    public init(
        enabled: Bool = false,
        captureMicrophone: Bool = true,
        captureSystemAudio: Bool = true,
        echoCancellationEnabled: Bool = true,
        transcriptWindowSeconds: Int = 300,
        persistTranscript: Bool = false
    ) {
        self.enabled = enabled
        self.captureMicrophone = captureMicrophone
        self.captureSystemAudio = captureSystemAudio
        self.echoCancellationEnabled = echoCancellationEnabled
        self.transcriptWindowSeconds = transcriptWindowSeconds
        self.persistTranscript = persistTranscript
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AwarenessSettings()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        captureMicrophone = try container.decodeIfPresent(Bool.self, forKey: .captureMicrophone)
            ?? defaults.captureMicrophone
        captureSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .captureSystemAudio)
            ?? defaults.captureSystemAudio
        echoCancellationEnabled = try container.decodeIfPresent(Bool.self, forKey: .echoCancellationEnabled)
            ?? defaults.echoCancellationEnabled
        transcriptWindowSeconds = try container.decodeIfPresent(Int.self, forKey: .transcriptWindowSeconds)
            ?? defaults.transcriptWindowSeconds
        persistTranscript = try container.decodeIfPresent(Bool.self, forKey: .persistTranscript)
            ?? defaults.persistTranscript
    }

    /// Listening to one side only produces a transcript of somebody talking to
    /// themselves, which reads worse than no transcript at all.
    public var capturesBothSides: Bool { captureMicrophone && captureSystemAudio }
}
