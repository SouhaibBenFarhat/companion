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

    /// Host time of the most recent buffer, for the shared clock.
    private(set) var latestHostTime: UInt64 = 0
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

    func drain(maximum: Int = .max) -> [Float] { ring.read(maximum: maximum) }
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

    func start(echoCancellation: Bool) throws {
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

        let latency = input.presentationLatency
        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, time in
            guard let self else { return }
            // Subtract the hardware delay, or the user's words are timestamped
            // later than they were spoken.
            let latencyNanoseconds = UInt64(max(0, latency) * 1_000_000_000)
            self.latestHostTime = time.hostTime &- latencyNanoseconds
            self.append(buffer, using: converter)
        }

        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning || engine.isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
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
    private func append(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) {
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
        ring.write(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
