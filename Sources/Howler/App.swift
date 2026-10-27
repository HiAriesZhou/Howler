import AppKit

@main
enum HowlerApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no Dock icon (LSUIElement is also set in Info.plist)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
