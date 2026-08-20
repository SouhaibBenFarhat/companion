import AVFoundation
import AppKit
import ApplicationServices
import CompanionCore
import CoreGraphics
import ScreenCaptureKit

/// Asks macOS what Companion is actually allowed to do.
///
/// Every check here is non-blocking and prompt-free. Asking is a separate,
/// deliberate act — a panel that fires three system prompts the moment it opens
/// is one people deny out of reflex.
enum PermissionChecker {
    static func report() -> PermissionReport {
        PermissionReport(
            statuses: Permission.allCases.map {
                PermissionStatus(permission: $0, state: state(of: $0))
            }
        )
    }

    static func state(of permission: Permission) -> PermissionState {
        switch permission {
        case .microphone: return microphone()
        case .systemAudio: return screenRecording()
        case .accessibility: return accessibility()
        }
    }

    private static func microphone() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    /// `CGPreflightScreenCaptureAccess` asks without prompting.
    ///
    /// It cannot tell "never asked" from "refused", so a false reading means
    /// the same thing either way: send the user to System Settings.
    private static func screenRecording() -> PermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Passing `kAXTrustedCheckOptionPrompt` as false is what keeps this quiet.
    private static func accessibility() -> PermissionState {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary) ? .granted : .denied
    }

    // MARK: - Asking

    /// Requests one permission, then reports the state afterwards.
    ///
    /// Only the microphone has a real in-app prompt. The other two can only be
    /// granted in System Settings, so "requesting" them means opening the right
    /// pane and adding Companion to the list.
    static func request(_ permission: Permission, completion: @escaping (PermissionState) -> Void) {
        switch permission {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { completion(microphone()) }
            }

        case .systemAudio:
            // `CGRequestScreenCaptureAccess` prompts once per app identity and
            // then does nothing forever after. An app that used up its prompt
            // and was refused is invisible: it never appears in the Screen
            // Recording list, so there is nothing for the user to switch on and
            // no way to add it by hand.
            //
            // Actually attempting a capture registers the app regardless. So
            // ask first, and if that is a no, make a real attempt so the entry
            // exists before sending the user to look for it.
            if CGRequestScreenCaptureAccess() {
                DispatchQueue.main.async { completion(.granted) }
                return
            }

            registerForScreenRecording { [self] in
                openSettings(for: permission)
                DispatchQueue.main.async { completion(screenRecording()) }
            }

        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
            if !trusted { openSettings(for: permission) }
            DispatchQueue.main.async { completion(trusted ? .granted : .denied) }
        }
    }

    /// Forces macOS to list Companion under Screen Recording.
    ///
    /// The attempt is expected to fail — that is the point. Asking the window
    /// server for shareable content is what creates the entry, and until the
    /// entry exists the user is hunting for a row that was never added.
    private static func registerForScreenRecording(then finish: @escaping () -> Void) {
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                SessionLog.shared.write("permission", "screen recording already available")
            } catch {
                // Expected while denied. The call still registers the app.
                SessionLog.shared.write("permission", "registered for screen recording")
            }
            await MainActor.run { finish() }
        }
    }

    static func openSettings(for permission: Permission) {
        // Companion never activates on its own, so System Settings would open
        // behind whatever is in front without this.
        NSWorkspace.shared.open(permission.settingsURL)
        NSApp.activate(ignoringOtherApps: false)
    }
}
