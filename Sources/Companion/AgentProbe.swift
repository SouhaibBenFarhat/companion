import CompanionCore
import Foundation

/// Confirms an agent binary actually runs.
///
/// Finding the file is not the same as it working. A path can point at a
/// dangling symlink, a binary for the wrong architecture, or a Node script
/// whose Node has been uninstalled — all of which pass an "exists and is
/// executable" check and then fail the moment you ask a question.
///
/// So the file search proposes a candidate and this confirms it, by running
/// `--version` and seeing whether anything sensible comes back.
enum AgentProbe {
    /// Generous enough for a cold Node start, short enough not to stall the
    /// panel opening.
    static let timeout: TimeInterval = 8

    struct Result: Equatable {
        let path: String
        let version: String?
        var works: Bool { version != nil }
    }

    private static var cache: [String: Result] = [:]

    /// Cached per path, since this runs on every state refresh and the answer
    /// only changes when the binary does.
    static func cached(for path: String) -> Result? {
        cache[path]
    }

    static func forget() {
        cache = [:]
    }

    /// Runs `<binary> --version` off the main thread.
    static func probe(executable: URL, completion: @escaping (Result) -> Void) {
        let path = executable.path
        if let known = cache[path] {
            completion(known)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result(path: path, version: runVersion(executable))
            DispatchQueue.main.async {
                cache[path] = result
                SessionLog.shared.write(
                    "probe",
                    "\(path) -> \(result.version ?? "did not run")"
                )
                completion(result)
            }
        }
    }

    private static func runVersion(_ executable: URL) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.environment = AgentEnvironment.forAgent(inheriting: ProcessInfo.processInfo.environment)

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }

        // Read before waiting: a full pipe buffer would deadlock the child.
        let data = output.fileHandleForReading.readDataToEndOfFile()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
