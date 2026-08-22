import CompanionCore
import Foundation
import WhisperKit

/// Gets the model files onto this Mac, once, and says how it is going.
///
/// An actor with one cached `Task`, so that two engines starting at the same
/// moment produce one download rather than two.
public actor WhisperModelStore {
    public static let shared = WhisperModelStore()

    /// What the panel shows while this is happening.
    public enum Phase: Sendable, Equatable {
        case idle
        /// 0...1, and bytes per second when the download reports it.
        case downloading(fraction: Double, bytesPerSecond: Double?)
        /// Core ML compiling the model for this chip. There is no progress API
        /// for this at all — `WhisperKitConfig.prewarm`'s own documentation
        /// says Apple provides no way to ask whether the cache is warm.
        case preparing
        case ready
        case failed(String)

        public var message: String? {
            switch self {
            case .idle, .ready:
                return nil
            case .downloading(let fraction, let speed):
                let percent = Int((fraction * 100).rounded())
                guard let speed, speed > 0 else {
                    return "Downloading the speech model… \(percent)%"
                }
                let mbps = String(format: "%.1f", speed / 1_000_000)
                return "Downloading the speech model… \(percent)% (\(mbps) MB/s)"
            case .preparing:
                return "Preparing the speech model for this Mac…"
            case .failed(let message):
                return message
            }
        }
    }

    /// Whisper model variants Companion offers.
    ///
    /// The string is what `WhisperKit.download(variant:)` globs for
    /// (`"*\(variant)/*"`), so it must match exactly one folder in the repo.
    public enum Variant: String, Codable, CaseIterable, Sendable {
        /// 1.64 GB. Argmax's README: "Recommended on macOS for maximum speed
        /// and accuracy". Measured on this Mac (Mac16,8): a fresh 15 s window
        /// decodes in 1.10 s with the vocabulary prompt on.
        case largeTurbo = "large-v3-v20240930_turbo"
        /// 627 MB, same word error rate within about one point. For a slow
        /// connection or a smaller disk.
        case largeCompressed = "large-v3-v20240930_626MB"

        /// The folder `WhisperKit.download` returns for this variant.
        var folderName: String { "openai_whisper-\(rawValue)" }

        /// Where the tokenizer lands. A second download, from a different
        /// repository, that the model download does not include.
        var tokenizerFolderName: String { "openai/whisper-large-v3" }
    }

    public static let repo = "argmaxinc/whisperkit-coreml"

    /// Not WhisperKit's default.
    ///
    /// `HubApi` defaults `downloadBase` to `~/Documents/huggingface`, which
    /// drops 1.6 GB into the user's Documents folder — and into iCloud Drive if
    /// they sync it. Companion already owns
    /// `~/Library/Application Support/Companion`, so the weights live with the
    /// rest of its data and go away when it does.
    public static var downloadBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Companion", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    /// `HubApi.localRepoLocation` is `downloadBase/<type>/<repo id>`, then the
    /// variant folder under it. Reproduced here so the disk can be checked
    /// without building a `HubApi` — which would reach the network.
    public static func modelFolder(for variant: Variant) -> URL {
        downloadBase
            .appendingPathComponent("models/\(repo)", isDirectory: true)
            .appendingPathComponent(variant.folderName, isDirectory: true)
    }

    public static func tokenizerFile(for variant: Variant) -> URL {
        downloadBase
            .appendingPathComponent("models/\(variant.tokenizerFolderName)", isDirectory: true)
            .appendingPathComponent("tokenizer.json")
    }

    /// `loadModels()` resolves exactly these three and throws if one is
    /// missing. It no longer loads `TextDecoderContextPrefill.mlmodelc`, which
    /// v0.9 did — the file is still downloaded, and is 19 MB of dead weight.
    private static let required = ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]

    public static func isOnDisk(_ variant: Variant) -> Bool {
        let folder = modelFolder(for: variant)
        let models = required.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        return models && FileManager.default.fileExists(atPath: tokenizerFile(for: variant).path)
    }

    private var phase: Phase = .idle
    private var observers: [@Sendable (Phase) -> Void] = []
    private var work: [Variant: Task<URL, Error>] = [:]

    public func observe(_ handler: @escaping @Sendable (Phase) -> Void) {
        observers.append(handler)
        handler(phase)
    }

    private func set(_ next: Phase) {
        phase = next
        for observer in observers { observer(next) }
    }

    /// The folder to hand to `WhisperKitConfig(modelFolder:)`.
    ///
    /// Safe to call from both engines at once: the second one waits on the
    /// first one's download instead of starting its own.
    public func folder(for variant: Variant) async throws -> URL {
        if let existing = work[variant] { return try await existing.value }
        let task = Task<URL, Error> { try await provision(variant) }
        work[variant] = task
        do {
            return try await task.value
        } catch {
            // A failed download must not be remembered as the answer.
            work[variant] = nil
            throw error
        }
    }

    private func provision(_ variant: Variant) async throws -> URL {
        let folder = Self.modelFolder(for: variant)

        // Disk first, and this ordering is not politeness.
        //
        // `WhisperKit.download` always calls `HubApi.getFilenames`, which does a
        // plain HTTP GET with no offline branch — unlike `snapshot`, which
        // consults the network monitor. So an offline launch with the model
        // already cached fails, and it fails as "Model not found. Please check
        // the model or repo name and try again", which points at the wrong
        // thing entirely.
        if Self.isOnDisk(variant) {
            try await prepare(folder, variant: variant)
            return folder
        }

        set(.downloading(fraction: 0, bytesPerSecond: nil))

        // The bar is driven by bytes on disk, not by WhisperKit's `Progress`.
        //
        // `HubApi.snapshot` builds `Progress(totalUnitCount: filenames.count)`
        // and gives every file `pendingUnitCount: 1`, but two of the twenty
        // files hold 99.9% of the bytes. `fractionCompleted` reaches about 0.9
        // in a second and then sits there for six minutes.
        let ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await self?.tickDiskProgress(variant)
            }
        }
        defer { ticker.cancel() }

        let downloaded: URL
        do {
            downloaded = try await WhisperKit.download(
                variant: variant.rawValue,
                downloadBase: Self.downloadBase,
                useBackgroundSession: false,
                from: Self.repo,
                progressCallback: { [weak self] progress in
                    // `fractionCompleted` is file-count weighted and useless,
                    // but `throughputKey` is honest bytes per second.
                    let speed = progress.userInfo[.throughputKey] as? Double
                    Task { await self?.noteSpeed(speed) }
                }
            )
        } catch {
            let message = "Could not download the speech model: \(error.localizedDescription)"
            set(.failed(message))
            SessionLog.shared.write("whisper", message)
            throw error
        }

        try await prepare(downloaded, variant: variant)
        return downloaded
    }

    private func noteSpeed(_ speed: Double?) {
        guard case .downloading(let fraction, _) = phase else { return }
        set(.downloading(fraction: fraction, bytesPerSecond: speed))
    }

    /// Completed files land at `<repo root>/<relative path>`; bytes still in
    /// flight sit beside them under `.cache/huggingface/download` and are moved
    /// on completion, so summing the whole tree never double counts.
    private func tickDiskProgress(_ variant: Variant) {
        guard case .downloading(_, let speed) = phase else { return }
        let root = Self.downloadBase.appendingPathComponent("models/\(Self.repo)", isDirectory: true)
        var bytes: Int64 = 0
        if let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let url as URL in walker {
                bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        let expected = Self.expectedBytes(variant)
        set(.downloading(fraction: min(Double(bytes) / expected, 0.999), bytesPerSecond: speed))
    }

    /// Sum of the files in the variant's folder, from the HuggingFace tree API.
    /// Only used to turn bytes into a fraction; being a little off is harmless.
    private static func expectedBytes(_ variant: Variant) -> Double {
        switch variant {
        case .largeTurbo: return 1_638_500_000
        case .largeCompressed: return 627_000_000
        }
    }

    /// Loads once, here, so the two engines that follow hit a warm Core ML
    /// cache and a tokenizer that is already on disk.
    ///
    /// `prewarm: true` loads and unloads each of the three models in turn,
    /// which holds peak memory to one model instead of three while Core ML
    /// specialises them for this chip. From the option's own documentation:
    /// that specialised cache "is evicted after every OS update", so this step
    /// reappears, without warning, after the user updates macOS.
    ///
    /// This is also what fetches the tokenizer — a second download, about
    /// 2.8 MB, from `openai/whisper-large-v3` rather than from the model repo.
    /// Doing it here means every later load is fully offline.
    private func prepare(_ folder: URL, variant: Variant) async throws {
        set(.preparing)
        do {
            _ = try await WhisperKit(WhisperKitConfig(
                modelFolder: folder.path,
                tokenizerFolder: Self.downloadBase,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            ))
            set(.ready)
        } catch {
            let message = "Could not prepare the speech model: \(error.localizedDescription)"
            set(.failed(message))
            SessionLog.shared.write("whisper", message)
            throw error
        }
    }
}
