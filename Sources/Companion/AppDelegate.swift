import AppKit
import CompanionCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelController: PanelController?
    private var hotKey: HotKey?

    private let settingsStore: JSONFileStore<Settings> = {
        let directory = StorageLocation.applicationSupportDirectory()
        return JSONFileStore(url: StorageLocation.settingsURL(in: directory), fallback: Settings())
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        setUpStatusItem()
        registerHotKey()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusIcon.make()
        item.button?.toolTip = "Companion"

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Companion", action: #selector(togglePanel), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())

        let repositoryItem = NSMenuItem(
            title: "Choose repo…",
            action: #selector(chooseRepository),
            keyEquivalent: ""
        )
        repositoryItem.target = self
        menu.addItem(repositoryItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Companion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() {
        panelController?.toggle()
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
