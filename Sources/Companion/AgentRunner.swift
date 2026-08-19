import CompanionCore
import Foundation

/// Runs one headless agent request and streams its output back.
///
/// Everything the panel shows comes through here. Callbacks are delivered on
/// the main queue so the caller can push straight into the web view.
///
/// All mutable state is guarded by `state`. Output arrives on a pipe queue, the
/// deadline fires on another, and the panel reads from main — three writers is
/// how a crash that only happens during a call gets written.
final class AgentRunner {
    /// How long to wait before giving up on a run.
    ///
    /// Longer than it looks like it should be. The CLI retries a failed request
    /// about eleven times before reporting it, which takes over three minutes —
    /// a shorter deadline killed it moments before the real error arrived, and
    /// turned a clear "your login expired" into a silent timeout.
    ///
    /// Most failures never reach this, because `watchForFailure` catches them
    /// from the debug file within seconds.
    static let timeout: TimeInterval = 300

    /// How often to check the agent's debug file while a run is in flight.
    static let diagnosticInterval: TimeInterval = 2

    /// Guards everything below it. Never blocks on the main queue.
    private let state = DispatchQueue(label: "companion.agent.state")

    private var process: Process?
    private var outputBuffer = LineBuffer()
    private var errorText = ""
    private var deadline: DispatchWorkItem?
    private var diagnosticTimer: DispatchSourceTimer?
    /// Held so cancel() can detach the handlers. Only the termination handler
    /// cleared them before, which never runs on a cancelled run.
    private var openPipes: [Pipe] = []
    private var timedOut = false
    private var diagnosed: AgentFailure?

    var isRunning: Bool {
        state.sync { process?.isRunning ?? false }
    }

    var failure: AgentFailure? {
        state.sync { diagnosed }
    }

    /// - Parameters:
    ///   - onEvent: each decoded line, in order.
    ///   - onFinish: exit code plus a reason. A non-zero exit with nothing to
    ///     say usually means the binary was found but could not start.
    func run(
        command: AgentCommand,
        kind: AgentKind,
        onEvent: @escaping (AgentEvent) -> Void,
        onFinish: @escaping (Int32, String) -> Void
    ) {
        cancel()

        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory
        process.environment = AgentEnvironment.forAgent(inheriting: ProcessInfo.processInfo.environment)

        logSpawn(command)

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        // The prompt goes here rather than in the arguments, where `ps` would
        // show the whole call transcript to every process on the machine.
        // Closed straight after writing, so the agent never waits on more input.
        if let prompt = command.standardInput {
            let input = Pipe()
            process.standardInput = input
            DispatchQueue.global(qos: .userInitiated).async {
                input.fileHandleForWriting.write(Data(prompt.utf8))
                try? input.fileHandleForWriting.close()
            }
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        state.sync {
            self.openPipes = [output, errors]
            self.outputBuffer = LineBuffer()
            self.errorText = ""
            self.timedOut = false
            self.diagnosed = nil
        }

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

            let lines = self.state.sync { self.outputBuffer.append(chunk) }
            guard !lines.isEmpty else { return }

            let events = lines.flatMap {
                AgentEventDecoder.decode(line: $0, kind: kind, partialMessages: kind == .claude)
            }
            guard !events.isEmpty else { return }

            for case .sessionStarted(let id) in events {
                self.watchForFailure(sessionID: id, kind: kind)
            }
            // Types and sizes only. The text itself is the user's conversation
            // and their code, and this file gets pasted into issues.
            SessionLog.shared.write("out", Self.summarise(events))
            DispatchQueue.main.async { events.forEach(onEvent) }
        }

        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            self.state.sync { self.errorText += chunk }
        }

        process.terminationHandler = { [weak self] finished in
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            guard let self else { return }
            self.state.sync { self.openPipes = [] }

            let (trailingLines, stderrText, wasTimeout, found) = self.state.sync {
                () -> ([String], String, Bool, AgentFailure?) in
                self.deadline?.cancel()
                self.deadline = nil
                self.diagnosticTimer?.cancel()
                self.diagnosticTimer = nil
                self.process = nil
                return (
                    self.outputBuffer.flush(),
                    self.errorText.trimmingCharacters(in: .whitespacesAndNewlines),
                    self.timedOut,
                    self.diagnosed
                )
            }

            // A run can end without a trailing newline; that last line is often
            // the result event, so it must not be dropped.
            let trailing = trailingLines.flatMap {
                AgentEventDecoder.decode(line: $0, kind: kind, partialMessages: kind == .claude)
            }

            var reported: String
            if let found {
                // A diagnosed failure beats both stderr and the timeout text:
                // it is the only one that says what to do about it.
                reported = found.message
            } else if wasTimeout {
                reported = """
                    The agent did not answer within \(Int(Self.timeout)) seconds and was stopped. \
                    Check that the agent CLI is signed in.
                    """
            } else {
                reported = Redaction.scrub(stderrText)
            }

            let failed = wasTimeout || found != nil || finished.terminationStatus != 0
            SessionLog.shared.write(
                "exit",
                "status=\(finished.terminationStatus) timedOut=\(wasTimeout) diagnosed=\(found?.code ?? "none")"
            )

            DispatchQueue.main.async {
                trailing.forEach(onEvent)
                onFinish(
                    (wasTimeout || found != nil) ? -2 : finished.terminationStatus,
                    failed ? reported : ""
                )
            }
        }

