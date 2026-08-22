import AVFoundation
import CompanionCore
import CoreMedia
import Foundation

/// Ties capture to transcription to the panel.
///
/// Owns the two audio paths, one transcriber per speaker, and the rolling
/// transcript. Everything above this sees text; everything below it sees audio.
final class AwarenessCoordinator {
    private let capture = CallCapture()
    /// One recogniser per speaker. Typed by the protocol, so the downcasts
    /// and the `#available` blocks that used to be needed here are gone.
    private var engines: [CaptureSpeaker: TranscriptionEngine] = [:]
    private(set) var transcript = TranscriptBuffer()
    private var screen: ScreenAwareness?
    private(set) var screenContext: ScreenContext?

    private let trigger = TurnTrigger()
    private let gate = SuggestionGate()
    private var gateState = SuggestionGate.State()
    /// True while the user's own microphone is above the speech threshold.
    private var userIsSpeaking = false
    private var repository: URL = FileManager.default.homeDirectoryForCurrentUser

    /// Fires whenever the transcript changes, so the panel can redraw.
    var onTranscript: ((TranscriptBuffer) -> Void)?
    var onLevels: ((CallCapture.Levels) -> Void)?
    var onError: ((String) -> Void)?
    var onStateChanged: (() -> Void)?
    var onScreen: ((ScreenContext) -> Void)?
    /// Something worth saying happened. The caller decides what to do with it.
    var onTrigger: ((TurnReason, String) -> Void)?

    var isListening: Bool { capture.isRunning }
    var callAppName: String? { capture.callAppName }

    /// When the user turned listening on, so each stream can say how far into
    /// the session it began.
    private var listeningStartedAt = Date.distantPast.timeIntervalSinceReferenceDate

    /// Which recogniser to build. Set from Settings before listening starts.
    var engineKind: TranscriptionEngineKind = .whisper

    init() {
        capture.onError = { [weak self] message in self?.onError?(message) }
        capture.onChunk = { [weak self] chunk in self?.consume(chunk) }
        capture.onLevels = { [weak self] levels in
            // Used to suppress suggestions while the user is mid-sentence.
            self?.userIsSpeaking = levels.me >= SpeechSegmenter().threshold
            self?.onLevels?(levels)
        }
    }

    /// Which microphone to open, passed through to capture.
    var preferredInputUID: String {
        get { capture.preferredInputUID }
        set { capture.preferredInputUID = newValue }
    }

    func updateRepository(_ url: URL) {
        repository = url
        screen?.updateRepository(url)
    }

    // MARK: - Lifecycle

    private(set) var settings = AwarenessSettings()

    func start(settings: AwarenessSettings) {
        listeningStartedAt = Date().timeIntervalSinceReferenceDate
        guard !isListening else { return }
        self.settings = settings
        guard SpeechSupport.isAvailable else {
            // Capture still works and the meters still move; only the words
            // are missing. Say so rather than refusing to start.
            onError?(SpeechSupport.requirement)
            return
        }

        transcript = TranscriptBuffer(windowSeconds: TimeInterval(settings.transcriptWindowSeconds))
        gateState = SuggestionGate.State()
        capture.start(settings: settings)

        let watcher = ScreenAwareness(repository: repository)
        watcher.onContext = { [weak self] context in
            self?.screenContext = context
            self?.onScreen?(context)
        }
        watcher.start()
        screen = watcher

        for speaker in CaptureSpeaker.allCases {
            guard let engine = makeEngine(for: speaker, settings: settings) else { continue }

            engine.onFinal = { [weak self] text, start in
                guard let self else { return }
                self.transcript.appendFinal(text, speaker: speaker, at: start)
                self.publish()

                // No timer. A settled line from the other person is a real
                // event, and it is the only kind worth thinking about.
                if let reason = self.trigger.evaluate(
                    text: text,
                    speaker: speaker,
                    userIsSpeaking: self.userIsSpeaking
                ) {
                    self.onTrigger?(reason, text)
                }
            }
            engine.onVolatile = { [weak self] text, start in
                self?.transcript.setVolatile(text, speaker: speaker, at: start)
                self?.publish()
            }
            engine.onError = { [weak self] message in self?.onError?(message) }

            // Where in the session this stream begins. Apple's engine counts
            // from zero for each one, so without this the second speaker's
            // first word sorts against the first speaker's first.
            engine.sessionOffset = max(0, Date().timeIntervalSinceReferenceDate - listeningStartedAt)

            engines[speaker] = engine
            Task { await engine.start() }
        }

        onStateChanged?()
    }

    func stop() {
        capture.stop()
        screen?.stop()
        screen = nil
        screenContext = nil

        for engine in engines.values {
            Task { await engine.stop() }
        }
        engines = [:]
        onStateChanged?()
        publish()
    }

    /// Whether an unprompted suggestion is worth showing right now.
    ///
    /// The trigger decided something happened. This decides whether saying so
    /// is worth interrupting a live conversation for, which is the harder
    /// question and the one that decides whether the feature survives.
    func admitSuggestion(_ text: String) -> Bool {
        let now = Date().timeIntervalSinceReferenceDate
        let decision = gate.admit(text, at: now, state: &gateState)
        if decision != .show {
            SessionLog.shared.write("suggest", "held back: \(decision)")
        }
        return decision == .show
    }

    /// Marks the transcript as read, so the next question carries only what
    /// has been said since.
    func markTranscriptSent() {
        transcript.markSent()
    }

    /// Clears the record without stopping. Used when a new conversation starts.
    func clearTranscript() {
        transcript.clear()
        publish()
    }

    // MARK: - Audio in, text out

    private func consume(_ chunk: PCMChunk) {
        guard let engine = engines[chunk.speaker] else { return }
        // The one clock both streams share. Whisper needs it because it is
        // handed detached blocks with no timeline of their own; Apple's engine
        // ignores it and counts frames instead.
        engine.append(chunk, at: capture.seconds(for: chunk.hostTimeNanoseconds, speaker: chunk.speaker))
    }

    /// Builds the recogniser the user picked, or nothing when this Mac cannot
    /// run it.
    private func makeEngine(
        for speaker: CaptureSpeaker,
        settings: AwarenessSettings
    ) -> TranscriptionEngine? {
        switch engineKind {
        case .whisper:
            return WhisperEngine(
                speaker: speaker,
                variant: .largeTurbo,
                // Empty for now. The words a call is full of are known — this
                // is where they go, worst-first, because Whisper keeps the tail
                // of the prompt and only 111 tokens of it.
                vocabulary: []
            )
        case .apple:
            guard #available(macOS 26.0, *) else {
                if let why = TranscriptionEngineKind.apple.unmetRequirement { onError?(why) }
                return nil
            }
            return Transcriber(speaker: speaker)
        }
    }

    /// Wraps a chunk in a buffer that says what it actually is.
    ///
    /// Built from the chunk's own sample rate, not from a format decided
    /// elsewhere. It used to be built in a fixed 16 kHz mono format while the
    /// system tap delivers 48 kHz, so every block of call audio was handed over
    /// claiming to be three times longer than it was — and the transcriber's
    /// converter, told the input was already 16 kHz, had nothing to correct.
    private static func makeBuffer(from chunk: PCMChunk) -> AVAudioPCMBuffer? {
        guard !chunk.samples.isEmpty,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: chunk.sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(chunk.samples.count)
              ),
              let channel = buffer.floatChannelData?[0]
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(chunk.samples.count)
        chunk.samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: source.count)
        }
        return buffer
    }

    private func publish() {
        onTranscript?(transcript)
    }
}
