import CompanionCore
import Foundation

/// One agent process, kept alive for the whole call.
///
/// The unprompted note used to spawn a fresh `claude` for every turn. Measured
/// on this Mac that costs about two seconds before the model has read a word —
/// a third of the delay, paid again on every line somebody speaks.
///
/// The CLI takes `--input-format stream-json`, which turns the process into a
/// conversation: write one JSON line per turn to its input, read one result per
/// turn from its output. Verified against the real CLI — two turns, two
/// results, one process.
///
/// The flags that cannot change mid-call are set once at launch: the system
/// prompt, the schema, the tools. Anything that changes per turn goes in the
/// message.
final class SuggestionSession {
    private var process: Process?
    private var input: FileHandle?
    private var buffer = LineBuffer()

    /// Waiting turns, oldest first. The CLI answers in the order it is asked,
    /// so a queue is enough and no correlation identifier is needed.
    private var waiting: [CheckedContinuation<String?, Never>] = []
    /// The object from the turn in flight, kept until its result arrives.
    private var structured: String?
    private var spoken = ""

    var isRunning: Bool { process?.isRunning ?? false }

    // MARK: - Lifecycle

    func start(
        executable: URL,
        workingDirectory: URL,
        systemPrompt: String,
        schema: String,
        environment: [String: String]
    ) {
        stop()

        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            // It reacts to a transcript it is handed. Reading anything is how a
            // note came back quoting a file on the user's Desktop.
            "--tools", "",
            "--append-system-prompt", systemPrompt,
            "--json-schema", schema,
        ]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        buffer = LineBuffer()
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in self?.consume(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            SessionLog.shared.write("suggest", "stderr: \(text.prefix(200))")
        }
        process.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async { [weak self] in self?.processEnded(status: ended.terminationStatus) }
        }

        do {
            try process.run()
            self.process = process
            self.input = inputPipe.fileHandleForWriting
            SessionLog.shared.write("suggest", "session started, one process for the call")
        } catch {
            SessionLog.shared.write("suggest", "could not start: \(error.localizedDescription)")
        }
    }

    func stop() {
        // Closing the input is what tells the CLI the conversation is over.
        try? input?.close()
        input = nil

        if let process, process.isRunning { process.terminate() }
        process = nil

        // Nobody is coming back to these.
        let pending = waiting
        waiting = []
        for continuation in pending { continuation.resume(returning: nil) }
    }

    // MARK: - Asking

    /// One turn. Returns the validated object, or nil when the session is not
    /// running or ended before answering.
    func ask(_ prompt: String) async -> String? {
        guard isRunning, let input else { return nil }

        let message: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": [["type": "text", "text": prompt]]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return nil }

        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            do {
                try input.write(contentsOf: data + Data("\n".utf8))
            } catch {
                SessionLog.shared.write("suggest", "could not write: \(error.localizedDescription)")
                waiting.removeLast()
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Reading

    private func consume(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        for line in buffer.append(chunk) {
            for event in AgentEventDecoder.decode(line: line, kind: .claude) {
                switch event {
                case .structuredOutput(let object): structured = object
                case .assistantText(let chunk): spoken += chunk
                case .finished: finishTurn()
                default: break
                }
            }
        }
    }

    private func finishTurn() {
        let answer = structured ?? (spoken.isEmpty ? nil : spoken)
        structured = nil
        spoken = ""

        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume(returning: answer)
    }

    private func processEnded(status: Int32) {
        SessionLog.shared.write("suggest", "session ended, status=\(status)")
        process = nil
        input = nil
        let pending = waiting
        waiting = []
        for continuation in pending { continuation.resume(returning: nil) }
    }
}
