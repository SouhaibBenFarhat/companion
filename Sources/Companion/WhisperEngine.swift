import AVFoundation
import CompanionCore
import Foundation
import WhisperKit

/// Turns one audio stream into text, on this Mac, with WhisperKit.
///
/// Same shape as `Transcriber`: one instance per speaker, start/stop/append,
/// onFinal/onVolatile/onError. The difference is underneath. `SpeechAnalyzer`
/// is a streaming recogniser that decides its own boundaries; Whisper is not,
/// so this holds the audio, decides where each utterance ends, and asks for a
/// decode. `TranscriptionWindower` is the part that decides.
///
/// Lives on the main queue, like everything else the coordinator touches. The
/// model itself lives in `WhisperPipeline`, an actor, because a decode takes
/// about a second and the panel must not wait for it.
final class WhisperEngine: TranscriptionEngine {
    let speaker: CaptureSpeaker

    /// Unused here. Whisper takes its times from `append(_:at:)`, which is
    /// derived from the mach host time of the audio itself rather than from a
    /// wall clock read at start-up.
    var sessionOffset: TimeInterval = 0

    var onFinal: ((String, TimeInterval) -> Void)?
    var onVolatile: ((String, TimeInterval) -> Void)?
    var onError: ((String) -> Void)?

    private let variant: WhisperModelStore.Variant
    private let vocabulary: [String]
    private let pipeline = WhisperPipeline()
    private let windower: TranscriptionWindower
    private var windowState = TranscriptionWindower.State()

    /// True once the model is loaded. Audio arriving before then is still
    /// windowed and still decoded when it lands — the first download takes
    /// minutes, and dropping the opening sentence of a call is worse than a
    /// late one.
    private var isLoaded = false
    /// One preview decode at a time. A second queued behind the first is stale
    /// before it starts.
    private var previewInFlight = false
    /// The last preview, to compare the next one against.
    private var lastPreview = ""

