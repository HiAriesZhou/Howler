import Foundation
import HowlerCore

/// Where the model setup lives, shared by the app and its command line: the service in
/// UserDefaults, the API key in the Keychain, and how the last check went. Every change
/// is announced so a running app picks up what the command line wrote.
struct ServiceStore {
    /// Injectable so app-state tests never touch the login Keychain.
    struct KeyAccess {
        var exists: (String) -> Bool
        var get: (String) -> String?
        var set: (String, String) throws -> Void
        var delete: (String) -> Void

        static let keychain = KeyAccess(
            exists: Keychain.exists, get: Keychain.get,
            set: { try Keychain.set($0, account: $1) }, delete: Keychain.delete
        )
    }

    struct CheckRecord: Codable, Equatable {
        var passed: Bool
        var message: String?
        var date: Date
        var revision: String?
    }

    static var changed: Notification.Name { Notification.Name(AppInfo.bundleIdentifier + ".serviceChanged") }

    private static let legacyKeyAccount = "api-key"

    private enum DefaultsKey {
        static let service = "service"
        static let check = "serviceCheck"
        /// Absent until the instructions are edited, so a better suggestion reaches everyone else.
        static let instructions = "systemPromptInstructions"
        static let revision = "serviceRevision"
        static let keyScope = "apiKeyScope"
        static let keyScopeMigrated = "apiKeyScopeMigrated"
        static let legacyKeyScope = "legacyAPIKeyScope"
        // Before the single model service: the chosen provider and a model per provider.
        static let legacyProvider = "provider"
        static let legacyModels = "models"
    }

    let defaults: UserDefaults
    private let keys: KeyAccess

    init(defaults: UserDefaults = .standard, keys: KeyAccess = .keychain) {
        self.defaults = defaults
        self.keys = keys
        // Bind an existing installation's key to its existing destination exactly once.
        // No secret is read here, and an absent binding later must never adopt a new host.
        if !defaults.bool(forKey: DefaultsKey.keyScopeMigrated) {
            if let service, keys.exists(Self.legacyKeyAccount) {
                defaults.set(Self.keyScope(for: service), forKey: DefaultsKey.keyScope)
                defaults.set(Self.keyScope(for: service), forKey: DefaultsKey.legacyKeyScope)
            }
            defaults.set(true, forKey: DefaultsKey.keyScopeMigrated)
            invalidateCheck()
        }
    }

    var service: ModelService? {
        defaults.data(forKey: DefaultsKey.service).flatMap { try? JSONDecoder().decode(ModelService.self, from: $0) }
    }

    func save(_ service: ModelService) throws {
        let data = try JSONEncoder().encode(service)
        let previous = self.service
        invalidateCheck()
        defer { finishChange() }
        if let previous, Self.keyScope(for: previous) != Self.keyScope(for: service) {
            defaults.removeObject(forKey: DefaultsKey.keyScope)
            keys.delete(Self.keyAccount(for: previous))
            removeLegacyKey(for: previous)
        }
        defaults.set(data, forKey: DefaultsKey.service)
    }

    /// Checks presence via attributes only, which never triggers a keychain prompt.
    var hasKey: Bool {
        guard let service, defaults.string(forKey: DefaultsKey.keyScope) == Self.keyScope(for: service) else { return false }
        return keys.exists(Self.keyAccount(for: service)) || hasLegacyKey(for: service)
    }

    func apiKey(for expected: ModelService? = nil) -> String? {
        let revision = self.revision
        guard let service, expected == nil || expected == service, hasKey else { return nil }
        let key = keys.get(Self.keyAccount(for: service))
            ?? (hasLegacyKey(for: service) ? keys.get(Self.legacyKeyAccount) : nil)
        // A concurrent config/key write must not pair a new key with an old destination.
        guard self.revision == revision, self.service == service, hasKey else { return nil }
        return key
    }

