import Foundation

/// Converts mach host time into seconds.
///
/// Host time is a tick count, not nanoseconds, and the tick length is a
/// property of the machine. On Apple Silicon it is 125/3 nanoseconds — about
/// 41.67 — so treating ticks as nanoseconds makes every duration roughly 41
/// times too small. A two second gap between speakers becomes 48 milliseconds,
/// which silently destroys the ordering of a two-speaker transcript.
public struct HostClock: Equatable, Sendable {
    /// Nanoseconds per tick, as the numerator and denominator the kernel gives.
    public let numerator: UInt32
    public let denominator: UInt32

    public init(numerator: UInt32, denominator: UInt32) {
        // A zero denominator would divide by zero on every sample; a zero
        // numerator would make time stand still.
        self.numerator = max(1, numerator)
        self.denominator = max(1, denominator)
    }

    /// Ticks to seconds.
    public func seconds(fromTicks ticks: UInt64) -> TimeInterval {
        TimeInterval(ticks) * TimeInterval(numerator) / TimeInterval(denominator) / 1_000_000_000
    }

    /// Seconds to ticks, for subtracting a hardware latency from a timestamp.
    public func ticks(fromSeconds seconds: TimeInterval) -> UInt64 {
        guard seconds > 0 else { return 0 }
        let nanoseconds = seconds * 1_000_000_000
        return UInt64(nanoseconds * TimeInterval(denominator) / TimeInterval(numerator))
    }

    /// This machine's timebase, read once.
    ///
    /// `mach_timebase_info` never changes while the system is running, so
    /// asking for it on every audio buffer would be waste.
    public static let current: HostClock = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS else { return .nanoseconds }
        return HostClock(numerator: info.numer, denominator: info.denom)
    }()

    /// The 1:1 clock, where a tick already is a nanosecond. Only correct on a
    /// machine whose timebase really is 1/1 — used as a test fixture, never
    /// assumed at runtime.
    public static let nanoseconds = HostClock(numerator: 1, denominator: 1)
}
