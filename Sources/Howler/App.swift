import AppKit
import Foundation

@main
enum HowlerApp {
    @MainActor
    static func main() {
        // `Howler config …` / `Howler check` run in the terminal and exit without any UI.
        if let status = CLI.run(CommandLine.arguments) { exit(status) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no Dock icon (LSUIElement is also set in Info.plist)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
