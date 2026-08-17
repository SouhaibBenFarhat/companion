import CompanionCore
import Foundation

/// Runs one headless agent request and streams its output back.
///
/// Everything the panel shows comes through here. Callbacks are delivered on
/// the main queue so the caller can push straight into the web view.
final class AgentRunner {
    private var process: Process?
    private var outputBuffer = LineBuffer()
    private var errorText = ""

    var isRunning: Bool { process?.isRunning ?? false }

    /// - Parameters:
    ///   - onEvent: each decoded line, in order.
    ///   - onFinish: exit code plus anything the agent wrote to stderr. A
    ///     non-zero exit with empty stderr usually means the binary was found
    ///     but could not start — worth surfacing rather than swallowing.
    func run(
        command: AgentCommand,
        kind: AgentKind,
        onEvent: @escaping (AgentEvent) -> Void,
        onFinish: @escaping (Int32, String) -> Void
    ) {
        cancel()
        outputBuffer = LineBuffer()
        errorText = ""

        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = AgentLocator.searchPathValue(inheriting: environment["PATH"])
        // Ask for plain output: the agent has no terminal here, and colour
        // escape codes would end up rendered as text in the panel.
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        process.environment = environment

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        // Without this the agent can block forever waiting on a prompt it can
        // never receive, and the panel just spins with no explanation.
        process.standardInput = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

            let lines = self.outputBuffer.append(chunk)
            guard !lines.isEmpty else { return }
            let events = lines.flatMap { AgentEventDecoder.decode(line: $0, kind: kind) }
            guard !events.isEmpty else { return }
            DispatchQueue.main.async { events.forEach(onEvent) }
        }

        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.errorText += chunk }
        }

        process.terminationHandler = { [weak self] finished in
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                guard let self else { return }
                // A run can end without a trailing newline; that last line is
                // often the result event, so it must not be dropped.
                let trailing = self.outputBuffer.flush()
                    .flatMap { AgentEventDecoder.decode(line: $0, kind: kind) }
                trailing.forEach(onEvent)

                self.process = nil
                onFinish(finished.terminationStatus, self.errorText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            DispatchQueue.main.async {
                onFinish(-1, "Could not start \(command.executable.path): \(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        guard let process, process.isRunning else {
            self.process = nil
            return
        }
        process.terminationHandler = nil
        process.terminate()
        self.process = nil
    }
}
