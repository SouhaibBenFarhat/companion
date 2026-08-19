import Foundation

/// Collapses a storm of change notifications into a settled answer.
///
/// The accessibility API reports every keystroke as a value change. Acting on
/// each one would mean reading the screen hundreds of times a minute, and every
/// read is a synchronous message to another process. Waiting for a pause is
/// both cheaper and more accurate — what the user is looking at is only
/// meaningful once they have stopped moving.
public struct ContextDebouncer: Sendable {
    /// How long the screen must be still before it counts as settled.
    public let quietPeriod: TimeInterval
    /// Report at least this often even while the user keeps typing, so a long
    /// stretch of work is not invisible.
    public let maximumSilence: TimeInterval

    public init(quietPeriod: TimeInterval = 0.6, maximumSilence: TimeInterval = 8) {
        self.quietPeriod = quietPeriod
        self.maximumSilence = maximumSilence
    }

    public struct State: Equatable, Sendable {
        public var lastChangeAt: TimeInterval?
        public var lastReportAt: TimeInterval?

        public init() {}
    }

    public enum Decision: Equatable, Sendable {
        case wait(TimeInterval)
        case report
    }

    public func changed(at now: TimeInterval, state: inout State) -> Decision {
        defer { state.lastChangeAt = now }

        // Long enough since the last report that the user deserves an update
        // even though they are still going.
        if let lastReport = state.lastReportAt, now - lastReport >= maximumSilence {
            state.lastReportAt = now
            return .report
        }

        guard let lastChange = state.lastChangeAt else {
            // The first change after quiet is worth reporting immediately —
            // switching apps should not feel delayed.
            state.lastReportAt = now
            return .report
        }

        let sinceChange = now - lastChange
        guard sinceChange >= quietPeriod else { return .wait(quietPeriod - sinceChange) }

        state.lastReportAt = now
        return .report
    }
}
