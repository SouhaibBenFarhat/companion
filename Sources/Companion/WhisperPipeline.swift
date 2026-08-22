import CompanionCore
import Foundation
import WhisperKit

/// One speaker's WhisperKit instance, sealed inside an actor.
///
/// An actor for two reasons, both checked rather than assumed.
///
/// `WhisperKit` is not `Sendable` — `open class WhisperKit` with no
/// conformance — so it must never cross an isolation boundary. Under Swift 6
/// that is a compile error; a probe here produced "non-Sendable type
/// 'WhisperKit' … cannot exit main actor-isolated context". Keeping it inside
/// one actor is what makes two instances legal at all.
///
/// And a decode takes about a second. `WhisperEngine` lives on the main queue
/// with the rest of the app, so the work has to happen somewhere else or the
/// panel freezes once a second.
///
/// Everything crossing the boundary is a value: `[Float]` in, `String` out.
actor WhisperPipeline {
    private var pipe: WhisperKit?
    private var promptTokens: [Int] = []
    private var language = "en"

    /// Loads the model from a folder that is already on disk.
    ///
    /// `download: false` on purpose — provisioning happened in
    /// `WhisperModelStore`, and letting this reach for the network would put a
    /// six-minute silent pause behind a button press.
    func load(folder: URL, language: String) async throws {
        self.language = language
        let pipe = try await WhisperKit(WhisperKitConfig(
            modelFolder: folder.path,
            tokenizerFolder: WhisperModelStore.downloadBase,
            computeOptions: ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            ),
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        ))
        self.pipe = pipe
    }

    func unload() async {
        if let pipe { await pipe.unloadModels() }
        pipe = nil
        promptTokens = []
    }

    /// The vocabulary, as decoder tokens.
    ///
    /// Rebuilt whenever the repository changes, because the words worth
    /// biasing towards are that repository's identifiers.
    ///
    /// Two hard limits, both read in `TextDecoder.prefillDecoderInputs`:
    /// it keeps only the last `(Constants.maxTokenContext / 2) - 1` = 111
    /// tokens, and it drops anything at or above `specialTokenBegin`. The
    /// filter is applied here too so the count Companion logs is the count the
    /// decoder will actually use. Truncation keeps the END of the list, so the
    /// caller puts its best terms last.
    func setVocabulary(_ terms: [String], budget: Int = 60) {
        guard let tokenizer = pipe?.tokenizer else { return }
        var chosen: [String] = []
        var spent = 0
        // Best first, so the budget buys the best terms.
        for term in terms.reversed() {
            // Content tokens only. Measured: `encode(text:)` wraps every call
            // in three special tokens — " AVAudioConverter" comes back as 9
            // tokens of which 6 are the word. Counting the raw length
            // overcharges each term by three and quietly drops terms that
            // would have fitted.
            let cost = tokenizer.encode(text: " " + term)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
                .count
            guard spent + cost <= budget else { continue }
            spent += cost
            chosen.append(term)
        }
        // Then reversed again, so the best term ends up last in the string.
        let text = " " + chosen.reversed().joined(separator: " ")
        promptTokens = tokenizer.encode(text: text)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        SessionLog.shared.write("whisper", "vocabulary: \(chosen.count) terms, \(promptTokens.count) tokens")
    }

    var vocabularyTokenCount: Int { promptTokens.count }

    /// Whether this instance is ready to be asked for text.
    var isLoaded: Bool { pipe != nil }

    /// Turns one bounded window of audio into one line of text.
    ///
    /// Every option below was measured on this Mac against
    /// `openai_whisper-large-v3-v20240930_turbo`, not recalled:
    ///
    /// - `temperatureFallbackCount: 0`. The default is 5. On a 20 s window with
    ///   the vocabulary prompt, 5 turned a 1.93 s decode into 9.88 s, with 4
    ///   fallbacks fired. Live transcription needs a bounded cost far more than
    ///   it needs a retry.
    /// - `wordTimestamps: false`. This one is not a preference. With
    ///   `promptTokens` set, word timings come back wrong: on 14.37 s of audio
    ///   every word started at 0.00 and the last word ended at 3.02. The cause
    ///   is in the library — `TextDecoder` writes alignment rows at absolute
    ///   decoder positions, which include the prompt, and
    ///   `SegmentSeeker.addWordTimestamps` reads them back from index 0. With
    ///   word timings on, that damage also overwrites the segment times.
    ///   Companion needs neither: a window's position comes from the mach host
    ///   time of the chunk that opened it.
    /// - `usePrefillPrompt: true`. `TranscribeTask` reads `promptTokens` only
    ///   when this is true, and it fails silently — the whole vocabulary is
    ///   thrown away with no error.
    /// - `withoutTimestamps: true`. One window is one line here, so the
    ///   timestamp tokens buy nothing. On a 20 s window they also produced
    ///   three times the expected text — the same passage transcribed over and
    ///   over — where turning them off gave the right length in 1.29 s instead
    ///   of 1.93 s.
    /// - `chunkingStrategy: ChunkingStrategy.none`, spelled out. A bare `.none`
    ///   against `ChunkingStrategy?` resolves to `Optional.none`, and the
    ///   window would be re-chunked by a second voice detector.
    func decode(_ samples: [Float]) async throws -> String {
        guard let pipe else { return "" }

        // The thresholds are Whisper's own defence against its worst failure,
        // and they are not optional here.
        //
        // Left off, a window it cannot make sense of comes back as a loop:
        // "and type, and type, and type" for a hundred words. Every one of
        // those settings below exists to catch that. The compression ratio of
        // repeated text is enormous, so it trips the check, and the decode is
        // retried at a higher temperature until it stops repeating.
        //
        // The cost is real — a fallback pass is another decode — but it is
        // paid only on windows that failed, and the alternative is filling the
        // panel with words nobody said.
        var options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            clipTimestamps: [],
            // Whisper's published values. Above this ratio the text is judged
            // too repetitive to be real; below that log probability it is
            // judged a guess; and a high no-speech probability with a low
            // score is silence, which is where the loops start.
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6,
            chunkingStrategy: ChunkingStrategy.none
        )
        if !promptTokens.isEmpty { options.promptTokens = promptTokens }

        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
    }
}
