import Foundation
import XCTest
import HowlerCore
@testable import Howler

/// Synthetic credentials only; these tests never access the real Keychain or network.
final class MemoryKeys {
    var values: [String: String] = [:]
    var access: ServiceStore.KeyAccess {
        .init(exists: { self.values[$0] != nil }, get: { self.values[$0] },
              set: { self.values[$1] = $0 }, delete: { self.values.removeValue(forKey: $0) })
    }
}

final class ObservedDefaults: UserDefaults {
    var beforeWrite: ((String) -> Void)?
    override func set(_ value: Any?, forKey defaultName: String) {
        beforeWrite?(defaultName)
        super.set(value, forKey: defaultName)
    }
}

final class DelayedProbe: URLProtocol {
    static var started: XCTestExpectation?
    static var pending: DelayedProbe?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.pending = self
        Self.started?.fulfill()
    }
    override func stopLoading() {}

    func succeed() {
        respond(status: 200, body: "data: {\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\ndata: [DONE]\n\n")
    }

    func respond(status: Int, body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class StateSafetyTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var keys: MemoryKeys!
    private var store: ServiceStore!

    override func setUp() {
        suite = "HowlerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        keys = MemoryKeys()
        store = ServiceStore(defaults: defaults, keys: keys.access)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        DelayedProbe.pending = nil
        DelayedProbe.started = nil
    }

    private func service(_ address: String = "https://service-a.example/v1", model: String = "fixture") -> ModelService {
        ModelService(format: .openAICompatible, baseURL: URL(string: address)!, model: model)
    }

    func testChangingOriginDoesNotReuseThePreviousKey() throws {
        try store.save(service())
        try store.setAPIKey("fixture-secret-a")
        XCTAssertEqual(store.apiKey(), "fixture-secret-a")
        try store.save(service("https://service-b.example/v1"))
        XCTAssertFalse(store.hasKey)
        XCTAssertNil(store.apiKey())
    }

    func testChangingModelOnSameOriginKeepsTheKey() throws {
        try store.save(service())
        try store.setAPIKey("fixture-secret-a")
        try store.save(service(model: "another-model"))
        XCTAssertTrue(store.hasKey)
        XCTAssertEqual(store.apiKey(), "fixture-secret-a")
    }

    func testDefaultPortsAndPathChangesKeepTheKeyButDifferentPortsDoNot() throws {
        try store.save(service())
        try store.setAPIKey("fixture-secret-a")
        try store.save(service("https://SERVICE-A.example:443/another-api"))
        XCTAssertEqual(store.apiKey(), "fixture-secret-a")
        try store.save(service("https://service-a.example:8443/v1"))
        XCTAssertFalse(store.hasKey)
        XCTAssertNil(store.apiKey())
    }

    func testChangingAuthenticationFormatRequiresANewKey() throws {
        try store.save(service())
        try store.setAPIKey("fixture-secret-a")
        var replacement = service()
        replacement.format = .anthropic
        try store.save(replacement)
        XCTAssertFalse(store.hasKey)
        XCTAssertNil(store.apiKey())
    }

    func testExistingSingleServiceKeyIsBoundOnlyOnce() throws {
        defaults.set(try JSONEncoder().encode(service()), forKey: "service")
        defaults.removeObject(forKey: "apiKeyScopeMigrated")
        keys.values["api-key"] = "fixture-legacy-secret"
        let upgraded = ServiceStore(defaults: defaults, keys: keys.access)
        XCTAssertEqual(upgraded.apiKey(), "fixture-legacy-secret")
        try upgraded.save(service("https://service-b.example/v1"))
        keys.values["api-key"] = "fixture-orphaned-secret"
        let reopened = ServiceStore(defaults: defaults, keys: keys.access)
        XCTAssertFalse(reopened.hasKey)
        XCTAssertNil(reopened.apiKey())
    }

    func testLegacyProviderMigrationKeepsItsKey() {
        defaults.set("anthropic", forKey: "provider")
        keys.values["anthropic"] = "fixture-legacy-secret"
        store.migrateLegacySetup()
        XCTAssertEqual(store.service?.knownProvider, .anthropic)
        XCTAssertEqual(store.apiKey(), "fixture-legacy-secret")
        XCTAssertNil(keys.values["anthropic"])
        XCTAssertNil(defaults.string(forKey: "provider"))
    }

    func testPromptKeyAndResetChangesInvalidatePreviousChecks() throws {
        try store.save(service())
        try store.setAPIKey("fixture-secret-a")
        func passedRevision() -> String {
            let revision = store.revision
            XCTAssertTrue(store.recordCheck(passed: true, message: nil, for: revision))
            XCTAssertEqual(store.lastCheck?.passed, true)
            return revision
        }
        let promptRevision = passedRevision()
        store.setInstructions("Synthetic revised instructions")
        XCTAssertNil(store.lastCheck)
        XCTAssertFalse(store.recordCheck(passed: true, message: nil, for: promptRevision))
        let keyRevision = passedRevision()
        try store.setAPIKey("fixture-secret-b")
        XCTAssertNil(store.lastCheck)
        XCTAssertFalse(store.recordCheck(passed: false, message: "Old failure", for: keyRevision))
        let resetRevision = passedRevision()
        store.reset()
        XCTAssertFalse(store.hasKey)
        XCTAssertFalse(store.recordCheck(passed: true, message: nil, for: resetRevision))
        XCTAssertNil(store.lastCheck)
    }

    func testAConfigurationChangeDuringKeyReadFailsClosed() throws {
        try store.save(service())
        try store.setAPIKey("fixture-secret-a")
        var access = keys.access
        access.get = { account in
            let key = self.keys.values[account]
            try? self.store.save(self.service("https://service-b.example/v1"))
            return key
        }
        let concurrent = ServiceStore(defaults: defaults, keys: access)
        XCTAssertNil(concurrent.apiKey())
    }

    func testKeyWriteDoesNotClaimSuccessAfterConfigurationChanges() throws {
        try store.save(service())
        var access = keys.access
        access.set = { key, account in
            self.keys.values[account] = key
            try self.store.save(self.service("https://service-b.example/v1"))
        }
        let concurrent = ServiceStore(defaults: defaults, keys: access)
        XCTAssertThrowsError(try concurrent.setAPIKey("fixture-secret-a"))
        XCTAssertFalse(concurrent.hasKey)
    }

    func testCompetingKeyWriterCannotReplaceAnotherOriginsCredential() throws {
        try store.save(service())
        try store.setAPIKey("fixture-secret-a")
        var access = keys.access
        access.set = { key, account in
            try self.store.save(self.service("https://service-b.example/v1"))
            try self.store.setAPIKey("fixture-secret-b")
            self.keys.values[account] = key
        }
        let concurrent = ServiceStore(defaults: defaults, keys: access)
        XCTAssertThrowsError(try concurrent.setAPIKey("fixture-late-secret-a"))
        XCTAssertEqual(store.service?.host, "service-b.example")
        XCTAssertEqual(store.apiKey(), "fixture-secret-b")
    }

    func testProbeSnapshotsTakenDuringConfigurationWritesCannotBecomeCurrent() throws {
        let observed = ObservedDefaults(suiteName: suite)!
        let concurrent = ServiceStore(defaults: observed, keys: keys.access)
        try concurrent.save(service())
        try concurrent.setAPIKey("fixture-secret-a")
        var captured: String?
        observed.beforeWrite = { name in
            if name == "service" { captured = concurrent.revision }
        }
        defer { observed.beforeWrite = nil }
        try concurrent.save(service(model: "replacement"))
        let revision = try XCTUnwrap(captured)
        XCTAssertFalse(concurrent.recordCheck(passed: true, message: nil, for: revision))
        XCTAssertNil(concurrent.lastCheck)
        XCTAssertTrue(concurrent.recordCheck(passed: true, message: nil, for: concurrent.revision))
    }

    @MainActor
    func testCachedKeyCannotBypassAnUndeliveredConfigurationChange() async throws {
        try store.save(service())
        try store.setAPIKey("fixture-secret-a")
        let settings = AppSettings(defaults: defaults, keys: keys.access)
        XCTAssertEqual(settings.apiKey(), "fixture-secret-a")
        try store.save(service("https://service-b.example/v1"))
        XCTAssertNil(settings.apiKey())
    }

    @MainActor
    func testAnOldProbeCannotMarkTheReplacementConfigurationReady() async throws {
        try store.save(service())
        try store.setAPIKey("fixture-secret-a")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedProbe.self]
        let settings = AppSettings(client: ChatClient(session: URLSession(configuration: configuration)),
                                   defaults: defaults, keys: keys.access)
        let started = expectation(description: "probe reached fixture transport")
        DelayedProbe.started = started
        let check = Task { await settings.check() }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(settings.checkState, .checking)
        try store.save(service(model: "replacement"))
        settings.reload()
        DelayedProbe.pending?.succeed()
        await check.value
        XCTAssertEqual(settings.service?.model, "replacement")
        XCTAssertEqual(settings.checkState, .unchecked)
        XCTAssertNil(store.lastCheck)
    }

    @MainActor
    func testClosingTheConversationClearsParsedAnswers() async {
        let settings = AppSettings(defaults: defaults, keys: keys.access)
        let model = ChatViewModel(settings: settings)
        _ = InkAttributed.make("Synthetic answer used for a cache lifecycle check.")
        XCTAssertFalse(InkAttributed.cache.isEmpty)
        model.reset()
        XCTAssertTrue(InkAttributed.cache.isEmpty)
    }

    @MainActor
    func testProviderKeyEchoIsNotSavedInCheckResults() async throws {
        try store.save(service())
        try store.setAPIKey("fixture-secret-a")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedProbe.self]
        let settings = AppSettings(client: ChatClient(session: URLSession(configuration: configuration)),
                                   defaults: defaults, keys: keys.access)
        let started = expectation(description: "check reached fixture transport")
        DelayedProbe.started = started
        let check = Task { await settings.check() }
        await fulfillment(of: [started], timeout: 3)
        DelayedProbe.pending?.respond(status: 401, body: "{\"error\":{\"message\":\"Rejected fixture-secret-a\"}}")
        await check.value
        guard case .failed(let message) = settings.checkState else { return XCTFail("expected a failed check") }
        XCTAssertTrue(message.contains("Rejected"))
        XCTAssertFalse(message.contains("fixture-secret-a"))
        XCTAssertEqual(store.lastCheck?.passed, false)
        let saved = try XCTUnwrap(defaults.data(forKey: "serviceCheck"))
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("fixture-secret-a"))
    }

    @MainActor
    func testReduceMotionRevealsTextImmediately() async {
        let pacer = QuillPacer()
        pacer.instant = true
        pacer.begin()
        pacer.update(target: 12)
        XCTAssertEqual(pacer.frame.revealed, 12)
        pacer.endStream()
    }
}
