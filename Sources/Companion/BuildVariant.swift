import Foundation

/// Which build this is.
///
/// A development build and an installed one are two different apps as far as
/// macOS is concerned — different bundle identifier, different name, different
/// permissions, different storage. Before this they shared everything except
/// the code signature, so testing a change wrote into the real conversations
/// and each held permissions the other could not use.
///
/// The same split every shipped app uses: VS Code Insiders, Firefox Nightly,
/// Chrome Canary. The icon differs too — if the two look identical in the menu
/// bar you eventually debug the wrong one.
enum BuildVariant {
    case development
    case release

    static var current: BuildVariant {
        let identifier = Bundle.main.bundleIdentifier ?? ""
        return identifier.hasSuffix(".dev") ? .development : .release
    }

    var isDevelopment: Bool { self == .development }

    /// The folder under Application Support. Taken from the bundle name so it
    /// can never drift from what the build actually is.
    var storageDirectoryName: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        return name ?? (isDevelopment ? "Companion Dev" : "Companion")
    }

    var displayName: String { isDevelopment ? "Companion Dev" : "Companion" }
}
