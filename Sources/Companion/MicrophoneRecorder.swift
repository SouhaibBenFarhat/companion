import AVFoundation
import CompanionCore
import Foundation

/// Captures the user's own voice.
///
/// The order of operations below is not stylistic. Getting it wrong produces
/// failures that look like anything but their cause:
///
/// 1. Check the permission first. Before the grant, `inputNode.outputFormat`
///    reports 0 Hz and installing a tap throws an Objective-C exception that
///    Swift cannot catch — the app dies with no usable message.
/// 2. Turn on voice processing before reading the format. It changes the
///    format, and a mismatch between the format passed to `installTap` and the
///    node's real one raises the same uncatchable exception.
/// 3. Connect the input to the mixer at zero volume. Voice processing only
///    engages when there is a rendering graph; without it the setting is
///    accepted and does nothing. Zero volume is what stops the user hearing
///    themselves.
final class MicrophoneRecorder {
    private let engine = AVAudioEngine()
    private let ring = AudioRingBuffer(capacity: 48_000 * 2)
    private var converter: AVAudioConverter?
    private var isRunning = false
    /// Tracked separately from `isRunning`: the tap is installed before the
    /// engine starts, so a failed start would otherwise leave it behind.
    private var tapInstalled = false

    /// Whether echo cancellation actually engaged.
    private(set) var voiceProcessingActive = false

    let targetFormat: AVAudioFormat

    init?(sampleRate: Double = 16_000) {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }
        targetFormat = format
    }

    deinit { stop() }

    func drain(maximum: Int = .max) -> (samples: [Float], hostTime: UInt64) { ring.drain(maximum: maximum) }
    var droppedFrames: Int { ring.droppedFrames }

    enum MicrophoneError: LocalizedError {
        case notPermitted
        case noInputFormat
        case converterUnavailable

        var errorDescription: String? {
            switch self {
            case .notPermitted: return "Microphone permission has not been granted."
            case .noInputFormat: return "The microphone reported no usable format."
            case .converterUnavailable: return "Could not convert the microphone's format."
            }
        }
    }

    /// - Parameter device: which microphone to open. Nil takes the system
    ///   default, which on a Mac with several is a coin toss — Continuity can
    ///   hand it the iPhone microphone without warning.
    func start(echoCancellation: Bool, device: AudioInputDevice? = nil) throws {
        // Give up the least valuable thing first.
        //
        // A USB microphone can refuse the voice processor outright — the Brio
        // fails initialisation with -10875 while the same device opens fine
        // without it — and a device another app holds can refuse everything.
        // Neither is knowable in advance, so this tries in the order of what
        // is worth keeping: your microphone matters more than echo
        // cancellation, because a gate in software covers some of what the
        // processor does and nothing covers recording the wrong microphone.
        var attempts: [(device: AudioInputDevice?, echo: Bool, note: String)] = []
        if echoCancellation {
            attempts.append((device, true, ""))
            attempts.append((device, false, "without echo cancellation"))
        } else {
            attempts.append((device, false, ""))
        }
        if device != nil {
            attempts.append((nil, echoCancellation, "on the system default microphone"))
            if echoCancellation {
                attempts.append((nil, false, "on the system default microphone, without echo cancellation"))
            }
        }

        var lastError: Error?
        for attempt in attempts {
            do {
                try open(echoCancellation: attempt.echo, device: attempt.device)
                if !attempt.note.isEmpty {
                    let name = device?.name ?? "The microphone"
                    SessionLog.shared.write("mic", "started \(attempt.note)")
                    onDegraded?("\(name) would not open. Listening \(attempt.note).")
                }
                return
            } catch {
                lastError = error
                SessionLog.shared.write(
                    "mic",
                    "attempt failed (\(attempt.device?.name ?? "system default"), echo=\(attempt.echo)): \(error.localizedDescription)"
                )
            }
        }

        throw lastError ?? MicrophoneError.noInputFormat
    }

    /// Reported when listening started, but not the way it was asked for.
    var onDegraded: ((String) -> Void)?

    private func open(echoCancellation: Bool, device: AudioInputDevice?) throws {
        stop()
        ring.reset()

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw MicrophoneError.notPermitted
        }

        let input = engine.inputNode

        if echoCancellation {
            do {
                try input.setVoiceProcessingEnabled(true)
                voiceProcessingActive = true
                // The mildest ducking available, so turning this on does not
                // make the person you are listening to quieter.
                if #available(macOS 14.0, *) {
                    let ducking = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                        enableAdvancedDucking: false,
                        duckingLevel: .min
                    )
                    input.voiceProcessingOtherAudioDuckingConfiguration = ducking
                }
            } catch {
                // Meet or Zoom may already hold voice processing on this device.
                // Plain capture is still useful; the echo gate covers the rest.
                voiceProcessingActive = false
                SessionLog.shared.write("mic", "voice processing unavailable: \(error.localizedDescription)")
            }
        }

        // The device goes on last, after voice processing and before the
        // format is read.
        //
        // Not first, which is where it was: turning voice processing on swaps
        // the input node's audio unit for the voice-processing one, so a device
        // set before that was set on a unit that then got thrown away. The
        // engine came up on the system default with no error, or refused to
        // start at all with -10875.
        //
        // Still before the format is read, because the converter is built from
        // that format and the device decides it.
        if let device {
            if AudioDevices.use(device, on: engine) {
                SessionLog.shared.write("mic", "using \(device.name)")
            } else {
                SessionLog.shared.write("mic", "\(device.name) refused; using the system default")
            }
        }

        // Voice processing needs a rendering graph to engage at all.
        engine.connect(input, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()

        // Read the format only now — voice processing changed it.
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw MicrophoneError.noInputFormat
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw MicrophoneError.converterUnavailable
        }
        self.converter = converter

        // Host time is a tick count, not nanoseconds, so the latency has to be
        // converted through the machine's timebase before it can be subtracted.
        let latencyTicks = HostClock.current.ticks(fromSeconds: max(0, input.presentationLatency))
        let rate = targetFormat.sampleRate

        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, time in
            guard let self else { return }
            // Subtract the hardware delay, or the user's words are timestamped
            // later than they were spoken.
            let captured = time.hostTime > latencyTicks ? time.hostTime &- latencyTicks : time.hostTime
            self.append(buffer, using: converter, hostTime: captured, sampleRate: rate)
        }

        tapInstalled = true

        try engine.start()
        isRunning = true
    }

    func stop() {
        guard tapInstalled || isRunning || engine.isRunning else { return }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        if voiceProcessingActive {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
            voiceProcessingActive = false
        }
        converter = nil
        isRunning = false
    }

    /// Converts to the transcriber's format off the audio thread's critical
    /// path, then hands raw floats to the ring.
    private func append(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        hostTime: UInt64,
        sampleRate: Double
    ) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

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

        guard error == nil, output.frameLength > 0, let channel = output.floatChannelData?[0] else { return }
        ring.write(
            UnsafeBufferPointer(start: channel, count: Int(output.frameLength)),
            hostTime: hostTime,
            sampleRate: sampleRate
        )
    }
}
