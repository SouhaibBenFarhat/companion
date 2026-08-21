import AppKit
import CompanionCore
import WebKit

/// Owns the panel, the web view inside it, and the bridge between them.
///
/// The split is deliberate: Swift handles the window and the subprocess, the
/// web view handles rendering markdown and code. Messages cross in two places
/// only — `handle(message:)` coming in, `send(_:)` going out.
final class PanelController: NSObject {
    private let panel: ChatPanel
    private let webView: WKWebView
    private let runner = AgentRunner()
    private let awareness = AwarenessCoordinator()
    /// Separate from `runner`, so a suggestion Companion decided to make on its
    /// own can never cancel an answer the user actually asked for.
    private let suggestionRunner = AgentRunner()

    private var settings: Settings
    private let settingsStore: JSONFileStore<Settings>
    private let conversations: ConversationStore
    private let content: WebContent.Source?

    private var current: Conversation
    /// Text streamed for the answer in flight, flushed to the conversation when
    /// the run finishes. Keeping it separate means a cancelled run leaves no
    /// half-message behind in the saved history.
    private var pendingAnswer = ""
    private var isReady = false
    /// A screenshot to attach to the next question, taken on request.
    private var pendingScreenshot: URL?
    private var queued: [String] = []

    var onSettingsChanged: (() -> Void)?

    init(settings: Settings, settingsStore: JSONFileStore<Settings>, conversations: ConversationStore) {
        self.settings = settings
        self.settingsStore = settingsStore
        self.conversations = conversations

        let repository = settings.repositoryURL().path
        current = conversations.forRepository(repository).first
            ?? Conversation(repositoryPath: repository, agent: settings.agent)

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        configuration.userContentController = controller

        let content = WebContent.resolve()
        if case .local(_, let readAccess) = content {
            configuration.setURLSchemeHandler(
                AppSchemeHandler(root: readAccess),
                forURLScheme: AppSchemeHandler.scheme
            )
        }
        self.content = content
        webView = WKWebView(frame: .zero, configuration: configuration)

        let size = CGSize(width: settings.panelWidth, height: settings.panelHeight)
        let saved = settings.panelOriginX.flatMap { x in
            settings.panelOriginY.map { CGRect(x: x, y: $0, width: size.width, height: size.height) }
        }
        // The display the panel was last on, not the one holding the key
        // window. `NSScreen.main` is the latter, and this app is never
        // frontmost, so on two displays it was routinely the wrong answer —
        // which is how a laptop-sized panel came back sized for a monitor.
        let screens = NSScreen.screens.map(\.visibleFrame)
        let fallback = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = saved.flatMap { PanelPlacement.target(for: $0, among: screens) } ?? fallback
        let frame = saved.map { PanelPlacement.clamp(frame: $0, into: visible) }
            ?? PanelPlacement.defaultFrame(size: size, in: visible)

        panel = ChatPanel.make(contentRect: frame)
        super.init()

        controller.add(self, name: "companion")

        webView.autoresizingMask = [.width, .height]
        webView.frame = panel.contentLayoutRect
        // Let the page paint the background instead of a white flash on load,
        // and let the material below show through where the page is see-through.
        webView.setValue(false, forKey: "drawsBackground")

        // Vibrancy: the blurred, tinted view of whatever is behind the panel.
        let backdrop = NSVisualEffectView(frame: panel.contentLayoutRect)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        // Forced active rather than following the window. Companion is
        // deliberately never the frontmost app, so "follows window state" would
        // leave the material permanently dimmed — the one setting that makes
        // vibrancy look broken in a non-activating panel.
        backdrop.state = .active

        // The window is borderless, so the rounded corner has to be clipped
        // here — otherwise the material and web view paint square corners.
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 12
        backdrop.layer?.masksToBounds = true
        backdrop.maskImage = Self.cornerMask(radius: 12)

        panel.contentView = backdrop
        backdrop.addSubview(webView)
        panel.delegate = self

        // Unplugging a monitor, changing resolution, or switching a display's
        // arrangement all arrive here. Without it the panel keeps a geometry
        // that no longer exists anywhere.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToScreen() }
        }
        panel.isHiddenFromScreenShare = settings.hideFromScreenShare
        applyAppearance()

