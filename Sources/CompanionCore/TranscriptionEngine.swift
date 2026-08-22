import Foundation

/// One audio stream in, labelled text out.
///
/// The seam between Companion and whatever does the recognising. Everything
/// above it — the transcript, the panel, the agent prompt — already reads
/// (text, seconds-since-listening-began) pairs, so an engine has only to
/// produce those.
///
/// Not version-gated. `Transcriber` is `@available(macOS 26.0, *)` because
/// `SpeechAnalyzer` is; that belongs on the conformance. Gating the protocol
/// would mean a WhisperKit engine that runs on macOS 14 could never be reached
/// from the same call site.
///
/// Not `@MainActor` either, deliberately. Everything here is already called
/// from the main queue — `CallCapture.deliver` hops there before calling
/// `onChunk` — but the package builds in Swift 5 language mode, where adding
/// `@MainActor` to `Transcriber` would move the body of its `async` methods
/// onto the main actor. That is a real behaviour change to the one file that
/// has just cost six failed attempts. Add the annotation when Companion moves
/// to Swift 6 and the compiler can check it.
public protocol TranscriptionEngine: AnyObject {
    /// Which side of the call this instance listens to. Set once, at init.
    var speaker: CaptureSpeaker { get }

    /// How far into the listening session this stream began, in seconds.
    ///
    /// Only the Apple engine uses it: `SpeechAnalyzer` reports times from its
    /// own zero, so Companion adds this. The Whisper engine takes the session
    /// time from `append(_:at:)` instead, which is measured rather than
    /// assumed.
    var sessionOffset: TimeInterval { get set }

    /// Settled text, and where it started in session seconds.
    var onFinal: ((String, TimeInterval) -> Void)? { get set }

    /// The tail still being revised. Replaced wholesale, never appended.
    /// An engine with no live preview simply never calls this.
    var onVolatile: ((String, TimeInterval) -> Void)? { get set }

    var onError: ((String) -> Void)? { get set }

    func start(locale: Locale) async
    func stop() async

    /// Audio in, in whatever the capture path produced. The engine converts;
    /// the caller does not know or care what the engine wants.
    ///
    /// - Parameter sessionSeconds: where this chunk sits on the one clock both
    ///   streams share — `CallCapture.seconds(for:speaker:)`, derived from the
    ///   chunk's own mach host time. Whisper needs it because it is handed
    ///   detached blocks of audio and has no timeline of its own. The Apple
    ///   engine ignores it: `SpeechAnalyzer` keeps its own position by counting
    ///   frames, and handing it a wall-clock time is exactly the bug that took
    ///   six attempts to remove.
    ///
    /// Synchronous and non-throwing on purpose: called from the capture pump
    /// ten times a second, and it must never make the caller wait.
    func append(_ chunk: PCMChunk, at sessionSeconds: TimeInterval)
}

public extension TranscriptionEngine {
    func start() async { await start(locale: .current) }
}

/// Which recogniser turns audio into text.
///
/// Shaped after `AgentKind`: raw-value string, Codable, CaseIterable for the
/// picker, and a `title` for display.
public enum TranscriptionEngineKind: String, Codable, CaseIterable, Sendable {
    /// Apple's `SpeechAnalyzer`. Needs macOS 26.
    case apple
    /// WhisperKit, running a Core ML model from disk.
    case whisper

    public var title: String {
        switch self {
        case .apple: return "Apple Speech"
        case .whisper: return "Whisper"
        }
    }

    /// Why this Mac cannot run it, or nil when it can.
    ///
    /// Replaces `SpeechSupport.isAvailable`, which asks about the OS when the
    /// question is now about the engine — and whose message ("needs macOS 26")
    /// is simply false once Whisper is an option.
    public var unmetRequirement: String? {
        switch self {
        case .apple:
            if #available(macOS 26.0, *) { return nil }
            return "Apple's live transcription needs macOS 26 or later."
        case .whisper:
            return nil
        }
    }
}
