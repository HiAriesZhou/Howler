import Foundation
import Security
import XCTest
import HowlerCore
@testable import Howler

private final class BoundaryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

private final class BoundaryFixture {
    let defaults = BoundaryDefaults(suiteName: "HowlerTests.Boundaries.\(UUID().uuidString)")!
    var values: [String: String] = [:]
    var calls: [String] = []
    var deletionFailures: [String: OSStatus] = [:]
    var readFailures: [String: OSStatus] = [:]

    var access: ServiceStore.KeyAccess {
        .init(
            exists: { self.calls.append("exists:\($0)"); return self.values[$0] != nil },
            get: {
                self.calls.append("get:\($0)")
                if let status = self.readFailures[$0] { throw KeychainError(status: status, operation: "read") }
                return self.values[$0]
            },
            set: { self.calls.append("set:\($1)"); self.values[$1] = $0 },
            delete: {
                self.calls.append("delete:\($0)")
                if let status = self.deletionFailures[$0] { throw KeychainError(status: status, operation: "delete") }
                self.values.removeValue(forKey: $0)
            }
        )
    }

    var store: ServiceStore { ServiceStore(defaults: defaults, keys: access) }

    func seedLegacy() {
        defaults.set("anthropic", forKey: "provider")
        defaults.set(["anthropic": "fixture-model"], forKey: "models")
        values["anthropic"] = "synthetic-legacy"
    }

    func service(_ host: String = "a.example", format: WireFormat = .openAICompatible) -> ModelService {
        ModelService(format: format, baseURL: URL(string: "https://\(host)/v1")!, model: "fixture")
    }
}

final class CLIStorageBoundaryTests: XCTestCase {
    func testInformationalCommandsLeavePendingLegacySetupUntouched() {
        for args in [
            ["help"], ["--help"], ["-h"], ["version"], ["--version"],
            ["config", "schema"], ["config", "--help"], ["config", "reset", "--help"],
            ["config", "reset", "-h"], ["config", "set", "--help"], ["check", "--help"]
        ] {
            let fixture = BoundaryFixture()
            let store = fixture.store
            fixture.seedLegacy()
            let before = fixture.defaults.values as NSDictionary
            fixture.calls = []
            XCTAssertEqual(CLI.run(["Howler"] + args, store: store), 0, "\(args)")
            XCTAssertEqual(fixture.defaults.values as NSDictionary, before, "\(args)")
            XCTAssertEqual(fixture.values, ["anthropic": "synthetic-legacy"], "\(args)")
            XCTAssertEqual(fixture.calls, [], "\(args)")
        }
    }

    func testUnknownArgumentsFailBeforeAnyMigrationOrMutation() {
        for args in [
            ["help", "unknown"], ["version", "--unknown"], ["--help", "--unknown"],
            ["config", "schema", "--unknown"], ["config", "show", "--unknown"],
            ["config", "reset", "--unknown"], ["config", "reset", "--help", "--unknown"],
            ["config", "set", "--help", "--unknown"], ["config", "unknown"],
            ["check", "--unknown"], ["check", "--verbose", "--unknown"]
        ] {
            let fixture = BoundaryFixture()
            let store = fixture.store
            fixture.seedLegacy()
            let before = fixture.defaults.values as NSDictionary
            fixture.calls = []
            XCTAssertEqual(CLI.run(["Howler"] + args, store: store), 1, "\(args)")
            XCTAssertEqual(fixture.defaults.values as NSDictionary, before, "\(args)")
            XCTAssertEqual(fixture.values, ["anthropic": "synthetic-legacy"], "\(args)")
            XCTAssertEqual(fixture.calls, [], "\(args)")
        }
    }

