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
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let saved = settings.panelOriginX.flatMap { x in
            settings.panelOriginY.map { CGRect(x: x, y: $0, width: size.width, height: size.height) }
        }
        let frame = saved.map { PanelPlacement.clamp(frame: $0, into: visible) }
            ?? PanelPlacement.defaultFrame(size: size, in: visible)

        panel = ChatPanel.make(contentRect: frame)
        super.init()

        controller.add(self, name: "companion")

        webView.autoresizingMask = [.width, .height]
        webView.frame = panel.contentLayoutRect
        // Let the page paint the background instead of a white flash on load.
        webView.setValue(false, forKey: "drawsBackground")

        // The window is borderless, so the rounded corner has to be clipped
        // here — otherwise the web view paints square corners over it.
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true

        panel.contentView?.addSubview(webView)
        panel.delegate = self

        load()
    }

    // MARK: - Showing and hiding

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let visible = NSScreen.main?.visibleFrame ?? panel.frame
        panel.setFrame(PanelPlacement.clamp(frame: panel.frame, into: visible), display: false)
        // Key, but never activating: the app you are presenting stays frontmost
        // while your typing comes here.
        panel.makeKeyAndOrderFront(nil)
        send(["type": "focus"])
    }

    func hide() {
        panel.orderOut(nil)
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

    // MARK: - State

    private func sendState() {
        let agentPath = AgentLocator.resolve(kind: settings.agent, configuredPath: settings.agentPath)?.path
        send([
            "type": "state",
            "busy": runner.isRunning,
            "agent": [
                "kind": settings.agent.rawValue,
                "title": settings.agent.title,
                "path": agentPath ?? "",
                "found": agentPath != nil,
            ],
            "settings": [
                "agent": settings.agent.rawValue,
                "agentPath": settings.agentPath,
                "repositoryPath": settings.defaultRepositoryPath,
                "permission": settings.permission.rawValue,
                "systemPrompt": settings.systemPrompt,
            ],
            "repository": settings.repositoryURL().path,
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
        let command = AgentCommandBuilder.build(
            kind: settings.agent,
            executable: executable,
            prompt: question,
            workingDirectory: settings.repositoryURL(),
            sessionID: current.agentSessionID,
            systemPrompt: settings.systemPrompt,
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
        var message = ""
        if failed {
            message = errorText.isEmpty
                ? "\(settings.agent.title) exited with code \(status)."
                : errorText
        }

        send(["type": "done", "isError": failed, "message": message])
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

        case "updateSettings":
            if let raw = body["agent"] as? String, let kind = AgentKind(rawValue: raw) { settings.agent = kind }
            if let path = body["agentPath"] as? String { settings.agentPath = path }
            if let raw = body["permission"] as? String, let value = AgentPermission(rawValue: raw) {
                settings.permission = value
            }
            if let prompt = body["systemPrompt"] as? String { settings.systemPrompt = prompt }
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
