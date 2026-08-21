import Foundation

/// Decides when a device change is worth rebuilding the capture graph for.
///
/// Unplugging headphones does not produce one notification. It produces a burst
/// — default output changed, default input changed, the engine reconfigured —
/// within a few milliseconds of each other. Rebuilding on each one tears down a
/// tap that is still being built, which fails in ways that look random.
public struct CaptureRestartPolicy: Sendable {
    /// How long to wait for the burst to finish.
    public let quietPeriod: TimeInterval
    /// Give up after this many rebuilds in a row, so a device that keeps
    /// changing cannot spin forever.
    public let maximumConsecutiveAttempts: Int

    /// How long after a start to ignore everything.
    ///
    /// Building the capture graph moves audio devices around, and Core Audio
    /// reports that as a device change like any other. Without this the graph
    /// rebuilds because it just started, and then rebuilds because it just
    /// restarted, at about one cycle a second, forever.
    public let settleAfterStart: TimeInterval

    /// Audio has to keep flowing this long before a rebuild counts as having
    /// worked. A trickle between two failures is not a recovery, and treating
    /// it as one is what stopped `giveUp` ever being reached.
    public let successRequires: TimeInterval

    public init(
        quietPeriod: TimeInterval = 0.4,
        maximumConsecutiveAttempts: Int = 5,
        settleAfterStart: TimeInterval = 2,
        successRequires: TimeInterval = 3
    ) {
        self.quietPeriod = quietPeriod
        self.maximumConsecutiveAttempts = maximumConsecutiveAttempts
        self.settleAfterStart = settleAfterStart
        self.successRequires = successRequires
    }

    public struct State: Equatable, Sendable {
        public var lastRequestAt: TimeInterval?
        public var attempts = 0
        /// When the graph last came up, and what the devices looked like then.
        public var startedAt: TimeInterval?
        public var fingerprint: String?

        public init() {}

        public mutating func started(at now: TimeInterval, fingerprint: String) {
            startedAt = now
            self.fingerprint = fingerprint
        }
    }

    public enum Decision: Equatable, Sendable {
        /// Nothing actually moved, or we caused it ourselves. Say why.
        case ignore(String)
        /// Wait — more notifications are probably coming.
        case wait(TimeInterval)
        case rebuild
        /// Something is wrong with the hardware; stop trying.
        case giveUp
    }

    /// - Parameters:
    ///   - now: seconds on any monotonic clock.
    ///   - fingerprint: what the system is using at this moment. Compared with
    ///     what it was using when the graph came up, because Core Audio reports
    ///     changes that move nothing — including the ones this app causes by
    ///     setting up its own capture.
    public func requestRebuild(
        at now: TimeInterval,
        fingerprint: String,
        state: inout State
    ) -> Decision {
        if let startedAt = state.startedAt, now - startedAt < settleAfterStart {
            return .ignore("still starting")
        }
        if let known = state.fingerprint, known == fingerprint {
            return .ignore("same devices")
        }

        defer { state.lastRequestAt = now }

        guard state.attempts < maximumConsecutiveAttempts else { return .giveUp }

        if let last = state.lastRequestAt, now - last < quietPeriod {
            return .wait(quietPeriod - (now - last))
        }
        state.attempts += 1
        return .rebuild
    }

    /// Called while audio is flowing. Only clears the counter once it has been
    /// flowing long enough to mean the graph is actually up.
    public func succeeded(at now: TimeInterval, state: inout State) {
        guard let startedAt = state.startedAt, now - startedAt >= successRequires else { return }
        state.attempts = 0
    }
}