    func setAPIKey(_ key: String) throws {
        guard let service else { throw ServiceConfigError.missing(["format", "base-url", "model"]) }
        invalidateCheck()
        let revision = self.revision
        defer { finishChange() }
        // Keep the current binding if the Keychain write fails without changing its item.
        // Separate Keychain items prevent a late writer for A from overwriting B's key.
        try keys.set(key, Self.keyAccount(for: service))
        guard self.revision == revision, self.service == service else {
            throw NSError(domain: "Howler.Configuration", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The setup changed while saving the API key. Save it again for the current service."
            ])
        }
        defaults.set(Self.keyScope(for: service), forKey: DefaultsKey.keyScope)
        removeLegacyKey(for: service)
    }

    /// What follows the date in the system prompt. Edited in Settings; empty sends no prompt.
    var instructions: String {
        defaults.string(forKey: DefaultsKey.instructions) ?? SystemPrompt.suggested
    }

    var instructionsAreSuggested: Bool {
        defaults.string(forKey: DefaultsKey.instructions) == nil
    }

    func setInstructions(_ text: String) {
        if text == SystemPrompt.suggested {
            resetInstructions()
        } else {
            guard text != instructions else { return }
            invalidateCheck()
            defaults.set(text, forKey: DefaultsKey.instructions)
            finishChange()
        }
    }

    func resetInstructions() {
        guard !instructionsAreSuggested else { return }
        invalidateCheck()
        defaults.removeObject(forKey: DefaultsKey.instructions)
        finishChange()
    }

    /// The system prompt as it is sent now, or nil when it is off.
    var systemPrompt: String? {
        SystemPrompt.compose(instructions: instructions)
    }

    var lastCheck: CheckRecord? {
        guard let data = defaults.data(forKey: DefaultsKey.check),
              let record = try? JSONDecoder().decode(CheckRecord.self, from: data),
              record.revision == revision else { return nil }
        return record
    }

    var revision: String { defaults.string(forKey: DefaultsKey.revision) ?? "unversioned" }

    @discardableResult
    func recordCheck(passed: Bool, message: String?, for revision: String) -> Bool {
        guard self.revision == revision else { return false }
        let record = CheckRecord(passed: passed, message: message, date: Date(), revision: revision)
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: DefaultsKey.check)
        }
        announce()
        return true
    }

    /// Removes the service, its key and the last check.
    func reset() {
        let previous = service
        invalidateCheck()
        defer { finishChange() }
        defaults.removeObject(forKey: DefaultsKey.service)
        defaults.removeObject(forKey: DefaultsKey.keyScope)
        if let previous { keys.delete(Self.keyAccount(for: previous)) }
        defaults.removeObject(forKey: DefaultsKey.legacyKeyScope)
        keys.delete(Self.legacyKeyAccount)
    }

    /// Turns the provider chosen in an earlier version, with its model and key, into the
    /// model service. Runs once; keys saved for other providers stay where they were.
    func migrateLegacySetup() {
        guard defaults.data(forKey: DefaultsKey.service) == nil,
              let raw = defaults.string(forKey: DefaultsKey.legacyProvider),
              let provider = Provider(rawValue: raw)
        else { return }
        let models = defaults.dictionary(forKey: DefaultsKey.legacyModels) as? [String: String] ?? [:]
        do {
            let service = provider.service(model: models[provider.rawValue])
            let sourceAccount = keys.exists(Self.legacyKeyAccount) ? Self.legacyKeyAccount : provider.rawValue
            if keys.exists(sourceAccount) {
                // A key that exists but can't be read yet (e.g. access was denied) is retried
                // on the next launch rather than left behind.
                guard let key = keys.get(sourceAccount) else { return }
                try keys.set(key, Self.keyAccount(for: service))
            }
            try save(service)
            if keys.exists(Self.keyAccount(for: service)) {
                defaults.set(Self.keyScope(for: service), forKey: DefaultsKey.keyScope)
                keys.delete(sourceAccount)
            }
            defaults.removeObject(forKey: DefaultsKey.legacyProvider)
            defaults.removeObject(forKey: DefaultsKey.legacyModels)
            finishChange()
        } catch {
            // Leave the old settings in place; the next launch tries again.
        }
    }

    /// Same origin and authentication format can share a key when the model/path changes.
    private static func keyScope(for service: ModelService) -> String {
        let url = service.baseURL
        let scheme = url.scheme?.lowercased() ?? "https"
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(service.format.rawValue)|\(scheme)://\(url.host?.lowercased() ?? ""):\(port)"
    }

    private static func keyAccount(for service: ModelService) -> String {
        "api-key:" + keyScope(for: service)
    }

    private func hasLegacyKey(for service: ModelService) -> Bool {
        defaults.string(forKey: DefaultsKey.legacyKeyScope) == Self.keyScope(for: service)
            && keys.exists(Self.legacyKeyAccount)
    }

    private func removeLegacyKey(for service: ModelService) {
        guard defaults.string(forKey: DefaultsKey.legacyKeyScope) == Self.keyScope(for: service) else { return }
        defaults.removeObject(forKey: DefaultsKey.legacyKeyScope)
        keys.delete(Self.legacyKeyAccount)
    }

    private func finishChange() {
        // Fence snapshots taken between the first invalidation and the completed write.
        invalidateCheck()
        announce()
    }

    private func invalidateCheck() {
        defaults.set(UUID().uuidString, forKey: DefaultsKey.revision)
        defaults.removeObject(forKey: DefaultsKey.check)
    }

    private func announce() {
        // Isolated settings domains (including tests) must not notify the installed app.
        guard defaults === UserDefaults.standard else { return }
        DistributedNotificationCenter.default().postNotificationName(
            Self.changed, object: nil, userInfo: nil, deliverImmediately: true
        )
    }
}
