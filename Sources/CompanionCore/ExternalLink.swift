import Foundation

/// Decides whether a link from an answer may be opened in the browser.
///
/// The text comes from an agent reading files off disk, so a link in it is not
/// trusted input. Only http and https leave the app: `file:` would open
/// anything on the machine, and `javascript:` would run in whatever opened it.
public enum ExternalLink {
    public static func url(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https" else { return nil }
        // A scheme with no host is not somewhere to go.
        guard let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
