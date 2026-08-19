import AppKit

/// The application menu.
///
/// Companion is an accessory app, so this menu bar is never drawn — which makes
/// it easy to assume it is not needed. It is: `NSApplication` dispatches key
/// equivalents by walking `mainMenu`, so without an Edit menu, ⌘A, ⌘C, ⌘V, ⌘X
/// and ⌘Z do nothing anywhere in the app. Every text field looks broken, and
/// nothing in the code says why.
enum MainMenu {
    static func install(into application: NSApplication) {
        let main = NSMenu()

        main.addItem(applicationMenu())
        main.addItem(editMenu())
        main.addItem(windowMenu())

        application.mainMenu = main
    }

    private static func submenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: title)
        build(menu)
        item.submenu = menu
        return item
    }

    private static func applicationMenu() -> NSMenuItem {
        submenu("Companion") { menu in
            menu.addItem(
                withTitle: "About Companion",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: ""
            )
            menu.addItem(.separator())
            menu.addItem(
                withTitle: "Hide Companion",
                action: #selector(NSApplication.hide(_:)),
                keyEquivalent: "h"
            )
            menu.addItem(.separator())
            menu.addItem(
                withTitle: "Quit Companion",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        }
    }

    /// The one that matters. These selectors travel the responder chain, so the
    /// web view handles them for whatever the user is typing in.
    private static func editMenu() -> NSMenuItem {
        submenu("Edit") { menu in
            menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")

            let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
            redo.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(redo)

            menu.addItem(.separator())
            menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

            let pasteMatch = NSMenuItem(
                title: "Paste and Match Style",
                action: #selector(NSTextView.pasteAsPlainText(_:)),
                keyEquivalent: "v"
            )
            pasteMatch.keyEquivalentModifierMask = [.command, .option, .shift]
            menu.addItem(pasteMatch)

            menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
            menu.addItem(
                withTitle: "Select All",
                action: #selector(NSText.selectAll(_:)),
                keyEquivalent: "a"
            )
        }
    }

    private static func windowMenu() -> NSMenuItem {
        submenu("Window") { menu in
            // ⌘W hides the panel rather than closing it — there is only one
            // window, and closing it would leave the app running with nothing
            // to show.
            menu.addItem(
                withTitle: "Close",
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
        }
    }
}
