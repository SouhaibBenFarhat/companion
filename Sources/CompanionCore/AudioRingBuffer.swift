import Foundation

/// Fixed-size storage between the audio thread and everything else.
///
/// The audio callback runs under a hard deadline shared with whatever else is
/// playing. Allocating memory, taking a lock or logging inside it does not just
/// glitch our recording — it glitches the user's call. So the callback does the
/// least possible: copy floats in, move an index, return.
///
/// Storage is allocated once at init and never grows. When the reader falls
/// behind, the oldest audio is dropped rather than the newest: a late listener
/// wants what is being said now, not what was said a second ago.
public final class AudioRingBuffer: @unchecked Sendable {
    private var storage: [Float]
    private let capacity: Int
    private var writeIndex = 0
    private var available = 0
    private let lock = NSLock()

    /// - Parameter capacity: in frames. A few hundred milliseconds is plenty;
    ///   more only adds latency between a word and its transcript.
    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage = [Float](repeating: 0, count: self.capacity)
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return available
    }

    public var isEmpty: Bool { count == 0 }

    /// How many frames have been thrown away because nobody read in time.
    /// Worth surfacing: a rising number means the consumer is too slow.
    public private(set) var droppedFrames: Int = 0

    /// Appends samples, dropping the oldest if there is not enough room.
    ///
    /// The lock here is uncontended in practice — the reader holds it for a
    /// memcpy — but a real audio thread should use atomics. Kept simple until
    /// a device shows it matters, and noted so the trade is visible.
    public func write(_ samples: UnsafeBufferPointer<Float>) {
        guard !samples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        // Anything beyond capacity would overwrite itself within this call.
        let incoming = samples.suffix(capacity)
        let dropped = samples.count - incoming.count

        for sample in incoming {
            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            if available < capacity {
                available += 1
            } else {
                droppedFrames += 1
            }
        }
        droppedFrames += dropped
    }

    public func write(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { write($0) }
    }

    /// Takes up to `maximum` frames, oldest first.
    public func read(maximum: Int = .max) -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        let count = min(maximum, available)
        guard count > 0 else { return [] }

        var output = [Float](repeating: 0, count: count)
        let start = (writeIndex - available + capacity * 2) % capacity
        for offset in 0..<count {
            output[offset] = storage[(start + offset) % capacity]
        }
        available -= count
        return output
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        available = 0
        droppedFrames = 0
    }
}