    func testEveryAssignmentIsValidatedBeforeMigration() {
        for fields in [
            ["preset=deepseek", "unknown=value"], ["preset=deepseek", "broken"],
            ["preset=deepseek", "model=bad model"], ["preset=deepseek", "body=not-json"],
            ["preset=deepseek", "base-url=http://remote.example"],
            ["preset=deepseek", "headers={\"Authorization\":\"synthetic\"}"],
            ["preset=deepseek", "api-key=synthetic"], ["preset=deepseek", "format=unknown"]
        ] {
            let fixture = BoundaryFixture()
            let store = fixture.store
            fixture.seedLegacy()
            let before = fixture.defaults.values as NSDictionary
            fixture.calls = []
            XCTAssertEqual(CLI.run(["Howler", "config", "set"] + fields, store: store), 1, "\(fields)")
            XCTAssertEqual(fixture.defaults.values as NSDictionary, before, "\(fields)")
            XCTAssertEqual(fixture.calls, [], "\(fields)")
            XCTAssertEqual(fixture.values, ["anthropic": "synthetic-legacy"], "\(fields)")
        }
    }

    func testValidMutationStillMigratesAndAppliesPartialAssignments() throws {
        let fixture = BoundaryFixture()
        let store = fixture.store
        fixture.seedLegacy()
        XCTAssertEqual(CLI.run(["Howler", "config", "set", "model=replacement"], store: store), 0)
        XCTAssertEqual(store.service?.model, "replacement")
        XCTAssertEqual(store.service?.format, .anthropic)
        XCTAssertEqual(try store.readAPIKey(), "synthetic-legacy")
        XCTAssertNil(fixture.defaults.string(forKey: "provider"))
    }

    func testResetRemovesPendingLegacySetupAndItsKeyWithoutResurrection() throws {
        let fixture = BoundaryFixture()
        let store = fixture.store
        fixture.seedLegacy()
        fixture.values["openai"] = "synthetic-unrelated"
        try store.reset()
        XCTAssertNil(fixture.defaults.object(forKey: "provider"))
        XCTAssertNil(fixture.defaults.object(forKey: "models"))
        XCTAssertNil(fixture.values["anthropic"])
        XCTAssertEqual(fixture.values["openai"], "synthetic-unrelated")
        let reopened = fixture.store
        reopened.migrateLegacySetup()
        XCTAssertNil(reopened.service)
        XCTAssertFalse(reopened.hasKey)
        XCTAssertNil(try reopened.readAPIKey())
    }

    func testResetRemovesCurrentAndPendingLegacyCredentialsTogether() throws {
        let fixture = BoundaryFixture()
        let store = fixture.store
        try store.save(fixture.service())
        try store.setAPIKey("synthetic-current")
        fixture.seedLegacy()
        fixture.values["api-key"] = "synthetic-single-service"
        try store.reset()
        XCTAssertNil(store.service)
        XCTAssertTrue(fixture.values.isEmpty)
        XCTAssertNil(fixture.defaults.object(forKey: "provider"))
        XCTAssertNil(fixture.defaults.object(forKey: "models"))
        fixture.store.migrateLegacySetup()
        XCTAssertNil(fixture.store.service)
    }

    func testResetRemovesKeysReferencedOnlyByPendingLegacyModels() throws {
        let fixture = BoundaryFixture()
        let store = fixture.store
        fixture.defaults.set(["anthropic": "fixture-a", "gemini": "fixture-g", "unknown": "fixture-u"], forKey: "models")
        fixture.values = ["anthropic": "synthetic-a", "gemini": "synthetic-g", "openai": "synthetic-unrelated"]
        fixture.deletionFailures["gemini"] = errSecAuthFailed
        XCTAssertThrowsError(try store.reset())
        XCTAssertNotNil(fixture.defaults.object(forKey: "models"))
        XCTAssertEqual(fixture.values["gemini"], "synthetic-g")
        XCTAssertEqual(fixture.values["openai"], "synthetic-unrelated")
        fixture.deletionFailures = [:]
        try store.reset()
        XCTAssertNil(fixture.defaults.object(forKey: "models"))
        XCTAssertEqual(fixture.values, ["openai": "synthetic-unrelated"])
    }

