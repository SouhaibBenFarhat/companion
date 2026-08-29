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
/// 3. With voice processing on, the input format grows echo-reference
///    channels — seven or nine on this hardware, not one. The converter must
///    take channel 0 alone: the default downmix of that layout converts every
///    buffer without error and writes silence, which is how listening once
///    ran with a live engine, a started log line, and no words. And a chosen
///    device goes on the unit's INPUT element — the voice-processing unit
///    owns both directions, and binding a capture-only device at global scope
///    points its output half at a device that cannot play, after which the
///    engine either refuses to start (-10875) or starts with a tap that
///    never fires. All of this was measured on hardware, not inferred.
final class MicrophoneRecorder {
    /// Replaced on every attempt, never reused.
    ///
    /// A failed start leaves the input node's audio unit initialised and
    /// holding the device it failed on, and the next attempt could not even set
    /// a device on it — -10851 on the retry, so the fallback ladder collapsed
    /// on its second rung for a reason that had nothing to do with the device
    /// it was trying.
    private var engine = AVAudioEngine()
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

    /// Whether the engine is actually delivering.
    ///
    /// `AVAudioEngine` stops itself on a configuration change and does not
    /// restart. A caller that decided a notification was ignorable needs a way
    /// to tell quiet from dead — the levels are zero in both.
    var isEngineRunning: Bool { engine.isRunning }

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
        do {
            try open(echoCancellation: echoCancellation, device: device)
        } catch {
            // One fallback, not a ladder. The four-rung version existed to
            // escape -10875, which was caused by connecting the shared
            // input/output unit to the mixer — not by the device and not by
            // echo cancellation. With that line gone the only case left worth
            // handling is a device genuinely held by another app.
            guard let device else { throw error }
            SessionLog.shared.write(
                "mic",
                "\(device.name) would not open (\(error.localizedDescription)), using the system default"
            )
            onDegraded?("\(device.name) would not open. Listening on the system default microphone.")
            try open(echoCancellation: echoCancellation, device: nil)
        }
    }

    /// Reported when listening started, but not the way it was asked for.
    var onDegraded: ((String) -> Void)?

    private func open(echoCancellation: Bool, device: AudioInputDevice?) throws {
        stop()
        ring.reset()
        engine = AVAudioEngine()
        // Reset here, not trusted from last time: an open that threw between
        // enabling voice processing and installing the tap leaves stop() with
        // nothing to tear down, so the flag survives — and it now decides the
        // device element and the channel map, where stale-true is not
        // harmless.
        voiceProcessingActive = false

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
            // Only a device the user actually chose arrives here — the caller
            // hands the resolver's fallback as nil. Binding the fallback would
            // only restate the system default, riskily, while pinning it —
            // and "empty means the system default" is meant to follow the
            // default when macOS moves it, not freeze it at start time.
            if AudioDevices.use(
                device,
                on: engine,
                // The voice-processing unit carries both directions. Its
                // device belongs on the input element; set at global scope it
                // reaches the output half too, and a microphone cannot play.
                element: voiceProcessingActive ? 1 : 0
            ) {
                SessionLog.shared.write("mic", "using \(device.name)")
            } else {
                SessionLog.shared.write("mic", "\(device.name) refused; using the system default")
            }
        } else {
            SessionLog.shared.write("mic", "using the system default microphone")
        }

        // Nothing is connected to the mixer, on purpose.
        //
        // On macOS the input node and the output node are the SAME audio unit —
        // `engine.inputNode.auAudioUnit === engine.outputNode.auAudioUnit` is
        // literally true. Touching `mainMixerNode` pulls the output half of that
        // unit into the graph, so it then has to PLAY audio on whichever device
        // was chosen for INPUT. The Logitech Brio has two input channels and no
        // output channels, so the output format was invalid and the engine
        // refused to start: -10875, with `IsFormatSampleRateAndChannelCountValid(outputHWFormat)`
        // named in the error itself.
        //
        // The comment that used to be here said this line was needed for voice
        // processing to engage. That was the opposite of the truth, and it is
        // why six rounds of fixing looked at the microphone instead of the line.
        engine.prepare()

        // Read the format only now — voice processing changed it.
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw MicrophoneError.noInputFormat
        }
        SessionLog.shared.write(
            "mic",
            "format \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) ch, "
                + "voice processing \(voiceProcessingActive ? "on" : "off")"
        )
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw MicrophoneError.converterUnavailable
        }
        if voiceProcessingActive, inputFormat.channelCount > 1 {
            // The processed voice is channel 0; the rest are echo-reference
            // channels. Left to its own downmix of that layout, the converter
            // reports success on every buffer and writes zeros — the failure
            // that looks like a user who is not speaking.
            converter.channelMap = [0]
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
