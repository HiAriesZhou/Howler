import AppKit
import HowlerCore

/// "Send Feedback…": opens the feedback form on GitHub with the version, macOS and chip
/// filled in. Only the browser sees them, and only when the person asks.
enum Feedback {
    @MainActor
    static func open() {
        let version = AppInfo.build.map { "\(AppInfo.version) (\($0))" } ?? AppInfo.version
        let url = FeedbackLink.url(
            project: RequestBuilder.projectURL, version: version, macOS: macOSVersion, architecture: architecture
        )
        NSWorkspace.shared.open(url)
    }

    /// "26.5.2 (25F84)".
    private static var macOSVersion: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let number = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 1 else { return number }
        var build = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &build, &size, nil, 0) == 0 else { return number }
        return "\(number) (\(String(cString: build)))"
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
