import Foundation

/// Collects pipe output into whole lines.
///
/// A subprocess pipe hands you arbitrary chunks of bytes, not tidy lines — one
/// read can end halfway through a JSON (a text format for data) object, and the
/// next can carry three objects at once. Decoding a half line throws away a
/// piece of the answer, so chunks are stitched here first.
public struct LineBuffer: Sendable {
    private var partial = ""

    public init() {}

    /// Appends a chunk and returns whatever complete lines that produced.
    /// Anything after the last newline is held back for the next chunk.
    public mutating func append(_ chunk: String) -> [String] {
        partial += chunk
        guard partial.contains("\n") else { return [] }

        var pieces = partial.components(separatedBy: "\n")
        // The final piece has no newline after it yet, so it is incomplete.
        partial = pieces.removeLast()
        return pieces.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Whatever is left when the process exits without a trailing newline.
    public mutating func flush() -> [String] {
        defer { partial = "" }
        let rest = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? [] : [rest]
    }
}
