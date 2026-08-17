import AppKit
import CompanionCore

/// The floating window.
///
/// Two behaviours matter here and they pull against each other:
///
/// 1. `.nonactivatingPanel` keeps Companion from coming to the front. The app
///    you are presenting stays active, and the call app sees no window switch.
/// 2. `canBecomeKey` lets you type into the panel anyway.
///
/// A borderless window returns false from `canBecomeKey` by default, so
/// without the override the panel would appear and quietly swallow nothing —
/// every keystroke would go to the editor behind it. Spotlight and Raycast
/// behave the same way.
final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Main status would make Companion the active app, which is exactly what
    /// `.nonactivatingPanel` is there to avoid.
    override var canBecomeMain: Bool { false }

    static func make(contentRect: NSRect) -> ChatPanel {
        let panel = ChatPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        // The whole reason this app exists: screen capture skips windows with
        // sharing turned off, so the panel stays on your display and never
        // reaches the shared stream in Meet, Teams, Zoom or Slack.
        panel.sharingType = .none

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        // Stay put when you switch app or Space — you are presenting, and a
        // panel that vanished on every focus change would be useless.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Not in the window menu or the ⌘` cycle; it is summoned by hotkey.
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 320, height: 240)

        return panel
    }
}
