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
    private var transcribers: [CaptureSpeaker: AnyObject] = [:]
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

    /// The format the transcribers are fed. Fixed, so the converter in each
    /// recorder has one target.
    private let workingFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )

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

        if #available(macOS 26.0, *) {
            for speaker in CaptureSpeaker.allCases {
                let transcriber = Transcriber(speaker: speaker)
                transcriber.onFinal = { [weak self] text, start in
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
                transcriber.onVolatile = { [weak self] text, start in
                    self?.transcript.setVolatile(text, speaker: speaker, at: start)
                    self?.publish()
                }
                transcriber.onError = { [weak self] message in self?.onError?(message) }
                transcribers[speaker] = transcriber

                Task { await transcriber.start() }
            }
        }

        onStateChanged?()
    }

    func stop() {
        capture.stop()
        screen?.stop()
        screen = nil
        screenContext = nil

        if #available(macOS 26.0, *) {
            for case let transcriber as Transcriber in transcribers.values {
                Task { await transcriber.stop() }
            }
        }
        transcribers = [:]
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
        guard #available(macOS 26.0, *),
              let transcriber = transcribers[chunk.speaker] as? Transcriber,
              let format = workingFormat,
              let buffer = Self.makeBuffer(from: chunk, format: format)
        else { return }

        // One clock for both streams. Each analyzer's own timeline starts at
        // zero, so this is what stops an answer appearing before its question.
        let seconds = capture.seconds(for: chunk.hostTimeNanoseconds, speaker: chunk.speaker)
        let startTime = CMTime(seconds: max(0, seconds), preferredTimescale: 1_000)
        transcriber.append(buffer, startTime: startTime)
    }

    private static func makeBuffer(from chunk: PCMChunk, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !chunk.samples.isEmpty,
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
