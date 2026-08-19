import AppKit
import CompanionCore

/// Opens a terminal sitting at the agent's sign-in prompt.
///
/// The CLI has no `login` subcommand — signing in only happens inside its
/// interactive session, which needs a real terminal. So the button cannot log
/// you in; it can only put you in front of the thing that can.
///
/// Done with a `.command` file rather than AppleScript on purpose: telling
/// Terminal what to type would need Automation permission, and asking for that
/// to run one command is a worse trade than opening a file macOS already knows
/// how to run.
enum SignIn {
    static func openTerminal(agent: AgentKind, executable: URL?) {
        let directory = StorageLocation.applicationSupportDirectory()
        let script = directory.appendingPathComponent("sign-in.command")
        let binary = executable?.path ?? agent.executableName

        let contents = """
            #!/bin/bash
            # Written by Companion. Safe to delete.
            clear
            echo "Signing in to \(agent.title)."
            echo "Type /login, follow the browser, then close this window."
            echo
            exec "\(binary)"

            """

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try contents.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        } catch {
            SessionLog.shared.write("signin", "could not write script: \(error.localizedDescription)")
            return
        }

        SessionLog.shared.write("signin", "opening terminal for \(agent.rawValue)")
        // Companion is non-activating, so nothing would come forward on its own.
        NSWorkspace.shared.open(script)
        NSApp.activate(ignoringOtherApps: false)
    }
}
