import Foundation
import HowlerCore

/// Where the model setup lives, shared by the app and its command line: the service in
/// UserDefaults, the API key in the Keychain, and how the last check went. Every change
/// is announced so a running app picks up what the command line wrote.
struct ServiceStore {
    struct CheckRecord: Codable, Equatable {
        var passed: Bool
        var message: String?
        var date: Date
    }

    static var changed: Notification.Name { Notification.Name(AppInfo.bundleIdentifier + ".serviceChanged") }

    private static let keyAccount = "api-key"

    private enum DefaultsKey {
        static let service = "service"
        static let check = "serviceCheck"
        /// Absent until the instructions are edited, so a better suggestion reaches everyone else.
        static let instructions = "systemPromptInstructions"
        // Before the single model service: the chosen provider and a model per provider.
        static let legacyProvider = "provider"
        static let legacyModels = "models"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var service: ModelService? {
        defaults.data(forKey: DefaultsKey.service).flatMap { try? JSONDecoder().decode(ModelService.self, from: $0) }
    }

    func save(_ service: ModelService) throws {
        defaults.set(try JSONEncoder().encode(service), forKey: DefaultsKey.service)
        defaults.removeObject(forKey: DefaultsKey.check)
        announce()
    }

    /// Checks presence via attributes only, which never triggers a keychain prompt.
    var hasKey: Bool {
        Keychain.exists(account: Self.keyAccount)
    }

    func apiKey() -> String? {
        Keychain.get(account: Self.keyAccount)
    }

    func setAPIKey(_ key: String) throws {
        try Keychain.set(key, account: Self.keyAccount)
        defaults.removeObject(forKey: DefaultsKey.check)
        announce()
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
            defaults.set(text, forKey: DefaultsKey.instructions)
        }
    }

    func resetInstructions() {
        defaults.removeObject(forKey: DefaultsKey.instructions)
    }

    /// The system prompt as it is sent now, or nil when it is off.
    var systemPrompt: String? {
        SystemPrompt.compose(instructions: instructions)
    }

    var lastCheck: CheckRecord? {
        defaults.data(forKey: DefaultsKey.check).flatMap { try? JSONDecoder().decode(CheckRecord.self, from: $0) }
    }

    func recordCheck(passed: Bool, message: String?) {
        let record = CheckRecord(passed: passed, message: message, date: Date())
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: DefaultsKey.check)
        }
        announce()
    }

    /// Removes the service, its key and the last check.
    func reset() {
        defaults.removeObject(forKey: DefaultsKey.service)
        defaults.removeObject(forKey: DefaultsKey.check)
        Keychain.delete(account: Self.keyAccount)
        announce()
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
            if !hasKey, Keychain.exists(account: provider.rawValue) {
                // A key that exists but can't be read yet (e.g. access was denied) is retried
                // on the next launch rather than left behind.
                guard let key = Keychain.get(account: provider.rawValue) else { return }
                try Keychain.set(key, account: Self.keyAccount)
                Keychain.delete(account: provider.rawValue)
            }
            try save(provider.service(model: models[provider.rawValue]))
            defaults.removeObject(forKey: DefaultsKey.legacyProvider)
            defaults.removeObject(forKey: DefaultsKey.legacyModels)
        } catch {
            // Leave the old settings in place; the next launch tries again.
        }
    }

    private func announce() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.changed, object: nil, userInfo: nil, deliverImmediately: true
        )
    }
}
