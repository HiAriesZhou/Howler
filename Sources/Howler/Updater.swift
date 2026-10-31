import AppKit
import Combine
import Sparkle

/// Sparkle behind one object. Updates come from the appcast attached to the latest GitHub
/// Release (`SUFeedURL`), signed with the key in `SUPublicEDKey`; Sparkle checks the EdDSA
/// signature and the Developer ID before it installs anything, and asks first: silent
/// automatic installs are off (`SUAllowsAutomaticUpdates`).
///
/// Howler lives in the menu bar, so a scheduled check that finds an update doesn't pop a
/// window over whatever you're doing: it raises a gentle reminder instead (`available`),
/// shown in the menu and in Settings, until you open it.
@MainActor
final class Updater: NSObject, ObservableObject {
    /// A newer version found by a scheduled check, waiting for you to look at it.
    @Published private(set) var available: String?
    @Published private(set) var canCheck = false
    @Published private(set) var checksAutomatically = false

    /// Off when the running copy carries no feed, e.g. `swift run` outside a bundle, where
    /// Sparkle would only complain.
    private(set) var isEnabled = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil

    private var core: SPUUpdater?
    private var userDriver: UpdateUserDriver?
    private var observers: [NSKeyValueObservation] = []

    override init() {
        super.init()
        #if DEBUG
        // Demo: HOWLER_DEMO_UPDATE=1 shows the update row; =0.1.9 also shows a reminder for 0.1.9.
        if let demo = ProcessInfo.processInfo.environment["HOWLER_DEMO_UPDATE"] {
            isEnabled = true
            canCheck = true
            checksAutomatically = true
            available = demo.contains(".") ? demo : nil
            return
        }
        #endif
        guard isEnabled else { return }
        let userDriver = UpdateUserDriver(standard: SPUStandardUserDriver(hostBundle: .main, delegate: self))
        userDriver.onAvailable = { [weak self] version in self?.available = version }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: userDriver, delegate: nil)
        self.userDriver = userDriver
        core = updater
        observers = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.checksAutomatically = updater.automaticallyChecksForUpdates }
            },
        ]
        do {
            try updater.start()
        } catch {
            isEnabled = false
            userDriver.showUpdaterError(error, acknowledgement: {})
        }
    }

    /// Looks for an update now, or shows the one the reminder is about.
    func checkForUpdates() {
        guard let core else { return }
        // An accessory app must come forward for Sparkle's window to take focus.
        NSApp.activate()
        core.checkForUpdates()
    }

    func installAvailableUpdate() {
        guard canCheck, available != nil else { return }
        NSApp.activate()
        userDriver?.installAvailableUpdate()
    }

    func setChecksAutomatically(_ enabled: Bool) {
        core?.automaticallyChecksForUpdates = enabled
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Ordinary scheduled offers wait in UpdateUserDriver. Offers routed to the standard
    /// UI (manual checks, informational notices and major upgrades) must remain visible.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        true
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { available = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { available = nil }
    }
}
