import AppKit
import CompanionCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelController: PanelController?
    private var hotKey: HotKey?
    private var listeningMenuItem: NSMenuItem?

    private let settingsStore: JSONFileStore<Settings> = {
        let directory = StorageLocation.applicationSupportDirectory()
        return JSONFileStore(url: StorageLocation.settingsURL(in: directory), fallback: Settings())
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before the settings store is touched. A development build must not
        // read or write the installed app's conversations.
        StorageLocation.use(directoryName: BuildVariant.current.storageDirectoryName)

        // Before anything else: an accessory app never draws a menu bar, but
        // AppKit still routes ⌘A/⌘C/⌘V/⌘Z through it. Without this, editing
        // shortcuts are dead in every field.
        MainMenu.install(into: NSApplication.shared)

        let settings = settingsStore.load()

        panelController = PanelController(
            settings: settings,
            settingsStore: settingsStore,
            conversations: .inApplicationSupport()
        )
        panelController?.onSettingsChanged = { [weak self] in self?.registerHotKey() }

        // Taps and aggregate devices outlive the process that made them, so a
        // crash leaves them behind for the next launch to find.
        CallCapture.sweepOrphans()

        setUpStatusItem()
        registerHotKey()

        panelController?.onListeningChanged = { [weak self] in self?.refreshStatusItem() }
        panelController?.restoreVisibility()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Leaving a tap running would keep a recording indicator in the menu bar
    /// after Companion is gone.
    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stopListening()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusIcon.make(development: BuildVariant.current.isDevelopment)
        item.button?.toolTip = BuildVariant.current.displayName

        let menu = NSMenu()
        menu.addItem(withTitle: "Show \(BuildVariant.current.displayName)", action: #selector(togglePanel), keyEquivalent: "")
            .target = self

        let listenItem = NSMenuItem(
            title: "Start listening",
            action: #selector(toggleListening),
            keyEquivalent: ""
        )
        listenItem.target = self
        menu.addItem(listenItem)
        listeningMenuItem = listenItem

        menu.addItem(.separator())

        let repositoryItem = NSMenuItem(
            title: "Choose repo…",
            action: #selector(chooseRepository),
            keyEquivalent: ""
        )
        repositoryItem.target = self
        menu.addItem(repositoryItem)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit \(BuildVariant.current.displayName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() {
        panelController?.toggle()
    }

    @objc private func toggleListening() {
        panelController?.toggleListening()
    }

    /// The menu bar is the only place listening is visible when the panel is
    /// hidden, so it has to say which state it is in.
    private func refreshStatusItem() {
        let listening = panelController?.isListening ?? false
        let name = BuildVariant.current.displayName
        statusItem?.button?.image = StatusIcon.make(
            listening: listening,
            development: BuildVariant.current.isDevelopment
        )
        statusItem?.button?.toolTip = listening ? "\(name) — listening" : name
        listeningMenuItem?.title = listening ? "Stop listening" : "Start listening"
    }

    @objc private func chooseRepository() {
        panelController?.show()
        panelController?.requestRepositoryPicker()
    }

    // MARK: - Shortcut

    /// Re-registered whenever settings change, since the shortcut is one of
    /// the things settings can change.
    private func registerHotKey() {
        hotKey = nil
        let settings = settingsStore.load()
        hotKey = HotKey(
            keyCode: settings.hotKeyCode,
            modifiers: settings.hotKeyModifiers
        ) { [weak self] in
            self?.panelController?.toggle()
        }
    }
}
