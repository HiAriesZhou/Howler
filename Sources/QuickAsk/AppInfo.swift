import Foundation

/// App identity, read from the bundle's Info.plist, which `scripts/bundle.sh` generates
/// from `app.config` — the single place to rename the app. The fallbacks only apply when
/// running the bare executable (e.g. `swift run`) outside a bundle.
enum AppInfo {
    static var name: String {
        string(for: "CFBundleDisplayName") ?? string(for: "CFBundleName") ?? "QuickAsk"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "io.github.hiarieszhou.quickask"
    }

    static var version: String {
        string(for: "CFBundleShortVersionString") ?? "dev"
    }

    private static func string(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            return nil
        }
        return value
    }
}
