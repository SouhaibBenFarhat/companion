import AVFoundation
import CompanionCore
import Foundation
import Speech

/// Turns one audio stream into text, on this Mac.
///
/// One instance per speaker. Nothing is uploaded, there is no per-minute cost,
/// and no duration cap — which is why this is `SpeechAnalyzer` rather than the
/// older recogniser, whose server route restarts every minute and cannot
/// promise on-device.
@available(macOS 26.0, *)
final class Transcriber {
    let speaker: CaptureSpeaker

    /// Settled text, with the moment it started.
    var onFinal: ((String, TimeInterval) -> Void)?
    /// The tail still being revised. Replaced, never appended.
    var onVolatile: ((String, TimeInterval) -> Void)?
    var onError: ((String) -> Void)?

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputStream: AsyncStream<AnalyzerInput>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var reservedLocale: Locale?

    /// The last timestamp handed over, so the next one can never precede it.
    private var lastStartTime: CMTime?
    private var nudged = 0

    /// The format the analyzer asked for.
    ///
    /// Asked, never assumed. Feeding it a format of our own choosing traps
    /// inside the framework — `SpeechRecognizerWorker.preRunRecognition` dies
    /// with `EXC_BREAKPOINT`, taking the app with it, and the crash report
    /// points at Apple's code rather than ours.
    private var requiredFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterSource: AVAudioFormat?

    init(speaker: CaptureSpeaker) {
        self.speaker = speaker
    }

    deinit {
        inputContinuation?.finish()
        resultsTask?.cancel()
    }

    // MARK: - Lifecycle

    func start(locale: Locale = Locale.current) async {
        await stop()

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber

        do {
            try await prepareModel(for: transcriber, locale: locale)
        } catch {
            await report("Could not prepare the speech model: \(error.localizedDescription)")
            await stop()
            return
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // Ask what it wants, then promise to send exactly that.
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            await report("This Mac offers no audio format the transcriber accepts.")
            await stop()
            return
        }
        requiredFormat = format

        do {
            try await analyzer.prepareToAnalyze(in: format)
        } catch {
            await report("Could not prepare transcription: \(error.localizedDescription)")
            await stop()
            return
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputStream = stream
        inputContinuation = continuation

        // Results arrive as an async sequence for the life of the session.
        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { return }
                    self.handle(result)
                }
            } catch {
                guard !Task.isCancelled else { return }
                // Logged as well as shown. This is the one failure that ends
                // transcription for the rest of the call, and it was reaching
                // the panel without leaving a trace anywhere to diagnose from.
                SessionLog.shared.write(
                    "transcribe",
                    "\(self.speaker) stream failed: \(error.localizedDescription)"
                )
                await MainActor.run { self.onError?(error.localizedDescription) }
            }
        }

        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            await report("Could not start transcription: \(error.localizedDescription)")
            // Leaving the half-built session in place would hold a reserved
            // locale and a live results task that nothing can ever finish.
            await stop()
        }
    }

    func stop() async {
        // A fresh analyzer starts a fresh clock.
        lastStartTime = nil
        nudged = 0
        inputContinuation?.finish()
        inputContinuation = nil
        inputStream = nil

        // Finalize only here. Forcing a boundary during the session strips the
        // context the recogniser uses to correct itself, which is the same
        // fault that makes the older API worse.
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil
        transcriber = nil
        requiredFormat = nil
        converter = nil
        converterSource = nil

        resultsTask?.cancel()
        resultsTask = nil

        if let reservedLocale {
            await AssetInventory.release(reservedLocale: reservedLocale)
            self.reservedLocale = nil
        }
    }

    /// Feeds audio in, converted to whatever the analyzer asked for.
    ///
    /// `startTime` is what puts the two streams on one clock — each analyzer's
    /// own timeline starts at zero, so without it the transcript can show an
    /// answer before the question.
    func append(_ buffer: AVAudioPCMBuffer, startTime: CMTime) {
        guard let continuation = inputContinuation, let required = requiredFormat else { return }
        guard let converted = convert(buffer, to: required) else { return }

        // Never backwards. `SpeechAnalyzer` rejects the whole input sequence
        // with "Audio input timestamp overlaps or precedes prior audio input"
        // and stops transcribing, so one bad timestamp costs the rest of the
        // call. The clock is fixed upstream; this is here because a stream the
        // user cannot restart is too expensive to lose to an arithmetic edge —
        // a device waking up, a latency figure that changed mid-run.
        // Never before zero either. The hardware latency is subtracted from
        // the capture time, so the first buffers of a session land just before
        // the origin — and the analyzer reads a negative start as preceding
        // input it has already taken, which is the same rejection.
        var start = startTime
        if start < .zero { start = .zero }

        if let last = lastStartTime, start <= last {
            start = CMTimeAdd(last, CMTime(value: 1, timescale: start.timescale))
            nudged += 1
            if nudged == 1 || nudged % 200 == 0 {
                SessionLog.shared.write("transcribe", "\(speaker) timestamp nudged forward (\(nudged))")
            }
        }
        lastStartTime = start

        continuation.yield(AnalyzerInput(buffer: converted, bufferStartTime: start))
    }

    /// Converts into the analyzer's format, reusing the converter across
    /// buffers. Building one per buffer would allocate on every chunk of audio.
    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }

        if converter == nil || converterSource != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converterSource = buffer.format
        }
        guard let converter else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    // MARK: - Model assets

    private func report(_ message: String) async {
        await MainActor.run { self.onError?(message) }
    }

    /// Reserving comes first. Without it the status never reaches installed and
    /// the model is downloaded again on every launch.
    private func prepareModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        // Matching full identifiers fails for most people: Locale.current
        // carries the region, so a British user in Germany is "en-DE", which is
        // in nobody's supported list even though English is supported.
        let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        guard let resolved else { throw TranscriberError.localeUnsupported(locale.identifier) }

        try await AssetInventory.reserve(locale: resolved)
        reservedLocale = resolved

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    enum TranscriberError: LocalizedError {
        case localeUnsupported(String)

        var errorDescription: String? {
            switch self {
            case .localeUnsupported(let identifier):
                return "On-device transcription does not support \(identifier)."
            }
        }
    }

    // MARK: - Results

    private func handle(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let start = result.range.start.seconds

        Task { @MainActor [weak self] in
            guard let self else { return }
            if result.isFinal {
                self.onFinal?(text, start)
            } else {
                self.onVolatile?(text, start)
            }
        }
    }
}
