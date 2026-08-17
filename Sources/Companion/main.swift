import AppKit

// Accessory app: lives in the menu bar with no Dock icon and no main menu.
// A Dock icon would be one more thing on screen while presenting, which is the
// opposite of the point.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
