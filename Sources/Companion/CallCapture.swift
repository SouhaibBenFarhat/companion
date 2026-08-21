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
    private let state = DispatchQueue(label: "companion.capture.state")
    private var tap: AnyObject?

    /// The tap, read safely from the pump queue.
    @available(macOS 14.4, *)
    private var currentTap: ProcessTapRecorder? {
        state.sync { tap as? ProcessTapRecorder }
    }
    private var timeline = AudioTimeline(originHostTime: 0)
    private var pump: DispatchSourceTimer?
    private var listeners: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []
    /// addObserver(forName:) registers the returned token, not self, so keeping
    /// it is the only way to remove the observer later.
    private var configurationObserver: NSObjectProtocol?
    /// Host time listening began. Survives a rebuild; cleared only when the
    /// user actually stops.
    private var sessionOrigin: UInt64?
    private var restartState = CaptureRestartPolicy.State()
    private let restartPolicy = CaptureRestartPolicy()
    private var settings = AwarenessSettings()
    /// Which microphone to open. Empty means the system default.
    var preferredInputUID = ""

    /// How often to move audio from the rings to the transcriber.
    private static let pumpInterval: TimeInterval = 0.1

    deinit { stop() }

    // MARK: - Lifecycle

    func start(settings: AwarenessSettings) {
        guard !isRunning else { return }
        self.settings = settings

        // The clock belongs to the listening session, not to this graph.
        //
        // A rebuild used to take a fresh origin, so audio that had been at
        // thirty seconds came back at zero while the transcriber was still
        // holding the earlier part — "Audio input timestamp overlaps or
        // precedes prior audio input", every time a device changed.
        let origin = sessionOrigin ?? mach_absolute_time()
        sessionOrigin = origin
        timeline = AudioTimeline(originHostTime: origin, clock: HostClock.current)

        if settings.captureMicrophone {
            do {
                let chosen = AudioInputSelection.resolve(
                    preferredUID: preferredInputUID,
                    available: AudioDevices.inputs()
                )
                microphone?.onDeviceUnavailable = { [weak self] name in
                    self?.report("\(name) would not open. Using the system default microphone.")
                }
                try microphone?.start(
                    echoCancellation: settings.echoCancellationEnabled,
                    device: chosen
                )
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
                state.sync { tap = recorder }
                callAppName = AudioProcessRegistry.likelyCallAppName()
            } catch {
                report(error.localizedDescription)
            }
        }

        observeDeviceChanges()
        startPump()
        isRunning = true
        // What the devices looked like when this graph came up. Anything that
        // arrives before it settles, or that leaves this unchanged, is noise.
        restartState.started(
            at: Date().timeIntervalSinceReferenceDate,
            fingerprint: AudioDevices.fingerprint()
        )
        SessionLog.shared.write("capture", "started mic=\(settings.captureMicrophone) tap=\(tap != nil)")
    }

    /// - Parameter endingSession: false while rebuilding, which must keep the
    ///   clock it has been handing to the transcribers.
    func stop(endingSession: Bool = true) {
        if endingSession { sessionOrigin = nil }
        guard isRunning || pump != nil else { return }
        pump?.cancel()
        pump = nil

        microphone?.stop()
        if #available(macOS 14.4, *), let recorder = currentTap {
            recorder.stop()
        }
        state.sync { tap = nil }

        removeDeviceListeners()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }

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
            let batch = microphone.drain()
            if !batch.samples.isEmpty {
                let chunk = PCMChunk(
                    speaker: .me,
                    hostTimeNanoseconds: batch.hostTime,
                    sampleRate: microphone.targetFormat.sampleRate,
                    samples: batch.samples
                )
                levels.me = chunk.level
                deliver(chunk)
            }
        }

        if #available(macOS 14.4, *), let recorder = currentTap {
            let batch = recorder.drain()
            if !batch.samples.isEmpty {
                let chunk = PCMChunk(
                    speaker: .them,
                    hostTimeNanoseconds: batch.hostTime,
                    sampleRate: recorder.streamFormat?.sampleRate ?? 48_000,
                    samples: batch.samples
                )
                levels.them = chunk.level
                deliver(chunk)
            }
        }

        // Audio arriving is the only proof a rebuild worked — and it has to
        // keep arriving. A trickle between two failures is not a recovery.
        if levels.me > 0 || levels.them > 0 {
            restartPolicy.succeeded(at: Date().timeIntervalSinceReferenceDate, state: &restartState)
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
        configurationObserver = NotificationCenter.default.addObserver(
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

        switch restartPolicy.requestRebuild(
            at: now,
            fingerprint: AudioDevices.fingerprint(),
            state: &restartState
        ) {
        case .ignore(let why):
            // Not worth a line each time; this fires in bursts.
            _ = why

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
            stop(endingSession: false)
            start(settings: current)
            // Deliberately not marking success here. Audio is not flowing yet,
            // and clearing the counter now would let a device that keeps
            // failing rebuild forever.
        }
    }

    private func report(_ message: String) {
        SessionLog.shared.write("capture", message)
        DispatchQueue.main.async { [weak self] in self?.onError?(message) }
    }
}