        awareness.updateRepository(settings.repositoryURL())
        awareness.preferredInputUID = settings.microphoneDeviceUID

        awareness.onLevels = { [weak self] levels in
            // Its own message, never through `state` — the page resets the
            // streamed answer on every state payload, so routing levels there
            // would wipe a half-drawn reply each time somebody spoke.
            self?.send(["type": "levels", "me": levels.me, "them": levels.them])
        }
        awareness.onError = { [weak self] message in
            self?.send(["type": "captureError", "message": message])
        }
        awareness.onTranscript = { [weak self] transcript in
            self?.send([
                "type": "transcript",
                "entries": transcript.entries.suffix(60).map { entry in
                    [
                        "id": entry.id,
                        "speaker": entry.speaker.rawValue,
                        "who": entry.speaker.title,
                        "text": entry.text,
                        "live": entry.isVolatile,
                    ]
                },
            ])
        }
        awareness.onStateChanged = { [weak self] in
            self?.onListeningChanged?()
            self?.sendState()
        }
        awareness.onScreen = { [weak self] context in
            self?.send([
                "type": "screen",
                "app": context.appName,
                "detail": context.filePath ?? context.url ?? context.windowTitle ?? "",
            ])
        }
        awareness.onTrigger = { [weak self] reason, line in
            self?.considerSpeaking(reason: reason, line: line)
        }

