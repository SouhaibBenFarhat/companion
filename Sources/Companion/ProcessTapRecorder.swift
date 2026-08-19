import AVFoundation
import AudioToolbox
import CompanionCore
import CoreAudio
import Foundation

/// Captures everything the Mac is playing — which is the other side of the call.
///
/// A Core Audio process tap feeding a private aggregate device. Nothing is
/// installed, no virtual driver, and the user's own audio routing is untouched.
///
/// The rules inside the IO (input/output) block are absolute: copy bytes, move
/// an index, return. No allocation, no locks, no logging. It runs under a
/// deadline shared with whatever else is playing, so overrunning glitches the
/// user's call, not just our recording.
@available(macOS 14.4, *)
final class ProcessTapRecorder {
    /// Prefix on every object we create, so a crash can be cleaned up after.
    static let namePrefix = "Companion Tap"

    private let ring: AudioRingBuffer
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var format: AVAudioFormat?

    /// Host time of the most recent block, for the shared clock.
    private(set) var latestHostTime: UInt64 = 0

    init(ringCapacity: Int = 48_000 * 2) {
        ring = AudioRingBuffer(capacity: ringCapacity)
    }

    deinit { stop() }

    var streamFormat: AVAudioFormat? { format }

    func drain(maximum: Int = .max) -> [Float] { ring.read(maximum: maximum) }
    var droppedFrames: Int { ring.droppedFrames }

    // MARK: - Start and stop

    enum TapError: LocalizedError {
        case noDefaultOutput
        case tapFailed(OSStatus)
        case aggregateFailed(OSStatus)
        case formatUnavailable
        case ioProcFailed(OSStatus)
        case startFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .noDefaultOutput: return "No audio output device to tap."
            case .tapFailed(let code): return "Could not create the audio tap (\(code)). Screen Recording permission is what grants this."
            case .aggregateFailed(let code): return "Could not create the capture device (\(code))."
            case .formatUnavailable: return "The tap reported no audio format."
            case .ioProcFailed(let code): return "Could not attach to the capture device (\(code))."
            case .startFailed(let code): return "Could not start capture (\(code))."
            }
        }
    }

    func start() throws {
        stop()
        ring.reset()

        // Exclude ourselves, or the panel's own sounds land in the transcript.
        // An empty list is correct when our object does not exist yet.
        var excluded: [AudioObjectID] = []
        if let own = AudioProcessRegistry.ownObjectID() { excluded = [own] }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.name = "\(Self.namePrefix) \(UUID().uuidString.prefix(8))"
        description.isPrivate = true
        // Anything other than unmuted silences the user's call.
        description.muteBehavior = .unmuted

        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTap)
        guard tapStatus == noErr, newTap != AudioObjectID(kAudioObjectUnknown) else {
            throw TapError.tapFailed(tapStatus)
        }
        tapID = newTap

        guard let tapUID = Self.string(of: tapID, kAudioTapPropertyUID) else {
            stop()
            throw TapError.formatUnavailable
        }
        // Never assume the format — read what the tap actually produces.
        guard var described = Self.streamDescription(of: tapID),
              let tapFormat = AVAudioFormat(streamDescription: &described)
        else {
            stop()
            throw TapError.formatUnavailable
        }
        format = tapFormat

        guard let outputUID = Self.defaultOutputDeviceUID() else {
            stop()
            throw TapError.noDefaultOutput
        }

        // The clock source. Without `main` the IO proc never fires, and the
        // failure looks exactly like a permission problem.
        let uid = "\(Self.namePrefix)-\(UUID().uuidString)"
        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: uid,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [] as [[String: Any]],
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: 1,
                ] as [String: Any]
            ],
        ]

        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(settings as CFDictionary, &newAggregate)
        guard aggregateStatus == noErr, newAggregate != AudioObjectID(kAudioObjectUnknown) else {
            stop()
            throw TapError.aggregateFailed(aggregateStatus)
        }
        aggregateID = newAggregate

        // Weak, so a late block after teardown cannot resurrect this object.
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            aggregateID,
            nil
        ) { [weak self] inputTime, inputData, _, _, _ in
            guard let self else { return }
            self.latestHostTime = inputTime.pointee.mHostTime

            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            guard let first = buffers.first, let raw = first.mData else { return }

            let frameCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            let samples = UnsafeBufferPointer<Float>(
                start: raw.assumingMemoryBound(to: Float.self),
                count: frameCount
            )
            self.ring.write(samples)
        }

        guard procStatus == noErr, ioProcID != nil else {
            stop()
            throw TapError.ioProcFailed(procStatus)
        }

        let startStatus = AudioDeviceStart(aggregateID, ioProcID)
        guard startStatus == noErr else {
            stop()
            throw TapError.startFailed(startStatus)
        }
    }

    func stop() {
        if let ioProcID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil

        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        format = nil
    }

    // MARK: - Cleaning up after a crash

    /// Taps and aggregate devices outlive the process that made them. Without
    /// this they pile up invisibly across every crash during development.
    static func sweepOrphans() {
        for id in objectList(kAudioHardwarePropertyTapList) {
            guard let name = string(of: id, kAudioTapPropertyDescription) ?? string(of: id, kAudioTapPropertyUID),
                  name.contains(namePrefix)
            else { continue }
            AudioHardwareDestroyProcessTap(id)
        }

        for id in objectList(kAudioHardwarePropertyDevices) {
            guard let uid = string(of: id, kAudioDevicePropertyDeviceUID), uid.hasPrefix(namePrefix) else { continue }
            AudioHardwareDestroyAggregateDevice(id)
        }
    }

    // MARK: - Property helpers

    private static func objectList(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    private static func string(of objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString? = nil
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private static func streamDescription(of tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &description) == noErr else { return nil }
        return description
    }

    private static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }

        return string(of: deviceID, kAudioDevicePropertyDeviceUID)
    }
}
