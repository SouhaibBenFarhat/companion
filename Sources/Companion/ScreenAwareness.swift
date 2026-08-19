import AppKit
import ApplicationServices
import CompanionCore
import Foundation

/// Watches what the user is looking at.
///
/// Event driven, never polled: the accessibility API will tell us when focus
/// moves, and asking repeatedly instead would mean hundreds of cross-process
/// messages a minute.
///
/// It runs on its own thread with a run loop. Two reasons, both learned the
/// hard way by other people: an accessibility read is a synchronous message to
/// another process, so doing it on the main thread means one busy app freezes
/// the panel — and an observer added to a plain dispatch queue never fires,
/// because it needs a run loop to deliver on.
final class ScreenAwareness {
    /// Called on the main queue when the picture has settled.
    var onContext: ((ScreenContext) -> Void)?

    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var observer: AXObserver?
    private var observedApplication: AXUIElement?
    private var observedPID: pid_t = 0

    private let debouncer = ContextDebouncer()
    private var debounceState = ContextDebouncer.State()
    private var repository: URL
    private(set) var isRunning = false

    /// How long to let one accessibility read take. Without a limit, a hung
    /// app hangs us with it.
    private static let messagingTimeout: Float = 0.25

    init(repository: URL) {
        self.repository = repository
    }

    deinit { stop() }

    func updateRepository(_ url: URL) {
        repository = url
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning, PermissionChecker.state(of: .accessibility) == .granted else { return }
        isRunning = true

        let thread = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()

            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
                self?.attach(to: app)
            }

            if let front = NSWorkspace.shared.frontmostApplication { self.attach(to: front) }

            // A plain queue has no run loop, and an observer added there never
            // delivers anything.
            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 0.25, false)
            }
        }
        thread.name = "companion.screen"
        thread.qualityOfService = .utility
        self.thread = thread
        thread.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        detach()

        thread?.cancel()
        if let runLoop { CFRunLoopStop(runLoop) }
        thread = nil
        runLoop = nil
    }

    // MARK: - Following the frontmost app

    private func attach(to app: NSRunningApplication) {
        detach()
        guard app.processIdentifier != getpid() else { return }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        observedApplication = element
        observedPID = app.processIdentifier

        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let awareness = Unmanaged<ScreenAwareness>.fromOpaque(context).takeUnretainedValue()
            awareness.changed()
        }

        guard AXObserverCreate(app.processIdentifier, callback, &newObserver) == .success,
              let created = newObserver
        else { return }
        observer = created

        let context = Unmanaged.passUnretained(self).toOpaque()
        // Window and focus changes only. Registering value changes on the
        // application element is a flood from any live page, and debouncing
        // removes the reads but not the cost of receiving them.
        for notification in [
            kAXFocusedWindowChangedNotification,
            kAXFocusedUIElementChangedNotification,
            kAXTitleChangedNotification,
            kAXApplicationActivatedNotification,
        ] {
            AXObserverAddNotification(created, element, notification as CFString, context)
        }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(created),
            .defaultMode
        )
        changed()
    }

    private func detach() {
        if let observer, let observedApplication {
            for notification in [
                kAXFocusedWindowChangedNotification,
                kAXFocusedUIElementChangedNotification,
                kAXTitleChangedNotification,
                kAXApplicationActivatedNotification,
            ] {
                AXObserverRemoveNotification(observer, observedApplication, notification as CFString)
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        observedApplication = nil
        observedPID = 0
    }

    // MARK: - Reading

    private func changed() {
        let now = Date().timeIntervalSinceReferenceDate
        switch debouncer.changed(at: now, state: &debounceState) {
        case .wait(let remaining):
            let deadline = DispatchTime.now() + remaining
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) { [weak self] in
                self?.changed()
            }
        case .report:
            let context = read()
            DispatchQueue.main.async { [weak self] in self?.onContext?(context) }
        }
    }

    private func read() -> ScreenContext {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return ScreenContext(appName: "")
        }

        var context = ScreenContext(
            appName: app.localizedName ?? "",
            bundleIdentifier: app.bundleIdentifier
        )

        guard let element = observedApplication else { return context }

        if let window = copyElement(element, kAXFocusedWindowAttribute) {
            context.windowTitle = copyString(window, kAXTitleAttribute)
            context.url = copyURL(window)
        }

        if let title = context.windowTitle,
           let name = WindowTitleParser.documentName(from: title) {
            context.filePath = WindowTitleParser.resolve(documentName: name, inRepository: repository)
        }

        if let focused = copyElement(element, kAXFocusedUIElementAttribute) {
            // Never read a password field, whatever else is true. The role
            // constant is not exposed to Swift, so the literal is used — it is
            // stable and documented.
            let role = copyString(focused, kAXRoleAttribute)
            if role != "AXSecureTextField" {
                context.selectionOrText = copyString(focused, kAXSelectedTextAttribute)
                    ?? copyString(focused, kAXValueAttribute)
            }
        }

        return context
    }

    // MARK: - Accessibility helpers

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let text = value as? String,
              !text.isEmpty
        else { return nil }
        return text
    }

    /// Browsers expose the page address on the window.
    private func copyURL(_ window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXURL" as CFString, &value) == .success,
              let value
        else { return nil }
        if let url = value as? URL { return url.absoluteString }
        if let text = value as? String { return text }
        return nil
    }
}
