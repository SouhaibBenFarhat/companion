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

    public init(quietPeriod: TimeInterval = 0.4, maximumConsecutiveAttempts: Int = 5) {
        self.quietPeriod = quietPeriod
        self.maximumConsecutiveAttempts = maximumConsecutiveAttempts
    }

    public struct State: Equatable, Sendable {
        public var lastRequestAt: TimeInterval?
        public var attempts = 0

        public init() {}
    }

    public enum Decision: Equatable, Sendable {
        /// Wait — more notifications are probably coming.
        case wait(TimeInterval)
        case rebuild
        /// Something is wrong with the hardware; stop trying.
        case giveUp
    }

    /// - Parameter now: seconds on any monotonic clock.
    public func requestRebuild(at now: TimeInterval, state: inout State) -> Decision {
        defer { state.lastRequestAt = now }

        guard state.attempts < maximumConsecutiveAttempts else { return .giveUp }

        if let last = state.lastRequestAt, now - last < quietPeriod {
            return .wait(quietPeriod - (now - last))
        }
        state.attempts += 1
        return .rebuild
    }

    /// Called once audio is flowing again.
    public func succeeded(state: inout State) {
        state.attempts = 0
    }
}