    /// Whisper wants 16 kHz mono Float32. `WhisperKit.sampleRate` is 16000, and
    /// `transcribe(audioArray:)` is documented "Array of 16khz raw float audio
    /// samples".
    private static let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(WhisperKit.sampleRate),
        channels: 1,
        interleaved: false
    )!

    private var converter: AVAudioConverter?
    private var converterSource: AVAudioFormat?

    init(
        speaker: CaptureSpeaker,
        variant: WhisperModelStore.Variant,
        vocabulary: [String]
    ) {
        self.speaker = speaker
        self.variant = variant
        self.vocabulary = vocabulary
        self.windower = TranscriptionWindower(speaker: speaker)
    }

    // MARK: - Lifecycle

    func start(locale: Locale) async {
        let language = locale.language.languageCode?.identifier ?? "en"
        do {
            let folder = try await WhisperModelStore.shared.folder(for: variant)
            try await pipeline.load(folder: folder, language: language)
            await pipeline.setVocabulary(vocabulary)
            let tokens = await pipeline.vocabularyTokenCount
            await MainActor.run { self.isLoaded = true }
            SessionLog.shared.write(
                "whisper",
                "\(speaker) ready: \(variant.rawValue), \(language), \(tokens) vocabulary tokens"
            )
        } catch {
            // `WhisperModelStore` has already published the reason as a phase,
            // and the panel is showing it. Saying it twice reads as two faults.
            SessionLog.shared.write("whisper", "\(speaker) could not start: \(error.localizedDescription)")
        }
    }

    func stop() async {
        // Whatever was being said when the user pressed stop is usually the
        // part they wanted.
        let pending = await MainActor.run { () -> TranscriptionWindow? in
            let open = self.isLoaded ? self.windower.flush(&self.windowState) : nil
            self.isLoaded = false
            self.previewInFlight = false
            self.converter = nil
            self.converterSource = nil
            return open
        }
        if let pending, let text = try? await pipeline.decode(pending.samples),
           !TranscriptionNoise.isFiller(text) {
            await MainActor.run { self.onFinal?(text, pending.startSeconds) }
        }
        await MainActor.run { self.windowState = TranscriptionWindower.State() }
        await pipeline.unload()
    }

    /// Replaces the vocabulary without restarting.
    ///
    /// The words worth biasing towards are the identifiers of the repository
    /// being paired on, and that can change mid-session —
    /// `AwarenessCoordinator.updateRepository` already exists for it.
    func updateVocabulary(_ terms: [String]) {
        Task { [pipeline] in await pipeline.setVocabulary(terms) }
    }

    // MARK: - Audio in

    func append(_ chunk: PCMChunk, at sessionSeconds: TimeInterval) {
        guard let samples = resample(chunk) else { return }

        if let window = windower.consume(
            samples: samples,
            level: chunk.level,
            at: sessionSeconds,
            state: &windowState
        ) {
            decode(window)
            return
        }

        guard !previewInFlight, let preview = windower.preview(&windowState) else { return }
        previewInFlight = true
        decode(preview)
    }

    /// Into 16 kHz mono, reusing one converter across buffers.
    ///
    /// The microphone path already produces exactly this — `MicrophoneRecorder`
    /// is built with a 16 kHz mono Float32 target — so `.me` costs nothing
    /// here. Only the process tap, at the output device's own rate, converts.
    ///
    /// The buffer is built from the chunk's own sample rate, never from a
    /// format decided elsewhere. Building it at a fixed 16 kHz while the tap
    /// delivers 48 kHz is a bug this project has already paid for once.
    private func resample(_ chunk: PCMChunk) -> [Float]? {
        guard !chunk.samples.isEmpty else { return nil }
        if chunk.sampleRate == Self.whisperFormat.sampleRate { return chunk.samples }

        guard let source = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: chunk.sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        if converter == nil || converterSource != source {
            converter = AVAudioConverter(from: source, to: Self.whisperFormat)
            converterSource = source
        }
        guard let converter,
              let input = AVAudioPCMBuffer(
                  pcmFormat: source,
                  frameCapacity: AVAudioFrameCount(chunk.samples.count)
              ),
              let channel = input.floatChannelData?[0]
        else { return nil }

        input.frameLength = AVAudioFrameCount(chunk.samples.count)
        chunk.samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            channel.update(from: base, count: buffer.count)
        }

        guard let output = try? AudioProcessor.resampleBuffer(input, with: converter) else { return nil }
        return AudioProcessor.convertBufferToArray(buffer: output)
    }

    // MARK: - Text out

    /// Decodes off the main queue and reports back on it.
    private func decode(_ window: TranscriptionWindow) {
        guard isLoaded else {
            previewInFlight = false
            return
        }
        // `self` is captured strongly on purpose: the task is short, and a
        // window that has been cut out of the audio should still reach the
        // transcript even if the coordinator is tearing the engine down.
        Task { [pipeline] in
            do {
                let text = try await pipeline.decode(window.samples)
                await self.report(text: text, for: window)
            } catch {
                let message = error.localizedDescription
                SessionLog.shared.write("whisper", "decode failed: \(message)")
                await self.report(failure: message, for: window)
            }
        }
    }

    @MainActor
    private func report(text: String, for window: TranscriptionWindow) {
        if !window.isClosed { previewInFlight = false }

        guard !TranscriptionNoise.isRepetitionLoop(text) else {
            // Thrown away rather than shown. A loop is not a mishearing that a
            // reader can discount; it reads as something the other person
            // actually said, at length.
            SessionLog.shared.write("whisper", "\(speaker) dropped a repetition loop (\(text.count) chars)")
            if window.isClosed { onVolatile?("", window.startSeconds) }
            return
        }

        guard !TranscriptionNoise.isFiller(text) else {
            // Silence comes back as "Thank you." and a short noise as ".".
            // Both are non-empty, so `TranscriptBuffer.appendFinal`'s empty
            // check lets them through, they count as a settled line, and they
            // can trip the suggestion trigger into interrupting a call about
            // nothing. Clearing the tail as well removes a preview that is
            // about to have no final to replace it.
            // Only on a closed window. Clearing the preview on an open one
            // deletes a line the reader is part-way through, and the next pass
            // brings it straight back — which is the flicker.
            if window.isClosed { onVolatile?("", window.startSeconds) }
            return
        }

        if window.isClosed {
            lastPreview = ""

            // One line per sentence, not one per window.
            //
            // A window is up to fifteen seconds, and everything in it arrives
            // as a single string. Shown whole it lands in the panel as a wall
            // of text with the next wall on top of it, which is not how the
            // conversation happened. Cut into sentences, each is its own line
            // at its own moment.
            let sentences = SentenceSplitter.split(text)
            let times = SentenceSplitter.times(
                for: sentences,
                from: window.startSeconds,
                over: window.duration
            )
            for (sentence, at) in zip(sentences, times) {
                onFinal?(sentence, at)
            }
            return
        }

        // Only the words this pass and the last one agree on.
        //
        // Whisper re-decodes a growing window, so each preview can rewrite the
        // whole line. Shown whole, the panel rewrites itself several times a
        // second and text that was on screen a moment ago disappears. Shown as
        // the agreed prefix, the line only ever grows.
        let agreed = AgreedPrefix.of(lastPreview, text)
        lastPreview = text
        guard !agreed.isEmpty else { return }
        onVolatile?(agreed, window.startSeconds)
    }

    @MainActor
    private func report(failure message: String, for window: TranscriptionWindow) {
        if !window.isClosed { previewInFlight = false }
        onError?("Transcription failed: \(message)")
    }
}
