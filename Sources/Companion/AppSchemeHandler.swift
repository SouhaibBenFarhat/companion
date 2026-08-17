import Foundation
import WebKit

/// Serves the built UI (user interface) from disk under `companion://app/`.
///
/// A custom scheme rather than `file://`. The page is a module script, and
/// module loading over `file://` runs into cross-origin rules that have nothing
/// to do with an app reading its own bundle — the page loads and every import
/// silently fails. Under a scheme we own, it is ordinary same-origin loading.
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "companion"
    static let indexURL = URL(string: "\(scheme)://app/index.html")!

    private let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let file = resolve(url) else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        guard let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: file.pathExtension),
                "Content-Length": String(data.count),
                "Cache-Control": "no-store",
            ]
        )!

        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// Maps a request path onto a file inside `root`, refusing anything that
    /// climbs out of it.
    private func resolve(_ url: URL) -> URL? {
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }

        let candidate = root
            .appendingPathComponent(path)
            .standardizedFileURL

        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            return nil
        }
        return candidate
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "map": return "application/json"
        default: return "application/octet-stream"
        }
    }
}
