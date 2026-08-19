import AVFoundation
import AudioToolbox
import CompanionCore
import CoreAudio
import Foundation

/// Owns both capture paths and keeps them on one clock.
///
/// A single `AVAudioEngine` has exactly one input device on macOS, so the
/// microphone and the system tap cannot share one. They are separate graphs
/// joined only by mach host time.
final class CallCapture {
    struct Levels: Equatable {
        var me: Float = 0
        var them: Float = 0
    }

    /// Called on the main queue with fresh audio, roughly ten times a second.
    var onChunk: ((PCMChunk) -> Void)?
    var onLevels: ((Levels) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var isRunning = false
    private(set) var callAppName: String?

    private let microphone = MicrophoneRecorder()
    private var tap: AnyObject?
    private var timeline = AudioTimeline(originHostTime: 0)
    private var pump: DispatchSourceTimer?
    private var listeners: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []
    private var restartState = CaptureRestartPolicy.State()
    private let restartPolicy = CaptureRestartPolicy()
    private var settings = AwarenessSettings()

    /// How often to move audio from the rings to the transcriber.
    private static let pumpInterval: TimeInterval = 0.1

    deinit { stop() }

    // MARK: - Lifecycle

    func start(settings: AwarenessSettings) {
        guard !isRunning else { return }
        self.settings = settings
        timeline = AudioTimeline(originHostTime: mach_absolute_time())

        if settings.captureMicrophone {
            do {
                try microphone?.start(echoCancellation: settings.echoCancellationEnabled)
            } catch {
                report(error.localizedDescription)
            }
        }

        if settings.captureSystemAudio {
            guard #available(macOS 14.4, *) else {
                report("Listening to the call needs macOS 14.4 or later.")
                return
            }
            let recorder = ProcessTapRecorder()
            do {
                try recorder.start()
                tap = recorder
                callAppName = AudioProcessRegistry.likelyCallAppName()
            } catch {
                report(error.localizedDescription)
            }
        }

        observeDeviceChanges()
        startPump()
        isRunning = true
        SessionLog.shared.write("capture", "started mic=\(settings.captureMicrophone) tap=\(tap != nil)")
    }

    func stop() {
        guard isRunning || pump != nil else { return }
        pump?.cancel()
        pump = nil

        microphone?.stop()
        if #available(macOS 14.4, *), let recorder = tap as? ProcessTapRecorder {
            recorder.stop()
        }
        tap = nil

        removeDeviceListeners()
        NotificationCenter.default.removeObserver(self)

        isRunning = false
        callAppName = nil
        onLevels?(Levels())
        SessionLog.shared.write("capture", "stopped")
    }

    /// Destroys anything left behind by a crash. Taps and aggregate devices
    /// outlive the process that created them.
    static func sweepOrphans() {
        guard #available(macOS 14.4, *) else { return }
        ProcessTapRecorder.sweepOrphans()
    }

    // MARK: - Moving audio

    private func startPump() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + Self.pumpInterval, repeating: Self.pumpInterval)
        timer.setEventHandler { [weak self] in self?.pumpOnce() }
        pump = timer
        timer.resume()
    }

    private func pumpOnce() {
        var levels = Levels()

        if let microphone {
            let samples = microphone.drain()
            if !samples.isEmpty {
                let chunk = PCMChunk(
                    speaker: .me,
                    hostTimeNanoseconds: microphone.latestHostTime,
                    sampleRate: microphone.targetFormat.sampleRate,
                    samples: samples
                )
                levels.me = chunk.level
                deliver(chunk)
            }
        }

        if #available(macOS 14.4, *), let recorder = tap as? ProcessTapRecorder {
            let samples = recorder.drain()
            if !samples.isEmpty {
                let chunk = PCMChunk(
                    speaker: .them,
                    hostTimeNanoseconds: recorder.latestHostTime,
                    sampleRate: recorder.streamFormat?.sampleRate ?? 48_000,
                    samples: samples
                )
                levels.them = chunk.level
                deliver(chunk)
            }
        }

        DispatchQueue.main.async { [weak self] in self?.onLevels?(levels) }
    }

    private func deliver(_ chunk: PCMChunk) {
        DispatchQueue.main.async { [weak self] in self?.onChunk?(chunk) }
    }

    func seconds(for hostTime: UInt64, speaker: CaptureSpeaker) -> TimeInterval {
        timeline.seconds(for: hostTime, speaker: speaker)
    }

    // MARK: - Devices changing underneath us

    private func observeDeviceChanges() {
        for selector in [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
        ] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.deviceChanged()
            }
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            // Keep the block: removing a listener requires the exact same one.
            if status == noErr { listeners.append((selector, block)) }
        }

        // The engine has its own contract and will silently stop delivering
        // microphone buffers if this is ignored.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.deviceChanged()
        }
    }

    private func removeDeviceListeners() {
        for (selector, block) in listeners {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
        listeners = []
    }

    /// Unplugging headphones fires several of these within milliseconds.
    private func deviceChanged() {
        guard isRunning else { return }
        let now = Date().timeIntervalSinceReferenceDate

        switch restartPolicy.requestRebuild(at: now, state: &restartState) {
        case .wait(let remaining):
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                self?.deviceChanged()
            }
        case .giveUp:
            report("The audio devices keep changing. Listening has stopped.")
            stop()
        case .rebuild:
            SessionLog.shared.write("capture", "device changed, rebuilding")
            let current = settings
            stop()
            start(settings: current)
            restartPolicy.succeeded(state: &restartState)
        }
    }

    private func report(_ message: String) {
        SessionLog.shared.write("capture", message)
        DispatchQueue.main.async { [weak self] in self?.onError?(message) }
    }
}
