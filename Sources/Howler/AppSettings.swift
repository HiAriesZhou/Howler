import Foundation
import HowlerCore
import ServiceManagement

/// The only persisted state: the model service, its last check, the system prompt's
/// instructions and the hotkey (UserDefaults) plus the API key (Keychain). Conversations
/// are never stored.
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
    /// Sent after the date at the start of every conversation; see `SystemPrompt`.
    @Published private(set) var instructions: String
    @Published private(set) var instructionsAreSuggested: Bool

    let client: ChatClient
    private let defaults: UserDefaults
    private let store: ServiceStore
    /// The key read this session, so the keychain is queried once until the setup changes.
    private var keyCache: (revision: String, service: ModelService, key: String)?
    private var checkingRevision: String?
    private var observer: NSObjectProtocol?

    private enum DefaultsKey {
        static let hotKey = "hotKey"
        /// Set once the move of the default off ⌥Space has been applied to stored settings.
        static let hotKeyDefaultChecked = "hotKeyDefaultChecked"
    }

    enum LoginItemState: Equatable {
        case off
        case on
        /// Registered, but the user must allow it in System Settings › Login Items.
        case needsApproval
        case failed(String)
    }

    init(client: ChatClient = ChatClient(), defaults: UserDefaults = .standard, keys: ServiceStore.KeyAccess = .keychain) {
        self.client = client
        self.defaults = defaults
        store = ServiceStore(defaults: defaults, keys: keys)
        var stored = defaults.data(forKey: DefaultsKey.hotKey)
            .flatMap { try? JSONDecoder().decode(HotKeyCombo.self, from: $0) }
        if !defaults.bool(forKey: DefaultsKey.hotKeyDefaultChecked) {
            stored = HotKeyCombo.storedAfterDefaultChange(stored)
            if stored == nil { defaults.removeObject(forKey: DefaultsKey.hotKey) }
            defaults.set(true, forKey: DefaultsKey.hotKeyDefaultChecked)
        }
        hotKey = HotKeyCombo.effective(stored: stored)
        instructions = store.instructions
        instructionsAreSuggested = store.instructionsAreSuggested
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
        let text = store.instructions
        if text != instructions { instructions = text }
        let suggested = store.instructionsAreSuggested
        if suggested != instructionsAreSuggested { instructionsAreSuggested = suggested }
        if checkState == .checking, checkingRevision == store.revision { return }
        checkingRevision = nil
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
        guard let service, service == store.service else { return nil }
        let revision = store.revision
        if let keyCache, keyCache.revision == revision, keyCache.service == service { return keyCache.key }
        guard let key = store.apiKey(for: service), store.revision == revision else {
            keyCache = nil
            return nil
        }
        keyCache = (revision, service, key)
        return key
    }

    /// Sends a tiny real request with the current setup and records the outcome, which the
    /// command line's `config show` reports too.
    func check() async {
        guard checkState != .checking else { return }
        guard let service else { return }
        let revision = store.revision
        guard let key = apiKey(), !key.isEmpty else {
            checkState = .failed("No API key saved.")
            return
        }
        guard revision == store.revision else { return }
        checkingRevision = revision
        checkState = .checking
        do {
            try await ConnectionTester.test(
                client: client, service: service, apiKey: key, appName: AppInfo.name, systemPrompt: systemPrompt
            )
            store.recordCheck(passed: true, message: nil, for: revision)
        } catch {
            store.recordCheck(passed: false, message: error.localizedDescription, for: revision)
        }
        guard checkingRevision == revision else { return }
        checkingRevision = nil
        checkState = .unchecked
        reload()
    }

    // MARK: System prompt

    /// The system prompt as it would be sent now, with today's date; nil when it is off.
    var systemPrompt: String? {
        SystemPrompt.compose(instructions: instructions)
    }

    func setInstructions(_ text: String) {
        store.setInstructions(text)
        reload()
    }

    /// Back to the suggestion by forgetting the edit, so a future suggestion applies too.
    func resetInstructions() {
        store.resetInstructions()
        reload()
    }

    // MARK: Hotkey

    func setHotKey(_ combo: HotKeyCombo) {
        guard combo.isValid else { return }
        hotKey = combo
        if let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: DefaultsKey.hotKey)
        }
    }

    /// Back to the default by forgetting the recorded shortcut, so a future default applies too.
    func resetHotKey() {
        hotKey = .standard
        defaults.removeObject(forKey: DefaultsKey.hotKey)
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
