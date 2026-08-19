import CompanionCore
import Foundation

/// Whether on-device transcription is available at all.
///
/// A separate, ungated type on purpose. Putting `isSupported` on a type marked
/// `@available(macOS 26.0, *)` cannot compile — the check itself would need the
/// version it is checking for.
enum SpeechSupport {
    /// `SpeechAnalyzer` arrived in macOS 26. Nothing before it can transcribe
    /// two continuous streams on device without a duration cap.
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    static let requirement = "Live transcription needs macOS 26 or later."
}
