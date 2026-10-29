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

    private var controller: SPUStandardUpdaterController?
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
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        observers = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.checksAutomatically = updater.automaticallyChecksForUpdates }
            },
        ]
    }

    /// Looks for an update now, or shows the one the reminder is about.
    func checkForUpdates() {
        guard let controller else { return }
        // An accessory app must come forward for Sparkle's window to take focus.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    func setChecksAutomatically(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows a scheduled update itself only when Howler already has your attention;
    /// otherwise the reminder waits in the menu and Settings.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            if !handleShowingUpdate && !state.userInitiated { available = version }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { available = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { available = nil }
    }
}
