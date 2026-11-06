import Foundation
import HowlerCore
import ServiceManagement

enum ShortcutAction: CaseIterable {
    case letter, settings, capture

    var standard: HotKeyCombo {
        switch self {
        case .letter: .standard
        case .settings: .settings
        case .capture: .screenshot
        }
    }

    var name: String {
        switch self {
        case .letter: "Open \(AppInfo.name)"
        case .settings: "Open Settings"
        case .capture: "Capture and Explain"
        }
    }

    var defaultsKey: String {
        switch self {
        case .letter: "hotKey"
        case .settings: "settingsHotKey"
        case .capture: "screenshotHotKey"
        }
    }
}

/// The only persisted state: the model service, its last check, the system prompt's
/// instructions, reply language and shortcuts (UserDefaults), plus the API key (Keychain). Conversations
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
    @Published private(set) var keyAccessError: String?
    @Published private(set) var isSavingAPIKey = false
    @Published private(set) var checkState: CheckState = .unchecked
    @Published private(set) var replyLanguage: String
    @Published private(set) var connectionVersion = UUID()
    @Published private(set) var hotKey: HotKeyCombo?
    @Published private(set) var settingsHotKey: HotKeyCombo?
    @Published private(set) var screenshotHotKey: HotKeyCombo?
    @Published var screenshotHotKeyRegistered = true
    @Published var settingsHotKeyRegistered = true
    @Published var recordingAction: ShortcutAction = .letter
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
        static let configurableSettingsShortcutChecked = "configurableSettingsShortcutChecked"
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
        let stored = defaults.data(forKey: DefaultsKey.hotKey)
            .flatMap { try? JSONDecoder().decode(HotKeyCombo.self, from: $0) }
        if !defaults.bool(forKey: DefaultsKey.hotKeyDefaultChecked) {
            if stored == .previousStandard { defaults.removeObject(forKey: DefaultsKey.hotKey) }
            defaults.set(true, forKey: DefaultsKey.hotKeyDefaultChecked)
        }
        // Before Settings was configurable, stored ⌥, was a mistaken letter default
        // from 0.1.8/0.1.9. Migrate it once; later deliberate assignments must survive.
        if !defaults.bool(forKey: DefaultsKey.configurableSettingsShortcutChecked) {
            if stored?.isSettings == true {
                defaults.removeObject(forKey: DefaultsKey.hotKey)
            }
            defaults.set(true, forKey: DefaultsKey.configurableSettingsShortcutChecked)
        }
        // Retire the old switch once. Its disabled state becomes an explicit empty
        // shortcut, which can later be recorded without an old flag disabling it again.
        if defaults.object(forKey: "captureAndExplainEnabled") as? Bool == false {
            defaults.set(try? JSONEncoder().encode(Optional<HotKeyCombo>.none),
                         forKey: ShortcutAction.capture.defaultsKey)
        }
        defaults.removeObject(forKey: "captureAndExplainEnabled")
        hotKey = Self.loadShortcut(.letter, from: defaults)
        settingsHotKey = Self.loadShortcut(.settings, from: defaults)
        replyLanguage = store.replyLanguage
        screenshotHotKey = Self.loadShortcut(.capture, from: defaults)
        instructions = store.instructions
        instructionsAreSuggested = store.instructionsAreSuggested
        store.migrateLegacySetup()
        reload()
        refreshLaunchAtLogin()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: ServiceStore.changed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
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
        var connectionChanged = stored != service
        if let cached = keyCache, cached.revision != store.keyRevision || cached.service != stored {
            // Reloading preferences must not cause a blocking Keychain prompt.
            connectionChanged = true
            keyCache = nil
        }
        if stored != service { service = stored }
        if connectionChanged { connectionVersion = UUID() }
        if replyLanguage != store.replyLanguage { replyLanguage = store.replyLanguage }
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
        let revision = store.keyRevision
        if let keyCache, keyCache.revision == revision, keyCache.service == service { return keyCache.key }
        do {
            guard let key = try store.readAPIKey(for: service), store.keyRevision == revision else {
                throw ConfigurationFailure.missingKey
            }
            keyAccessError = nil
            keyCache = (revision, service, key)
            return key
        } catch {
            keyAccessError = error.localizedDescription
            keyCache = nil
            return nil
        }
    }

    func saveAPIKey(_ raw: String, for expected: ModelService) async throws {
        guard !isSavingAPIKey, checkState != .checking else { throw ConfigurationFailure.busy }
        guard service == expected else { throw ConfigurationFailure.changed }
        let key = try ServiceStore.validatedAPIKey(raw)
        let store = self.store
        isSavingAPIKey = true
        defer { isSavingAPIKey = false; reload() }
        try await Task.detached { try store.setAPIKey(key, for: expected) }.value
        keyCache = nil
        keyAccessError = nil
        connectionVersion = UUID()
    }

    /// Sends a tiny real request with the current setup and records the outcome, which the
    /// command line's `config show` reports too.
    func check(for expected: ModelService? = nil) async {
        guard checkState != .checking, !isSavingAPIKey else { return }
        guard let service, expected == nil || expected == service else { return }
        let revision = store.revision
        let store = self.store
        checkingRevision = revision
        checkState = .checking
        defer {
            if checkingRevision == revision {
                checkingRevision = nil
                checkState = .unchecked
                reload()
            }
        }
        do {
            // Explicit checks read afresh, even if a previous conversation cached a key.
            guard let key = try await Task.detached(operation: {
                try store.readAPIKey(for: service)
            }).value, !key.isEmpty else { throw ConfigurationFailure.missingKey }
            guard revision == store.revision else { return }
            keyCache = (store.keyRevision, service, key)
            keyAccessError = nil
            try await ConnectionTester.test(
                client: client, service: service, apiKey: key, appName: AppInfo.name, systemPrompt: systemPrompt, replyLanguage: resolvedReplyLanguage
            )
            store.recordCheck(passed: true, message: nil, for: revision)
        } catch {
            guard revision == store.revision else { return }
            if error is KeychainError || error is ConfigurationFailure {
                keyCache = nil
                keyAccessError = error.localizedDescription
            }
            store.recordCheck(passed: false, message: error.localizedDescription, for: revision)
        }
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

    var resolvedReplyLanguage: String { store.resolvedReplyLanguage }

    func setReplyLanguage(_ language: String) {
        store.setReplyLanguage(language)
        reload()
    }

    // MARK: Hotkey

    /// Missing data means the default; JSON null means deliberately disabled.
    private static func loadShortcut(_ action: ShortcutAction, from defaults: UserDefaults) -> HotKeyCombo? {
        guard let data = defaults.data(forKey: action.defaultsKey) else { return action.standard }
        do {
            let value = try JSONDecoder().decode(HotKeyCombo?.self, from: data)
            if let value, !value.isValid { return action.standard }
            return value
        } catch {
            return action.standard
        }
    }

    func shortcut(for action: ShortcutAction) -> HotKeyCombo? {
        switch action {
        case .letter: hotKey
        case .settings: settingsHotKey
        case .capture: screenshotHotKey
        }
    }

    func shortcutConflict(_ combo: HotKeyCombo, for action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first {
            $0 != action && shortcut(for: $0).map { combo.matches($0) } == true
        }
    }

    @discardableResult
    func setShortcut(_ combo: HotKeyCombo?, for action: ShortcutAction) -> Bool {
        if let combo {
            guard combo.isValid, shortcutConflict(combo, for: action) == nil else { return false }
        }
        switch action {
        case .letter: hotKey = combo
        case .settings: settingsHotKey = combo
        case .capture: screenshotHotKey = combo
        }
        if let data = try? JSONEncoder().encode(combo) { defaults.set(data, forKey: action.defaultsKey) }
        return true
    }

    /// Forget a custom shortcut only when its default is available.
    @discardableResult
    func resetShortcut(for action: ShortcutAction) -> Bool {
        guard setShortcut(action.standard, for: action) else { return false }
        defaults.removeObject(forKey: action.defaultsKey)
        return true
    }

    func setHotKey(_ combo: HotKeyCombo?) { setShortcut(combo, for: .letter) }
    func resetHotKey() { resetShortcut(for: .letter) }
    func setScreenshotHotKey(_ combo: HotKeyCombo?) { setShortcut(combo, for: .capture) }
    func resetScreenshotHotKey() { resetShortcut(for: .capture) }

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
