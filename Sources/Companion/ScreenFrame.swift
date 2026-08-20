import AppKit
import CompanionCore
import Foundation
import ScreenCaptureKit

/// One still picture of a window, for the times text is not enough.
///
/// The last resort, not the default. Accessibility text is exact and free;
/// a frame costs real tokens and can be misread. This exists for the cases
/// where there is no text to read: a diagram, a rendered page, an Electron app
/// whose accessibility tree gives up nothing.
@available(macOS 14.0, *)
enum ScreenFrame {
    /// Long edge of the captured image.
    ///
    /// Small on purpose. Cost scales with pixels, and a model reads code from a
    /// downscaled window about as well as from a full one — while a
    /// full-resolution capture of a large display is several times the price.
    static let maximumEdge = 1_400

    enum FrameError: LocalizedError {
        case notPermitted
        case noWindow
        case captureFailed(String)

        var errorDescription: String? {
            switch self {
            case .notPermitted: return "Screen Recording permission is needed to look at the screen."
            case .noWindow: return "Could not find the window to capture."
            case .captureFailed(let reason): return "Could not capture the screen: \(reason)"
            }
        }
    }

    /// Captures the frontmost window of the frontmost app, as PNG data.
    ///
    /// The frontmost window rather than the whole display: it is what the user
    /// means by "look at this", it is a fraction of the pixels, and it cannot
    /// accidentally include a window they did not intend to share.
    static func captureFrontmostWindow() async throws -> Data {
        guard CGPreflightScreenCaptureAccess() else { throw FrameError.notPermitted }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        let ownPID = getpid()
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { throw FrameError.noWindow }

        // Companion's own panel is never a useful subject, and capturing it
        // would put the assistant's own answers back into its input.
        let candidates = content.windows.filter { window in
            window.owningApplication?.processID != ownPID
                && window.owningApplication?.processID == frontmost.processIdentifier
                && window.frame.width > 200
                && window.frame.height > 200
        }

        guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        else { throw FrameError.noWindow }

        let configuration = SCStreamConfiguration()
        let scale = min(
            1.0,
            Double(maximumEdge) / Double(max(window.frame.width, window.frame.height))
        )
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best

        let filter = SCContentFilter(desktopIndependentWindow: window)

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw FrameError.captureFailed("could not encode the image")
            }
            return data
        } catch let error as FrameError {
            throw error
        } catch {
            throw FrameError.captureFailed(error.localizedDescription)
        }
    }

    /// Writes a frame where the agent can read it.
    ///
    /// The agent reads files, so a path is all it needs. Kept in the temporary
    /// directory and overwritten each time, so screenshots of a work call do
    /// not accumulate anywhere permanent.
    static func writeToTemporary(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-screen.png")
        try data.write(to: url, options: .atomic)
        return url
    }
}