        do {
            try process.run()

            let deadline = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let running: Process? = self.state.sync {
                    guard self.process?.isRunning == true else { return nil }
                    self.timedOut = true
                    return self.process
                }
                running?.terminate()
            }
            state.sync {
                self.process = process
                self.deadline = deadline
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.timeout, execute: deadline)
        } catch {
            SessionLog.shared.write("spawn", "failed to start: \(error.localizedDescription)")
            DispatchQueue.main.async {
                onFinish(-1, "Could not start \(command.executable.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        let running: Process? = state.sync {
            // Detach first. A handler left installed keeps firing against a
            // dead process and keeps this object alive with it.
            for pipe in self.openPipes {
                pipe.fileHandleForReading.readabilityHandler = nil
            }
            self.openPipes = []
            self.diagnosticTimer?.cancel()
            self.diagnosticTimer = nil
            self.deadline?.cancel()
            self.deadline = nil
            defer { self.process = nil }
            guard let process = self.process, process.isRunning else { return nil }
            process.terminationHandler = nil
            return process
        }
        running?.terminate()
    }

    // MARK: - Logging

    /// Flag names and counts, never values.
    ///
    /// The arguments carry the user's question and their system prompt. Writing
    /// them down put a verbatim copy of every conversation in a file, which is
    /// the opposite of what a local-only tool should do.
    private func logSpawn(_ command: AgentCommand) {
        let flags = command.arguments.filter { $0.hasPrefix("--") || $0 == "-p" }
        SessionLog.shared.write(
            "spawn",
            "\(command.executable.lastPathComponent) flags=[\(flags.joined(separator: " "))] "
                + "promptChars=\(command.standardInput?.count ?? 0) "
                + "cwd=\(command.workingDirectory.lastPathComponent)"
        )
    }

    private static func summarise(_ events: [AgentEvent]) -> String {
        var text = 0
        var tools: [String] = []
        var other: [String] = []

        for event in events {
            switch event {
            case .assistantText(let chunk): text += chunk.count
            case .toolUse(let name): tools.append(name)
            case .sessionStarted: other.append("session")
            case .finished(_, let isError): other.append(isError ? "finished(error)" : "finished")
            }
        }

        var parts: [String] = []
        if text > 0 { parts.append("text=\(text)chars") }
        if !tools.isEmpty { parts.append("tools=[\(tools.joined(separator: ","))]") }
        parts.append(contentsOf: other)
        return parts.joined(separator: " ")
    }

    // MARK: - Diagnosis

    /// Polls the agent's own debug file for a failure it has not reported yet.
    ///
    /// Only Claude Code writes one of these, so this is best effort — nothing
    /// depends on it, it just turns a three-minute silence into a few seconds.
    private func watchForFailure(sessionID: String, kind: AgentKind) {
        guard kind == .claude else { return }

        let timer: DispatchSourceTimer? = state.sync {
            guard self.diagnosticTimer == nil else { return nil }
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            self.diagnosticTimer = timer
            return timer
        }
        guard let timer else { return }

        timer.schedule(deadline: .now() + Self.diagnosticInterval, repeating: Self.diagnosticInterval)
        timer.setEventHandler { [weak self] in
            guard let self,
                  let found = AgentDiagnostics.inspect(sessionID: sessionID),
                  found.isFatal
            else { return }

            let running: Process? = self.state.sync {
                guard self.diagnosed == nil else { return nil }
                self.diagnosed = found
                self.diagnosticTimer?.cancel()
                self.diagnosticTimer = nil
                return self.process
            }
            guard running != nil else { return }

            SessionLog.shared.write("diagnose", "\(found.code) — stopping early")
            running?.terminate()
        }
        timer.resume()
    }
}
