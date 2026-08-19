import AudioToolbox
import CompanionCore
import CoreAudio
import Foundation

/// Which processes are playing audio right now.
///
/// Two jobs: find Companion's own audio object so the tap can exclude it — a
/// tap that records our own output would feed the panel's sounds back into the
/// transcript — and name the app the call is coming from, so the panel can say
/// "Chrome" rather than "something".
@available(macOS 14.4, *)
enum AudioProcessRegistry {
    struct AudioProcess {
        let objectID: AudioObjectID
        let processID: pid_t
        let bundleIdentifier: String?
        /// Holds an active output stream. Not the same as "making a sound right
        /// now" — a paused video still reports true — so any label built from
        /// this is a good guess, not a fact.
        let isRunningOutput: Bool
    }

    /// Apps worth naming as the source of a call, most likely first.
    private static let callApps: [(identifier: String, name: String)] = [
        ("us.zoom.xos", "Zoom"),
        ("com.microsoft.teams2", "Teams"),
        ("com.microsoft.teams", "Teams"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.google.Chrome", "Chrome"),
        ("com.apple.Safari", "Safari"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.brave.Browser", "Brave"),
        ("com.microsoft.edgemac", "Edge"),
        ("com.apple.FaceTime", "FaceTime"),
        ("com.hnc.Discord", "Discord"),
    ]

    static func all() -> [AudioProcess] {
        objectIDs().compactMap { objectID in
            guard let processID: pid_t = value(of: objectID, kAudioProcessPropertyPID) else { return nil }
            return AudioProcess(
                objectID: objectID,
                processID: processID,
                bundleIdentifier: string(of: objectID, kAudioProcessPropertyBundleID),
                isRunningOutput: (value(of: objectID, kAudioProcessPropertyIsRunningOutput) as UInt32?) == 1
            )
        }
    }

    /// Companion's own audio object, so the tap can leave it out.
    ///
    /// Returns nil if Companion has never played a sound — the object may not
    /// exist yet. An empty exclusion list is right in that case; passing a
    /// garbage identifier is far worse.
    static func ownObjectID() -> AudioObjectID? {
        var processID = getpid()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &processID,
            &size,
            &objectID
        )

        guard status == noErr, objectID != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return objectID
    }

    /// A friendly name for whatever is most likely to be the call.
    static func likelyCallAppName() -> String? {
        let playing = all().filter(\.isRunningOutput)
        for known in callApps {
            if playing.contains(where: { $0.bundleIdentifier == known.identifier }) {
                return known.name
            }
        }
        // Nothing recognised: fall back to the last component of any bundle
        // identifier that is playing.
        return playing.compactMap(\.bundleIdentifier).first?.components(separatedBy: ".").last
    }

    // MARK: - Property reading

    private static func objectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids
    }

    private static func value<T>(of objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let storage = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { storage.deallocate() }

        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, storage) == noErr else { return nil }
        return storage.pointee
    }

    private static func string(of objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString? = nil

        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}