        load()
    }

    /// A resizable rounded-rectangle mask for the material.
    ///
    /// Layer corner radius alone does not round `NSVisualEffectView` — the blur
    /// is drawn outside the layer's clipping, so the corners come back square.
    /// A mask image is the supported way to shape it.
    private static func cornerMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: - Appearance

    /// Light, dark, or whatever macOS is doing.
    ///
    /// Set on the window, not on the page. The panel is a blurred AppKit
    /// material with a web view on top: the window's appearance drives that
    /// material AND the `prefers-color-scheme` the page reads, so the two
    /// cannot disagree. Styling the page alone would leave a light blur behind
    /// dark content.
    private func applyAppearance() {
        switch settings.theme {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Staying on screen

    /// The screen the panel is actually on.
    ///
    /// Not `NSScreen.main`: that is the screen holding the key window, and this
    /// app is deliberately never frontmost, so on a two-display setup it is
    /// routinely the wrong one.
    private var visibleFrame: CGRect? {
        (panel.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
    }

    /// Pulls the panel back inside its display, shrinking it if it no longer
    /// fits.
    ///
    /// A panel wider or taller than the screen is not merely untidy: its edges
    /// and its drag strip are off the display, so it cannot be resized and it
    /// cannot be moved. The only way out was to delete the settings file.
    /// Carrying a size from a large monitor to a laptop screen did exactly
    /// that.
    func fitToScreen(display: Bool = true) {
        guard let visible = visibleFrame else { return }
        let fitted = PanelPlacement.clamp(frame: panel.frame, into: visible)
        guard fitted != panel.frame else { return }
        panel.setFrame(fitted, display: display)
        rememberFrame()
    }

    // MARK: - Showing and hiding

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        fitToScreen(display: false)
        // Key, but never activating: the app you are presenting stays frontmost
        // while your typing comes here.
        panel.makeKeyAndOrderFront(nil)
        send(["type": "focus"])
        rememberVisibility(true)
    }

    func hide() {
        panel.orderOut(nil)
        rememberVisibility(false)
    }

    /// So a restart puts the panel back where it was.
    private func rememberVisibility(_ visible: Bool) {
        guard settings.panelWasVisible != visible else { return }
        settings.panelWasVisible = visible
        try? settingsStore.save(settings)
    }

    /// Reopens the panel if it was open when Companion last quit.
    func restoreVisibility() {
        guard settings.panelWasVisible else { return }
        show()
    }

    // MARK: - Web view

    private func load() {
        switch content {
        case .remote(let url):
            webView.load(URLRequest(url: url))
        case .local:
            webView.load(URLRequest(url: AppSchemeHandler.indexURL))
        case nil:
            let message = "The interface was not built. Run: npm --prefix web install && npm --prefix web run build"
            webView.loadHTMLString(
                "<body style=\"font:13px -apple-system;padding:24px;color:#888\">\(message)</body>",
                baseURL: nil
            )
        }
    }

    private func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return }

        // The page may not have loaded yet on first launch; hold messages
        // rather than dropping them, or the first state never arrives.
        guard isReady else {
            queued.append(json)
            return
        }
        webView.evaluateJavaScript("window.__companion && window.__companion.receive(\(json))")
    }

    private func flushQueue() {
        let pending = queued
        queued = []
        for json in pending {
            webView.evaluateJavaScript("window.__companion && window.__companion.receive(\(json))")
        }
    }

    // MARK: - Listening

    var isListening: Bool { awareness.isListening }
    var onListeningChanged: (() -> Void)?

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    func startListening() {
        let permissions = PermissionChecker.report()
        PermissionChecker.log("listen requested")
        guard permissions.canListen else {
            send(["type": "captureError", "message": permissions.summary])
            showSettingsTab()
            return
        }

        settings.awareness.enabled = true
        persistSettings()
        awareness.start(settings: settings.awareness)
    }

    func stopListening() {
        awareness.stop()
        settings.awareness.enabled = false
        persistSettings()
    }

    /// Something happened worth thinking about. Ask the agent, and show the
    /// answer only if it is worth interrupting for.
    private func considerSpeaking(reason: TurnReason, line: String) {
        // Two switches, not one. Listening is useful with Companion silent.
        guard settings.awareness.enabled, settings.awareness.suggestionsEnabled else { return }
        // Never while the user is waiting on an answer they asked for, and
        // never on top of a suggestion already in flight.
        guard !runner.isRunning, !suggestionRunner.isRunning else { return }
        guard let executable = AgentLocator.resolve(kind: settings.agent, configuredPath: settings.agentPath)
        else { return }

        let spoken = awareness.transcript.text(lastSeconds: 120)
        let screen = awareness.screenContext?.summary ?? ""
        let prompt = AwarenessPrompt.build(
            question: "The last thing said was: \"\(line)\"",
            conversation: spoken,
            screen: screen
        )

        let command = AgentCommandBuilder.build(
            kind: settings.agent,
            executable: executable,
            prompt: prompt,
            workingDirectory: settings.repositoryURL(),
            sessionID: nil,
            systemPrompt: AgentContext.systemPrompt(
                repository: settings.repositoryURL(),
                hasRepository: settings.hasRepository,
                isListening: true,
                watching: AwarenessPrompt.watchingInstruction
            ),
            permission: .readOnly
        )

        var answer = ""
        SessionLog.shared.write("suggest", "thinking, reason=\(reason.rawValue)")
        suggestionRunner.run(
            command: command,
            kind: settings.agent,
            onEvent: { event in
                if case .assistantText(let chunk) = event { answer += chunk }
            },
            onFinish: { [weak self] _, _ in
                guard let self else { return }
                let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard self.awareness.admitSuggestion(text) else { return }
                // Kept only if the user allows the transcript to be stored.
                // Otherwise it is shown and forgotten, which is what "do not
                // persist" has to mean or the setting is decoration.
                if self.settings.awareness.persistTranscript {
                    self.current.append(Message(role: .assistant, text: text))
                    try? self.conversations.save(self.current)
                }
                self.send([
                    "type": "suggestion",
                    "text": text,
                    "reason": reason.rawValue,
                ])
            }
        )
    }

    /// Takes one picture of the window in front, for the next question.
    ///
    /// On request only. Accessibility text is exact and free, so pixels are for
    /// the cases with no text to read — a diagram, a rendered page, an app whose
    /// accessibility tree gives up nothing.
    private func captureScreen() {
        guard #available(macOS 14.0, *) else { return }
        send(["type": "screenshot", "state": "capturing"])

        Task { @MainActor in
            do {
                let data = try await ScreenFrame.captureFrontmostWindow()
                let url = try ScreenFrame.writeToTemporary(data)
                pendingScreenshot = url
                SessionLog.shared.write("screenshot", "captured \(data.count) bytes")
                send([
                    "type": "screenshot",
                    "state": "ready",
                    "name": awareness.screenContext?.appName ?? "the screen",
                ])
            } catch {
                pendingScreenshot = nil
                send([
                    "type": "screenshot",
                    "state": "failed",
                    "message": error.localizedDescription,
                ])
            }
        }
    }

    func discardScreenshot() {
        if let pendingScreenshot { try? FileManager.default.removeItem(at: pendingScreenshot) }
        pendingScreenshot = nil
        send(["type": "screenshot", "state": "none"])
    }

    private func showSettingsTab() {
        show()
        send(["type": "openSettings"])
    }

    // MARK: - State

    private func sendState() {
        let resolved = AgentLocator.resolve(kind: settings.agent, configuredPath: settings.agentPath)
        let agentPath = resolved?.path

        // Confirm the binary runs, not just that a file is there. The first
        // answer arrives asynchronously and refreshes the panel.
        if let resolved, AgentProbe.cached(for: resolved.path) == nil {
            AgentProbe.probe(executable: resolved) { [weak self] _ in self?.sendState() }
        }
        let probe = resolved.flatMap { AgentProbe.cached(for: $0.path) }

        let permissions = PermissionChecker.report()
        send([
            "type": "state",
            "busy": runner.isRunning,
            "agent": [
                "kind": settings.agent.rawValue,
                "title": settings.agent.title,
                "path": agentPath ?? "",
                // Optimistic until the probe answers: reporting "not found"
                // for the second it takes would flash a false error.
                "found": agentPath != nil && (probe?.works ?? true),
                "version": probe?.version ?? "",
                "checked": probe != nil,
            ],
            "settings": [
                "agent": settings.agent.rawValue,
                "agentPath": settings.agentPath,
                "repositoryPath": settings.defaultRepositoryPath,
                "permission": settings.permission.rawValue,
                "systemPrompt": settings.systemPrompt,
                "suggestionsEnabled": settings.awareness.suggestionsEnabled,
                "persistTranscript": settings.awareness.persistTranscript,
                "microphoneDeviceUID": settings.microphoneDeviceUID,
                "hideFromScreenShare": settings.hideFromScreenShare,
                "theme": settings.theme.rawValue,
                "hasRepository": settings.hasRepository,
                "microphoneMissing": AudioInputSelection.isPreferredMissing(
                    preferredUID: settings.microphoneDeviceUID,
                    available: AudioDevices.inputs()
                ),
            ],
            "repository": settings.repositoryURL().path,
            "inputDevices": AudioDevices.inputs().map { device in
                [
                    "uid": device.uid,
                    "name": device.name,
                    "isSystemDefault": device.isSystemDefault,
                ]
            },
            "listening": [
                "active": awareness.isListening,
                "callApp": awareness.callAppName ?? "",
            ],
            "permissions": [
                "canListen": permissions.canListen,
                "canSeeScreen": permissions.canSeeScreen,
                "isReady": permissions.isReady,
                "summary": permissions.summary,
                "next": permissions.nextToRequest?.rawValue ?? "",
                "items": Permission.allCases.map { permission in
                    [
                        "id": permission.rawValue,
                        "title": permission.title,
                        "reason": permission.reason,
                        "state": permissions.state(of: permission).rawValue,
                        "needsRestart": permission.needsRestartAfterGranting,
                        "resetCommand": permission.resetCommand(
                            bundleIdentifier: Bundle.main.bundleIdentifier ?? ""
                        ),
                    ]
                },
            ],
            "currentId": current.id,
            "conversations": conversations
                .forRepository(settings.repositoryURL().path)
                .map { ["id": $0.id, "title": $0.title.isEmpty ? "New conversation" : $0.title] },
            "messages": current.messages.map {
                ["id": $0.id, "role": $0.role.rawValue, "text": $0.text]
            },
        ])
    }

    private func persistSettings() {
        try? settingsStore.save(settings)
        onSettingsChanged?()
    }

    // MARK: - Asking

    private func ask(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !runner.isRunning else { return }

        guard let executable = AgentLocator.resolve(kind: settings.agent, configuredPath: settings.agentPath) else {
            send([
                "type": "done",
                "isError": true,
                "message": "\(settings.agent.title) was not found. Install it, or set the path in Settings.",
            ])
            return
        }

        current.append(Message(role: .user, text: question))
        try? conversations.save(current)
        sendState()

        pendingAnswer = ""
        // Only what the agent has not been given yet. Resending the whole
        // transcript each turn would grow every question without adding
        // anything, since the session already remembers what it was told.
        let spoken = awareness.isListening ? awareness.transcript.unsentText() : ""
        var screen = awareness.screenContext?.summary ?? ""
        if let shot = pendingScreenshot {
            // A path, not the image. The agent reads files, so this costs
            // nothing until it decides it needs to look.
            screen += screen.isEmpty ? "" : "\n"
            screen += "Screenshot of the current window: \(shot.path)"
        }
        let prompt = AwarenessPrompt.build(question: question, conversation: spoken, screen: screen)
        if !spoken.isEmpty { awareness.markTranscriptSent() }
        // One question, one picture. Keeping it would silently attach a stale
        // screen to everything after it.
        pendingScreenshot = nil

        let command = AgentCommandBuilder.build(
            kind: settings.agent,
            executable: executable,
            prompt: prompt,
            workingDirectory: settings.repositoryURL(),
            sessionID: current.agentSessionID,
            systemPrompt: AgentContext.systemPrompt(
                repository: settings.repositoryURL(),
                hasRepository: settings.hasRepository,
                isListening: isListening,
                watching: isListening ? AwarenessPrompt.watchingInstruction : "",
                extra: settings.systemPrompt
            ),
            permission: settings.permission
        )

        send(["type": "busy", "busy": true])
        runner.run(
            command: command,
            kind: settings.agent,
            onEvent: { [weak self] event in self?.handle(event) },
            onFinish: { [weak self] status, errorText in self?.finish(status: status, errorText: errorText) }
        )
    }

    private func handle(_ event: AgentEvent) {
        switch event {
        case .sessionStarted(let id):
            // Storing this is what makes "no, do it the other way" work: the
            // next question resumes an agent that still remembers what it read.
            current.agentSessionID = id
            try? conversations.save(current)

        case .assistantText(let text):
            pendingAnswer += text
            send(["type": "delta", "text": text])

        case .toolUse(let name):
            send(["type": "tool", "name": name])

        case .finished(let result, let isError):
            if pendingAnswer.isEmpty, let result, !result.isEmpty, !isError {
                pendingAnswer = result
                send(["type": "delta", "text": result])
            }
        }
    }

    private func finish(status: Int32, errorText: String) {
        let answer = pendingAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingAnswer = ""

        if !answer.isEmpty {
            current.append(Message(role: .assistant, text: answer))
            try? conversations.save(current)
        }

        let failed = status != 0
        if failed, answer.isEmpty {
            // The session the agent opened produced nothing usable. Keeping its
            // id would make every later message resume a dead conversation.
            current.agentSessionID = nil
            try? conversations.save(current)
        }

        var message = ""
        if failed {
            message = errorText.isEmpty
                ? "\(settings.agent.title) exited with code \(status)."
                : errorText
        }

        send([
            "type": "done",
            "isError": failed,
            "message": message,
            // Lets the panel offer a Sign in button without matching on words.
            "code": runner.failure?.code ?? "",
        ])
        sendState()
    }

    // MARK: - Repository picking

    /// Called from the menu bar, which has no page behind it to send a message.
    func requestRepositoryPicker() {
        pickRepository()
    }

    private func pickRepository() {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.allowsMultipleSelection = false
        open.prompt = "Use this repo"
        open.directoryURL = settings.repositoryURL()

        // The picker is a normal window, so the app has to come forward for it.
        NSApp.activate(ignoringOtherApps: true)
        guard open.runModal() == .OK, let url = open.url else { return }

        settings.defaultRepositoryPath = url.path
        persistSettings()
        awareness.updateRepository(url)
        current = conversations.forRepository(url.path).first
            ?? Conversation(repositoryPath: url.path, agent: settings.agent)
        sendState()
    }
}

