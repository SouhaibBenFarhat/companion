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
    /// A line somebody finished saying. Fired once, when it settles.
    ///
    /// Separate from `onTranscript`, which fires on every revision: this is the
    /// moment a line is worth keeping.
    var onSpokenLine: ((CaptureSpeaker, String) -> Void)?
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

    /// The file this call is being written to, when the user asked for one.
    private var transcriptFile: TranscriptFile?

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
        startTranscriptFile(if: settings.persistTranscript)
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

        startScreenWatcher()

        for speaker in CaptureSpeaker.allCases {
            guard let engine = makeEngine(for: speaker, settings: settings) else { continue }

            engine.onFinal = { [weak self] text, start in
                guard let self else { return }
                self.transcript.appendFinal(text, speaker: speaker, at: start)
                self.publish()
                self.onSpokenLine?(speaker, text)

                // Written as it settles, not at the end. A transcript that only
                // reaches disk on a clean quit is one you lose on the day
                // something crashes mid-call — the day you wanted it.
                if let file = self.transcriptFile {
                    do {
                        try file.append(speaker: speaker, text: text, at: start)
                    } catch {
                        SessionLog.shared.write("transcript", "could not write: \(error.localizedDescription)")
                        self.transcriptFile = nil
                        self.onError?("Could not save the transcript. Listening continues.")
                    }
                }

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

    /// Opens the file this call will be written to, or leaves it closed.
    private func startTranscriptFile(if wanted: Bool) {
        transcriptFile = nil
        guard wanted else { return }

        let now = Date()
        let directory = TranscriptFile.directory(
            in: StorageLocation.applicationSupportDirectory()
        )
        let file = TranscriptFile(url: directory.appendingPathComponent(TranscriptFile.name(for: now)))
        do {
            try file.begin(at: now)
            transcriptFile = file
            SessionLog.shared.write("transcript", "writing to \(file.url.lastPathComponent)")
        } catch {
            SessionLog.shared.write("transcript", "could not start: \(error.localizedDescription)")
            onError?("Could not save the transcript. Listening continues.")
        }
    }

    /// Where the transcripts are, for the panel to open in Finder.
    var transcriptsDirectory: URL {
        TranscriptFile.directory(in: StorageLocation.applicationSupportDirectory())
    }

    /// Whether the screen stays watched outside of a call.
    ///
    /// Listening always brings the watcher up — the call brain needs it. This
    /// keeps it up between calls too, so typed questions carry the screen. It
    /// is the standing setting, not a session state: `stop()` consults it to
    /// decide whether the watcher goes down with the capture graph.
    var watchScreenAlways = false

    /// Starts or stops the standing watcher, without touching a live call.
    func setWatchingScreen(_ enabled: Bool) {
        watchScreenAlways = enabled
        if enabled {
            startScreenWatcher()
        } else if !isListening {
            stopScreenWatcher()
        }
        // While listening, turning the setting off changes nothing now — the
        // call still needs the screen — and `stop()` honours it afterwards.
    }

    /// Whether the screen is actually being read right now — as opposed to
    /// merely asked for. The difference is the Accessibility grant.
    var isWatchingScreen: Bool { screen?.isRunning == true }

    private func startScreenWatcher() {
        if screen?.isRunning == true { return }
        screen = nil
        let watcher = ScreenAwareness(repository: repository)
        watcher.onContext = { [weak self] context in
            self?.screenContext = context
            self?.onScreen?(context)
        }
        watcher.start()
        // A watcher that never actually started — the Accessibility grant was
        // missing — is not kept. Kept, it pinned the nil-guard above, and
        // every later attempt, including the next call, silently did nothing;
        // dropped, each start is a fresh try, which is what makes granting
        // the permission ever take effect.
        guard watcher.isRunning else { return }
        screen = watcher
    }

    private func stopScreenWatcher() {
        screen?.stop()
        screen = nil
        // Cleared, not kept: a question asked tomorrow must not carry the
        // window that happened to be open when watching was turned off.
        screenContext = nil
    }

    func stop() {
        transcriptFile = nil
        capture.stop()
        if !watchScreenAlways { stopScreenWatcher() }

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
    func admitSuggestion(_ text: String, answersAQuestion: Bool = false) -> Bool {
        let now = Date().timeIntervalSinceReferenceDate
        let decision = gate.admit(
            text, at: now, answersAQuestion: answersAQuestion, state: &gateState
        )
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
