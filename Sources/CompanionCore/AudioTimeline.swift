import Foundation

/// Puts the two streams on one clock.
///
/// The microphone and the system tap are different devices with unrelated
/// clocks, and each reports its own host time. Without a shared origin the
/// transcript can show an answer before the question.
public struct AudioTimeline: Sendable {
    /// Host time of the moment listening started, in mach ticks.
    public let originHostTime: UInt64
    /// How long a tick is on this machine. Not a constant, and not one
    /// nanosecond — see `HostClock`.
    public let clock: HostClock
    /// Per-stream correction, in seconds.
    ///
    /// Not guesswork: the microphone path reports `presentationLatency`, and a
    /// tap has its own. Defaults to zero, and only a device test can fill it in.
    public var offsets: [CaptureSpeaker: TimeInterval]

    public init(
        originHostTime: UInt64,
        clock: HostClock = .nanoseconds,
        offsets: [CaptureSpeaker: TimeInterval] = [:]
    ) {
        self.originHostTime = originHostTime
        self.clock = clock
        self.offsets = offsets
    }

    /// Host time to seconds since listening began.
    public func seconds(for hostTime: UInt64, speaker: CaptureSpeaker) -> TimeInterval {
        // Unsigned, so a timestamp from before the origin must not wrap into a
        // number near 18 billion.
        let elapsed: TimeInterval
        if hostTime >= originHostTime {
            elapsed = clock.seconds(fromTicks: hostTime - originHostTime)
        } else {
            elapsed = -clock.seconds(fromTicks: originHostTime - hostTime)
        }
        return elapsed + (offsets[speaker] ?? 0)
    }

    /// Merges two labelled lists into the order things were actually said.
    ///
    /// Ties go to `them`: when both start at the same instant it is almost
    /// always the other person still talking while the user starts, and reading
    /// their line first matches what happened.
    public static func merge(_ lists: [SpeechSegment]...) -> [SpeechSegment] {
        lists.flatMap { $0 }.sorted { left, right in
            if left.startSeconds != right.startSeconds {
                return left.startSeconds < right.startSeconds
            }
            if left.speaker != right.speaker {
                return left.speaker == .them
            }
            return left.endSeconds < right.endSeconds
        }
    }
}
