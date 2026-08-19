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
            onError?("Could not prepare the speech model: \(error.localizedDescription)")
            return
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

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
                await MainActor.run { self.onError?(error.localizedDescription) }
            }
        }

        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            onError?("Could not start transcription: \(error.localizedDescription)")
        }
    }

    func stop() async {
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

        resultsTask?.cancel()
        resultsTask = nil

        if let reservedLocale {
            await AssetInventory.release(reservedLocale: reservedLocale)
            self.reservedLocale = nil
        }
    }

    /// Feeds audio in. `startTime` is what puts the two streams on one clock —
    /// each analyzer's own timeline starts at zero, so without it the transcript
    /// can show an answer before the question.
    func append(_ buffer: AVAudioPCMBuffer, startTime: CMTime) {
        inputContinuation?.yield(AnalyzerInput(buffer: buffer, bufferStartTime: startTime))
    }

    // MARK: - Model assets

    /// Reserving comes first. Without it the status never reaches installed and
    /// the model is downloaded again on every launch.
    private func prepareModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            throw TranscriberError.localeUnsupported(locale.identifier)
        }

        try await AssetInventory.reserve(locale: locale)
        reservedLocale = locale

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
