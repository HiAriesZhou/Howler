import Foundation
import HowlerCore
import ServiceManagement

/// The only persisted state: the active provider, per-provider model and the hotkey
/// (UserDefaults) plus API keys (Keychain). Conversations are never
/// stored.
@MainActor
final class AppSettings: ObservableObject {
    enum ConnectionStatus: Equatable {
        case untested
        case testing
        case connected
        case failed(String)
    }

    @Published private(set) var activeProvider: Provider?
    @Published private(set) var status: [Provider: ConnectionStatus] = [:]
    @Published private(set) var keyPresence: [Provider: Bool] = [:]
    @Published private(set) var hotKey: HotKeyCombo
    /// Set by the app delegate after trying to register `hotKey`.
    @Published var hotKeyRegistered = true
    /// While Settings records a new shortcut, the global one is suspended.
    @Published var isRecordingHotKey = false
    @Published private(set) var launchAtLogin: LoginItemState = .off

    let client: ChatClient
    private let defaults: UserDefaults
    /// Keys read this session, so the keychain is queried at most once per provider.
    private var keyCache: [Provider: String] = [:]

    private enum DefaultsKey {
        static let provider = "provider"
        static let models = "models"
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
        activeProvider = defaults.string(forKey: DefaultsKey.provider).flatMap(Provider.init(rawValue:))
        hotKey = defaults.data(forKey: DefaultsKey.hotKey)
            .flatMap { try? JSONDecoder().decode(HotKeyCombo.self, from: $0) }
            .flatMap { $0.isValid ? $0 : nil } ?? .optionSpace
        refreshKeyPresence()
        refreshLaunchAtLogin()
    }

    /// Re-reads which providers have a stored key. Called whenever the panel or Settings
    /// opens, so a keychain lookup that failed once (e.g. while locked) is not final.
    func refreshKeyPresence() {
        var presence: [Provider: Bool] = [:]
        for provider in Provider.allCases {
            let present = Keychain.exists(account: provider.rawValue)
            presence[provider] = present
            if !present { keyCache[provider] = nil }
        }
        if presence != keyPresence { keyPresence = presence }
    }

    var isConfigured: Bool {
        #if DEBUG
        if demoMode { return true }
        #endif
        guard let activeProvider else { return false }
        return hasKey(for: activeProvider)
    }

    #if DEBUG
    /// Demo mode (HOWLER_DEMO=1) pretends a provider is configured; nothing is sent or saved.
    var demoMode = false

    func useDemoProvider(_ provider: Provider) {
        demoMode = true
        if activeProvider == nil { activeProvider = provider }
    }
    #endif

    /// Providers ready to use right now, for switching from the panel.
    var configuredProviders: [Provider] {
        Provider.allCases.filter(hasKey(for:))
    }

    /// Switches the active provider without re-testing (its key was tested when saved).
    func setActiveProvider(_ provider: Provider) {
        guard provider != activeProvider else { return }
        activeProvider = provider
        defaults.set(provider.rawValue, forKey: DefaultsKey.provider)
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

    func hasKey(for provider: Provider) -> Bool {
        keyPresence[provider] ?? false
    }

    func connectionStatus(for provider: Provider) -> ConnectionStatus {
        status[provider] ?? .untested
    }

    /// The model the user typed, or "" for the provider default.
    func storedModel(for provider: Provider) -> String {
        let models = defaults.dictionary(forKey: DefaultsKey.models) as? [String: String] ?? [:]
        return models[provider.rawValue] ?? ""
    }

    func model(for provider: Provider) -> String {
        provider.resolvedModel(storedModel(for: provider))
    }

    func apiKey(for provider: Provider) -> String? {
        if let cached = keyCache[provider] { return cached }
        let key = Keychain.get(account: provider.rawValue)
        keyCache[provider] = key
        return key
    }

    /// Makes `provider` active, stores the key (if a new one was entered) and model,
    /// then runs a tiny real request to verify the configuration.
    func save(provider: Provider, newKey: String, model: String) async {
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            do {
                try Keychain.set(key, account: provider.rawValue)
                keyCache[provider] = key
                keyPresence[provider] = true
            } catch {
                status[provider] = .failed(error.localizedDescription)
                return
            }
        }

        var models = defaults.dictionary(forKey: DefaultsKey.models) as? [String: String] ?? [:]
        models[provider.rawValue] = model.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(models, forKey: DefaultsKey.models)
        activeProvider = provider
        defaults.set(provider.rawValue, forKey: DefaultsKey.provider)

        guard let storedKey = apiKey(for: provider), !storedKey.isEmpty else {
            status[provider] = .failed("No API key saved.")
            return
        }
        status[provider] = .testing
        do {
            try await ConnectionTester.test(
                client: client,
                provider: provider,
                apiKey: storedKey,
                model: self.model(for: provider),
                appName: AppInfo.name
            )
            status[provider] = .connected
        } catch {
            status[provider] = .failed(error.localizedDescription)
        }
    }

    func removeKey(for provider: Provider) {
        Keychain.delete(account: provider.rawValue)
        keyCache[provider] = nil
        keyPresence[provider] = false
        status[provider] = .untested
    }
}
