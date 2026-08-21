import AVFoundation
import CompanionCore
import CoreAudio
import Foundation

/// Finds the microphones on this Mac, and points the engine at one.
enum AudioDevices {
    /// Every device that can record.
    static func inputs() -> [AudioInputDevice] {
        let defaultUID = defaultInputUID()

        return allDeviceIDs().compactMap { id in
            // Zero input channels means it can only play. A pair of speakers is
            // not a microphone, and listing it would be a trap.
            guard inputChannelCount(of: id) > 0,
                  let uid = string(of: id, kAudioDevicePropertyDeviceUID),
                  let name = string(of: id, kAudioObjectPropertyName)
            else { return nil }

            return AudioInputDevice(uid: uid, name: name, isSystemDefault: uid == defaultUID)
        }
    }

    /// Points the engine's input at a device.
    ///
    /// Must happen before the engine starts. `AVAudioEngine` has no API for
    /// this — the device is set on the audio unit underneath its input node,
    /// which is why this reaches through to Core Audio.
    @discardableResult
    static func use(_ device: AudioInputDevice, on engine: AVAudioEngine) -> Bool {
        guard let id = deviceID(forUID: device.uid), let unit = engine.inputNode.audioUnit else {
            return false
        }

        var deviceID = id
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            SessionLog.shared.write("mic", "could not select \(device.name) (\(status))")
        }
        return status == noErr
    }

    // MARK: - Lookups

    private static func allDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
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

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { string(of: $0, kAudioDevicePropertyDeviceUID) == uid }
    }

    private static func defaultInputUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        ) == noErr else { return nil }
        return string(of: id, kAudioDevicePropertyDeviceUID)
    }

    private static func inputChannelCount(of id: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }

        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(of id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}
