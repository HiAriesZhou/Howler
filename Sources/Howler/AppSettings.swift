import Foundation
import HowlerCore
import ServiceManagement

/// The only persisted state: the model service, its last check and the hotkey
/// (UserDefaults) plus the API key (Keychain). Conversations are never stored.
/// The model service is set up from the command line (see `CLI`); this object mirrors it
/// and reloads whenever the command line changes it.
@MainActor
final class AppSettings: ObservableObject {
    enum CheckState: Equatable {
        case unchecked
        case checking
        case passed(Date)
        case failed(String)
    }

    @Published private(set) var service: ModelService?
    @Published private(set) var hasKey = false
    @Published private(set) var checkState: CheckState = .unchecked
    @Published private(set) var hotKey: HotKeyCombo
    /// Set by the app delegate after trying to register `hotKey`.
    @Published var hotKeyRegistered = true
    /// While Settings records a new shortcut, the global one is suspended.
    @Published var isRecordingHotKey = false
    @Published private(set) var launchAtLogin: LoginItemState = .off

    let client: ChatClient
    private let defaults: UserDefaults
    private let store: ServiceStore
    /// The key read this session, so the keychain is queried once until the setup changes.
    private var keyCache: String?
    private var observer: NSObjectProtocol?

    private enum DefaultsKey {
        static let hotKey = "hotKey"
    }

    enum LoginItemState: Equatable {
        case off
        case on
        /// Registered, but the user must allow it in System Settings › Login Items.
        case needsApproval
        case failed(String)
    }

    init(client: ChatClient = ChatClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        store = ServiceStore(defaults: defaults)
        hotKey = HotKeyCombo.effective(stored: defaults.data(forKey: DefaultsKey.hotKey)
            .flatMap { try? JSONDecoder().decode(HotKeyCombo.self, from: $0) })
        store.migrateLegacySetup()
        reload()
        refreshLaunchAtLogin()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: ServiceStore.changed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.keyCache = nil
                self?.reload()
            }
        }
    }

    /// Re-reads the setup. Called when the panel or Settings opens and whenever the command
    /// line changes it, so a keychain lookup that failed once (e.g. while locked) is not final.
    func reload() {
        #if DEBUG
        if demoMode { return }
        #endif
        let stored = store.service
        if stored != service { service = stored }
        let present = store.hasKey
        if !present { keyCache = nil }
        if present != hasKey { hasKey = present }
        guard checkState != .checking else { return }
        let state: CheckState = switch store.lastCheck {
        case .some(let record) where record.passed: .passed(record.date)
        case .some(let record): .failed(record.message ?? "The last check failed.")
        case nil: .unchecked
        }
        if state != checkState { checkState = state }
    }

    var isConfigured: Bool {
        #if DEBUG
        if demoMode { return true }
        #endif
        return service != nil && hasKey
    }

    #if DEBUG
    /// Demo mode (HOWLER_DEMO=1) pretends a service is configured; nothing is sent or saved.
    var demoMode = false

    func useDemoService(_ provider: Provider) {
        demoMode = true
        service = provider.service()
        hasKey = true
        checkState = .passed(Date())
    }
    #endif

    func apiKey() -> String? {
        if let keyCache { return keyCache }
        keyCache = store.apiKey()
        return keyCache
    }

    /// Sends a tiny real request with the current setup and records the outcome, which the
    /// command line's `config show` reports too.
    func check() async {
        guard checkState != .checking else { return }
        guard let service else { return }
        guard let key = apiKey(), !key.isEmpty else {
            checkState = .failed("No API key saved.")
            return
        }
        checkState = .checking
        do {
            try await ConnectionTester.test(client: client, service: service, apiKey: key, appName: AppInfo.name)
            checkState = .passed(Date())
            store.recordCheck(passed: true, message: nil)
        } catch {
            checkState = .failed(error.localizedDescription)
            store.recordCheck(passed: false, message: error.localizedDescription)
        }
    }

    // MARK: Hotkey

    func setHotKey(_ combo: HotKeyCombo) {
        guard combo.isValid else { return }
        hotKey = combo
        if let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: DefaultsKey.hotKey)
        }
    }

    // MARK: Launch at login

    func refreshLaunchAtLogin() {
        switch SMAppService.mainApp.status {
        case .enabled: launchAtLogin = .on
        case .requiresApproval: launchAtLogin = .needsApproval
        default: if case .failed = launchAtLogin {} else { launchAtLogin = .off }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = .off
            refreshLaunchAtLogin()
        } catch {
            launchAtLogin = .failed(error.localizedDescription)
        }
    }
}