    func testPartialDeletionAdvancesKeyRevisionBeforeFailureCanExposeAStaleCachedKey() throws {
        let fixture = BoundaryFixture()
        let store = fixture.store
        try store.save(fixture.service())
        try store.setAPIKey("synthetic-current")
        let revision = store.keyRevision
        fixture.seedLegacy()
        fixture.deletionFailures["anthropic"] = errSecAuthFailed
        XCTAssertThrowsError(try store.reset())
        XCTAssertNotEqual(store.keyRevision, revision)
        XCTAssertNil(try store.readAPIKey())
        XCTAssertNotNil(store.service)
    }

    func testInformationalAndInvalidCommandsNeverConstructAStore() {
        for (args, expected) in [
            (["help"], Int32(0)), (["version"], 0), (["--version"], 0),
            (["config", "schema"], 0), (["config", "reset", "--help"], 0),
            (["config", "set", "api-key", "--help"], 0), (["check", "-h"], 0),
            (["config", "reset", "--unknown"], 1), (["config", "set", "model=bad model"], 1),
            (["config", "set", "headers={\"x-api-key\":\"synthetic\"}"], 1),
            (["config", "set", "api-key", "--stdin", "--unknown"], 1),
            (["config", "set", "api-key", "--env"], 1),
            (["config", "set", "api-key", "--env", "FIXTURE", "extra"], 1),
            (["config", "set", "api-key", "--file"], 1),
            (["config", "set", "api-key", "--file", "/synthetic/missing", "extra"], 1),
            (["config", "set", "api-key", "--help", "--unknown"], 1)
        ] {
            let fixture = BoundaryFixture()
            fixture.seedLegacy()
            var constructions = 0
            func makeStore() -> ServiceStore {
                constructions += 1
                return fixture.store
            }
            XCTAssertEqual(CLI.run(["Howler"] + args, store: makeStore()), expected, "\(args)")
            XCTAssertEqual(constructions, 0, "\(args)")
            XCTAssertEqual(fixture.calls, [], "\(args)")
            XCTAssertNil(fixture.defaults.object(forKey: "apiKeyScopeMigrated"), "\(args)")
        }
        let fixture = BoundaryFixture()
        var constructions = 0
        func makeStore() -> ServiceStore {
            constructions += 1
            return fixture.store
        }
        XCTAssertEqual(CLI.run(["Howler", "config", "set", "preset=deepseek"], store: makeStore()), 0)
        XCTAssertEqual(constructions, 1)
        XCTAssertEqual(fixture.store.service?.knownProvider, .deepSeek)
    }

    func testOrdinaryAppLaunchDoesNotConstructCLIStore() {
        let fixture = BoundaryFixture()
        var constructions = 0
        func makeStore() -> ServiceStore {
            constructions += 1
            return fixture.store
        }
        XCTAssertNil(CLI.run(["Howler"], store: makeStore()))
        XCTAssertEqual(constructions, 0)
    }