// MARK: - Messages from the page

extension PanelController: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }

        switch type {
        case "ready":
            isReady = true
            flushQueue()
            sendState()

        case "ask":
            ask(body["text"] as? String ?? "")

        case "cancel":
            runner.cancel()
            send(["type": "done", "isError": false, "message": ""])

        case "hide":
            hide()

        case "drag":
            // The web view eats the mouse events AppKit would use to move the
            // window, so the header reports movement and we move it here.
            // Screen Y grows upward on macOS and downward in the page, hence
            // the flipped sign.
            guard let dx = body["dx"] as? Double, let dy = body["dy"] as? Double else { return }
            let moved = panel.frame.offsetBy(dx: dx, dy: -dy)
            panel.setFrameOrigin(moved.origin)
            rememberFrame()

        case "dragEnd":
            // Only once the pointer is up. Clamping on every step would pin the
            // panel to the display it started on, and you could never drag it
            // to another one.
            fitToScreen()

        case "newConversation":
            runner.cancel()
            current = Conversation(repositoryPath: settings.repositoryURL().path, agent: settings.agent)
            sendState()

        case "selectConversation":
            guard let id = body["id"] as? String, let loaded = conversations.load(id: id) else { return }
            runner.cancel()
            current = loaded
            sendState()

        case "deleteConversation":
            guard let id = body["id"] as? String else { return }
            try? conversations.delete(id: id)
            if current.id == id {
                current = Conversation(repositoryPath: settings.repositoryURL().path, agent: settings.agent)
            }
            sendState()

        case "pickRepository":
            pickRepository()

        case "requestPermission":
            guard let raw = body["id"] as? String, let permission = Permission(rawValue: raw) else { return }
            PermissionChecker.request(permission) { [weak self] _ in self?.sendState() }

        case "openPermissionSettings":
            guard let raw = body["id"] as? String, let permission = Permission(rawValue: raw) else { return }
            PermissionChecker.openSettings(for: permission)

        case "toggleListening":
            toggleListening()

        case "lookAtScreen":
            captureScreen()

        case "relaunch":
            // Accessibility and Screen Recording are read once, at launch. A
            // grant made while the app is running reaches nothing, and no
            // amount of checking again will pick it up — so the panel offers
            // the only thing that works instead of describing it.
            let url = Bundle.main.bundleURL
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            SessionLog.shared.write("panel", "relaunching for permissions")
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }

        case "refreshPermissions":
            // Cheap, and the only way to notice a grant made in System Settings
            // while the panel was open.
            sendState()

        case "openLink":
            // A link in an answer must not navigate the panel. There is no
            // address bar and no back button here, so following one inside the
            // web view loses the conversation with no way back.
            guard let raw = body["url"] as? String, let url = ExternalLink.url(from: raw) else { return }
            NSWorkspace.shared.open(url)

        case "signIn":
            SignIn.openTerminal(
                agent: settings.agent,
                executable: AgentLocator.resolve(kind: settings.agent, configuredPath: settings.agentPath)
            )

        case "updateSettings":
            if let raw = body["agent"] as? String, let kind = AgentKind(rawValue: raw) { settings.agent = kind }
            if let path = body["agentPath"] as? String { settings.agentPath = path }
            if let raw = body["permission"] as? String, let value = AgentPermission(rawValue: raw) {
                settings.permission = value
            }
            if let prompt = body["systemPrompt"] as? String { settings.systemPrompt = prompt }
            if let value = body["suggestionsEnabled"] as? Bool { settings.awareness.suggestionsEnabled = value }

            if let uid = body["microphoneDeviceUID"] as? String, uid != settings.microphoneDeviceUID {
                settings.microphoneDeviceUID = uid
                awareness.preferredInputUID = uid
                // A device cannot be swapped underneath a running engine, so a
                // change while listening restarts capture.
                if awareness.isListening {
                    stopListening()
                    startListening()
                }
            }

            if let raw = body["theme"] as? String, let theme = Appearance(rawValue: raw), theme != settings.theme {
                settings.theme = theme
                applyAppearance()
            }
            if let value = body["hideFromScreenShare"] as? Bool, value != settings.hideFromScreenShare {
                settings.hideFromScreenShare = value
                panel.isHiddenFromScreenShare = value
                SessionLog.shared.write("panel", "hidden from screen share: \(value)")
            }
            AgentProbe.forget()
            persistSettings()
            sendState()

        default:
            break
        }
    }
}

// MARK: - Remembering where the panel was

extension PanelController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) { rememberFrame() }
    func windowDidResize(_ notification: Notification) { rememberFrame() }

    func windowDidResignKey(_ notification: Notification) {
        // Deliberately does nothing. Hiding on focus loss would make the panel
        // vanish the moment you click back into the code you are pairing on.
    }

    private func rememberFrame() {
        settings.panelOriginX = panel.frame.minX
        settings.panelOriginY = panel.frame.minY
        settings.panelWidth = panel.frame.width
        settings.panelHeight = panel.frame.height
        try? settingsStore.save(settings)
    }
}