    func testFileKeySourceRemainsAvailableAfterStrictArgumentValidation() throws {
        let fixture = BoundaryFixture()
        let store = fixture.store
        try store.save(fixture.service())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("HowlerTests.Key.\(UUID().uuidString)")
        try Data("synthetic-file-key\n".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(CLI.run(["Howler", "config", "set", "api-key", "--file", file.path], store: store), 0)
        XCTAssertEqual(try store.readAPIKey(), "synthetic-file-key")
    }

    func testResetDeletionFailuresPreserveConfigurationAndCanBeRetried() throws {
        for failureIndex in 0..<3 {
            let fixture = BoundaryFixture()
            let store = fixture.store
            try store.save(fixture.service())
            try store.setAPIKey("synthetic-current")
            fixture.seedLegacy()
            fixture.values["api-key"] = "synthetic-single-service"
            let scoped = try XCTUnwrap(fixture.values.keys.first { $0.hasPrefix("api-key:") })
            let accounts = [scoped, "api-key", "anthropic"]
            let previousKeys = fixture.values
            let previousService = store.service
            let previousScope = fixture.defaults.string(forKey: "apiKeyScope")
            let revision = store.revision
            store.recordCheck(passed: true, message: nil, for: revision)
            fixture.deletionFailures[accounts[failureIndex]] = errSecAuthFailed
            fixture.calls = []

            XCTAssertThrowsError(try store.reset()) { error in
                XCTAssertEqual((error as? KeychainError)?.status, errSecAuthFailed)
                XCTAssertEqual((error as? KeychainError)?.operation, "delete")
            }
            XCTAssertEqual(fixture.calls, accounts.prefix(failureIndex + 1).map { "delete:\($0)" })
            XCTAssertEqual(store.service, previousService)
            XCTAssertEqual(fixture.defaults.string(forKey: "apiKeyScope"), previousScope)
            XCTAssertEqual(fixture.defaults.string(forKey: "provider"), "anthropic")
            XCTAssertEqual(fixture.defaults.dictionary(forKey: "models") as? [String: String], ["anthropic": "fixture-model"])
            XCTAssertNotEqual(store.revision, revision)
            XCTAssertNil(store.lastCheck)
            XCTAssertFalse(store.recordCheck(passed: true, message: nil, for: revision))
            var remaining = previousKeys
            for account in accounts.prefix(failureIndex) { remaining.removeValue(forKey: account) }
            XCTAssertEqual(fixture.values, remaining)

            fixture.deletionFailures = [:]
            fixture.calls = []
            try store.reset()
            XCTAssertEqual(fixture.calls, accounts.map { "delete:\($0)" })
            XCTAssertTrue(fixture.values.isEmpty)
            XCTAssertNil(store.service)
            XCTAssertNil(fixture.defaults.object(forKey: "provider"))
            XCTAssertNil(fixture.defaults.object(forKey: "models"))
            fixture.store.migrateLegacySetup()
            XCTAssertNil(fixture.store.service)
            try store.reset()
            XCTAssertTrue(fixture.values.isEmpty)
        }
    }

    func testCLIResetReportsTheDeletionFailureWithoutMigratingOrRebuilding() throws {
        for status in [errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled] {
            let fixture = BoundaryFixture()
            let store = fixture.store
            fixture.seedLegacy()
            fixture.deletionFailures["anthropic"] = status
            let output = capture { CLI.run(["Howler", "config", "reset"], store: store) }
            XCTAssertEqual(output.status, 1)
            XCTAssertEqual(output.stdout, "")
            XCTAssertTrue(output.stderr.contains("Keychain delete (OSStatus \(status))"))
            XCTAssertFalse(output.stderr.contains("synthetic-legacy"))
            XCTAssertEqual(fixture.calls, ["delete:api-key", "delete:anthropic"])
            XCTAssertNil(store.service)
            XCTAssertEqual(fixture.values, ["anthropic": "synthetic-legacy"])
            XCTAssertEqual(fixture.defaults.string(forKey: "provider"), "anthropic")
            fixture.deletionFailures = [:]
            let retry = capture { CLI.run(["Howler", "config", "reset"], store: store) }
            XCTAssertEqual(retry.status, 0)
            XCTAssertTrue(retry.stdout.contains("Removed the model service and its API key."))
            XCTAssertEqual(retry.stderr, "")
            XCTAssertTrue(fixture.values.isEmpty)
            XCTAssertNil(fixture.defaults.object(forKey: "provider"))
        }
    }

    func testFailedOriginDeletionPreservesTheOriginalServiceAndBinding() throws {
        let fixture = BoundaryFixture()
        let store = fixture.store
        let original = fixture.service()
        try store.save(original)
        try store.setAPIKey("synthetic-current")
        let scoped = try XCTUnwrap(fixture.values.keys.first)
        let scope = fixture.defaults.string(forKey: "apiKeyScope")
        fixture.deletionFailures[scoped] = errSecAuthFailed
        fixture.calls = []
        XCTAssertThrowsError(try store.save(fixture.service("b.example")))
        XCTAssertEqual(fixture.calls, ["delete:\(scoped)"])
        XCTAssertEqual(store.service, original)
        XCTAssertEqual(fixture.defaults.string(forKey: "apiKeyScope"), scope)
        XCTAssertEqual(try store.readAPIKey(), "synthetic-current")
        XCTAssertEqual(try fixture.store.readAPIKey(), "synthetic-current")
        fixture.deletionFailures = [:]
        try store.save(fixture.service("b.example"))
        XCTAssertEqual(store.service?.host, "b.example")
        XCTAssertFalse(store.hasKey)
        XCTAssertNil(try store.readAPIKey())
        XCTAssertTrue(fixture.values.isEmpty)
    }

    func testPartialOriginDeletionKeepsRemainingLegacyCredentialBoundToItsOriginalOrigin() throws {
        for hasScopedItem in [false, true] {
            let fixture = BoundaryFixture()
            let original = fixture.service()
            fixture.defaults.set(try JSONEncoder().encode(original), forKey: "service")
            fixture.values["api-key"] = "synthetic-legacy"
            let store = fixture.store
            let scope = try XCTUnwrap(fixture.defaults.string(forKey: "apiKeyScope"))
            let scoped = "api-key:" + scope
            if hasScopedItem { fixture.values[scoped] = "synthetic-scoped" }
            fixture.deletionFailures["api-key"] = errSecInteractionNotAllowed
            fixture.calls = []
            XCTAssertThrowsError(try store.save(fixture.service("b.example")))
            XCTAssertEqual(fixture.calls, ["delete:\(scoped)", "delete:api-key"])
            XCTAssertEqual(store.service, original)
            XCTAssertEqual(fixture.defaults.string(forKey: "apiKeyScope"), scope)
            XCTAssertEqual(fixture.defaults.string(forKey: "legacyAPIKeyScope"), scope)
            XCTAssertNil(fixture.values[scoped])
            XCTAssertEqual(try store.readAPIKey(), "synthetic-legacy")
            XCTAssertEqual(try fixture.store.readAPIKey(), "synthetic-legacy")
            fixture.deletionFailures = [:]
            try store.save(fixture.service("b.example"))
            XCTAssertNil(fixture.defaults.string(forKey: "legacyAPIKeyScope"))
            XCTAssertNil(try store.readAPIKey())
            XCTAssertTrue(fixture.values.isEmpty)
        }
    }

    func testKeyReplacementPropagatesLegacyCleanupFailureAndRetainsBothBindings() throws {
        let fixture = BoundaryFixture()
        let original = fixture.service()
        fixture.defaults.set(try JSONEncoder().encode(original), forKey: "service")
        fixture.values["api-key"] = "synthetic-legacy"
        let store = fixture.store
        let scope = fixture.defaults.string(forKey: "apiKeyScope")
        let revision = store.keyRevision
        fixture.deletionFailures["api-key"] = errSecUserCanceled
        XCTAssertThrowsError(try store.setAPIKey("synthetic-replacement")) { error in
            XCTAssertEqual((error as? KeychainError)?.status, errSecUserCanceled)
        }
        XCTAssertEqual(store.service, original)
        XCTAssertEqual(fixture.defaults.string(forKey: "apiKeyScope"), scope)
        XCTAssertEqual(fixture.defaults.string(forKey: "legacyAPIKeyScope"), scope)
        XCTAssertEqual(fixture.values["api-key"], "synthetic-legacy")
        XCTAssertNotEqual(store.keyRevision, revision)
        XCTAssertEqual(try fixture.store.readAPIKey(), "synthetic-replacement")
        fixture.deletionFailures = [:]
        try store.setAPIKey("synthetic-replacement")
        XCTAssertNil(fixture.defaults.string(forKey: "legacyAPIKeyScope"))
        XCTAssertNil(fixture.values["api-key"])
        XCTAssertEqual(try store.readAPIKey(), "synthetic-replacement")
    }

    func testMigrationDeletionFailureKeepsPendingLegacyStateAvailableForReset() throws {
        let fixture = BoundaryFixture()
        let store = fixture.store
        fixture.seedLegacy()
        fixture.deletionFailures["anthropic"] = errSecAuthFailed
        store.migrateLegacySetup()
        XCTAssertEqual(store.service?.knownProvider, .anthropic)
        XCTAssertEqual(try store.readAPIKey(), "synthetic-legacy")
        XCTAssertEqual(fixture.defaults.string(forKey: "provider"), "anthropic")
        fixture.deletionFailures = [:]
        try store.reset()
        XCTAssertTrue(fixture.values.isEmpty)
        fixture.store.migrateLegacySetup()
        XCTAssertNil(fixture.store.service)
    }

    @MainActor
    func testPartialResetDeletionInvalidatesCachedKeyAndPausesQueue() throws {
        try assertCachedQueueIsInvalidated(by: .reset)
    }

    @MainActor
    func testPartialOriginDeletionInvalidatesCachedKeyAndPausesQueue() throws {
        try assertCachedQueueIsInvalidated(by: .changeOrigin)
    }

    @MainActor
    func testFailedLegacyCleanupAfterReplacementInvalidatesCachedKeyAndPausesQueue() throws {
        try assertCachedQueueIsInvalidated(by: .replaceKey)
    }

    @MainActor
    func testDeniedDeletionInvalidatesCachedCredentialBeforeItCanBeReused() throws {
        let fixture = BoundaryFixture()
        let store = fixture.store
        try store.save(fixture.service())
        try store.setAPIKey("synthetic-current")
        let scoped = try XCTUnwrap(fixture.values.keys.first)
        let settings = AppSettings(defaults: fixture.defaults, keys: fixture.access)
        XCTAssertEqual(settings.apiKey(), "synthetic-current")
        let model = ChatViewModel(settings: settings)
        var continuation: AsyncThrowingStream<String, Error>.Continuation?
        model.streamFactory = { _, _ in AsyncThrowingStream { continuation = $0 } }
        defer { model.reset(); continuation?.finish() }
        model.input = "Active synthetic question"
        model.send()
        model.input = "Waiting synthetic question"
        model.send()
        XCTAssertFalse(model.queue.isPaused)
        XCTAssertEqual(model.queue.waiting.count, 1)
        let revision = store.keyRevision
        let connection = settings.connectionVersion
        fixture.deletionFailures[scoped] = errSecAuthFailed
        fixture.readFailures[scoped] = errSecAuthFailed

        XCTAssertThrowsError(try store.reset())
        XCTAssertEqual(fixture.values[scoped], "synthetic-current")
        XCTAssertNotEqual(store.keyRevision, revision)
        XCTAssertNil(settings.apiKey())
        XCTAssertNotNil(settings.keyAccessError)
        settings.reload()
        XCTAssertNotEqual(settings.connectionVersion, connection)
        XCTAssertTrue(model.queue.isPaused)
        XCTAssertEqual(model.queue.active?.state, .paused)
        XCTAssertEqual(model.queue.waiting.count, 1)
    }

    private enum DeletionMutation { case reset, changeOrigin, replaceKey }

    @MainActor
    private func assertCachedQueueIsInvalidated(by mutation: DeletionMutation) throws {
        let fixture = BoundaryFixture()
        let original = fixture.service()
        fixture.defaults.set(try JSONEncoder().encode(original), forKey: "service")
        fixture.values["api-key"] = "synthetic-legacy"
        let store = fixture.store
        let scope = try XCTUnwrap(fixture.defaults.string(forKey: "apiKeyScope"))
        let scoped = "api-key:" + scope
        fixture.values[scoped] = "synthetic-current"
        let settings = AppSettings(defaults: fixture.defaults, keys: fixture.access)
        XCTAssertEqual(settings.apiKey(), "synthetic-current")
        let model = ChatViewModel(settings: settings)
        var continuation: AsyncThrowingStream<String, Error>.Continuation?
        model.streamFactory = { _, _ in AsyncThrowingStream { continuation = $0 } }
        defer { model.reset(); continuation?.finish() }
        model.input = "Active synthetic question"
        model.send()
        model.input = "Waiting synthetic question"
        model.send()
        XCTAssertEqual(model.queue.active?.state, .generating)
        XCTAssertEqual(model.queue.waiting.count, 1)
        XCTAssertFalse(model.queue.isPaused)
        let revision = store.keyRevision
        let connection = settings.connectionVersion
        fixture.deletionFailures["api-key"] = errSecAuthFailed

        XCTAssertThrowsError(try {
            switch mutation {
            case .reset: try store.reset()
            case .changeOrigin: try store.save(fixture.service("b.example"))
            case .replaceKey: try store.setAPIKey("synthetic-replacement")
            }
        }()) { error in
            XCTAssertEqual((error as? KeychainError)?.status, errSecAuthFailed)
        }
        XCTAssertEqual(store.service, original)
        XCTAssertEqual(fixture.defaults.string(forKey: "apiKeyScope"), scope)
        XCTAssertEqual(fixture.defaults.string(forKey: "legacyAPIKeyScope"), scope)
        XCTAssertTrue(store.hasKey)
        XCTAssertEqual(fixture.values["api-key"], "synthetic-legacy")
        XCTAssertNotEqual(store.keyRevision, revision)
        let remainingKey = mutation == .replaceKey ? "synthetic-replacement" : "synthetic-legacy"
        XCTAssertEqual(settings.apiKey(), remainingKey)
        settings.reload()
        XCTAssertNotEqual(settings.connectionVersion, connection)
        XCTAssertEqual(settings.apiKey(), remainingKey)
        XCTAssertTrue(model.queue.isPaused)
        XCTAssertEqual(model.queue.active?.state, .paused)
        XCTAssertEqual(model.queue.waiting.count, 1)
    }

    private func capture(_ operation: () -> Int32?) -> (status: Int32?, stdout: String, stderr: String) {
        fflush(stdout)
        fflush(stderr)
        let savedOut = dup(STDOUT_FILENO)
        let savedError = dup(STDERR_FILENO)
        let out = Pipe()
        let error = Pipe()
        dup2(out.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(error.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        let status = operation()
        fflush(stdout)
        fflush(stderr)
        dup2(savedOut, STDOUT_FILENO)
        dup2(savedError, STDERR_FILENO)
        close(savedOut)
        close(savedError)
        out.fileHandleForWriting.closeFile()
        error.fileHandleForWriting.closeFile()
        return (status, String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}

final class KeychainDeletionBoundaryTests: XCTestCase {
    func testDeletionAcceptsSuccessAndMissingItems() throws {
        for status in [errSecSuccess, errSecItemNotFound] {
            var deletions = 0
            let operations = Keychain.Operations(
                update: { _, _ in XCTFail("Unexpected update"); return errSecAuthFailed },
                add: { _, _ in XCTFail("Unexpected add"); return errSecAuthFailed },
                delete: { query in
                    deletions += 1
                    let query = query as NSDictionary
                    XCTAssertEqual(query[kSecClass] as? String, kSecClassGenericPassword as String)
                    XCTAssertEqual(query[kSecAttrService] as? String, AppInfo.bundleIdentifier)
                    XCTAssertEqual(query[kSecAttrAccount] as? String, "fixture-account")
                    return status
                },
                copy: { _, _ in XCTFail("Unexpected read"); return errSecAuthFailed }
            )
            try Keychain.delete(account: "fixture-account", operations: operations)
            XCTAssertEqual(deletions, 1)
        }
    }

    func testDeletionPropagatesErrorsWithoutRecreatingAnItem() {
        for status in [errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled, errSecParam] {
            var calls: [String] = []
            let operations = Keychain.Operations(
                update: { _, _ in calls.append("update"); return errSecSuccess },
                add: { _, _ in calls.append("add"); return errSecSuccess },
                delete: { _ in calls.append("delete"); return status },
                copy: { _, _ in calls.append("read"); return errSecSuccess }
            )
            XCTAssertThrowsError(try Keychain.delete(account: "fixture-account", operations: operations)) { error in
                XCTAssertEqual((error as? KeychainError)?.status, status)
                XCTAssertEqual((error as? KeychainError)?.operation, "delete")
                XCTAssertTrue(error.localizedDescription.contains("OSStatus \(status)"))
            }
            XCTAssertEqual(calls, ["delete"])
        }
    }
}
