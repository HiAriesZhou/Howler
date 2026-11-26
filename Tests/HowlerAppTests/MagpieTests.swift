import XCTest
import HowlerCore
@testable import Howler

@MainActor
final class MagpieTests: XCTestCase {
    func testStagingThroughCLILeavesSubscriptionAndItsCheckActive() throws {
        let defaults = DemoDefaults(suiteName: "HowlerTests.Stage")!
        let store = ServiceStore(defaults: defaults, keys: MemoryKeys().access)
        let subscription = MagpieSelection(port: 3425, model: "sample/vision")
        try store.selectMagpie(subscription)
        let revision = store.revision
        store.recordCheck(passed: true, message: nil, for: revision)

        XCTAssertEqual(CLI.run(["Howler", "config", "stage", "preset=openai", "model=fixture"], store: store), 0)
        XCTAssertEqual(store.pendingDirectService, Provider.openAI.service(model: "fixture"))
        XCTAssertEqual(store.service, subscription.service)
        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(store.lastCheck?.passed, true)
    }

    func testReplacingPreparedModelRejectsOldActivationBeforeWritingKey() throws {
        let defaults = DemoDefaults(suiteName: "HowlerTests.ReplaceDraft")!
        let keys = MemoryKeys()
        let store = ServiceStore(defaults: defaults, keys: keys.access)
        let subscription = MagpieSelection(port: 3425, model: "sample/vision")
        try store.selectMagpie(subscription)
        let first = Provider.openAI.service(model: "first")
        let second = Provider.openAI.service(model: "second")
        try store.stageDirectService(first)
        let revision = store.revision
        try store.stageDirectService(second)

        XCTAssertThrowsError(try store.activateCheckedDirectService(first, key: "fixture-key", for: revision, pending: first))
        XCTAssertTrue(keys.values.isEmpty)
        XCTAssertEqual(store.service, subscription.service)
        XCTAssertEqual(store.pendingDirectService, second)
    }

    func testSaveAndCheckActivatesPreparedModelOnlyAfterSuccessfulProbe() async throws {
        let defaults = DemoDefaults(suiteName: "HowlerTests.Activate")!
        let keys = MemoryKeys()
        let store = ServiceStore(defaults: defaults, keys: keys.access)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedProbe.self]
        let settings = AppSettings(client: ChatClient(session: URLSession(configuration: configuration)),
                                   defaults: defaults, keys: keys.access)
        let subscription = MagpieSelection(port: 3425, model: "sample/vision")
        try settings.selectMagpie(subscription)
        let service = Provider.openAI.service(model: "fixture")
        try store.stageDirectService(service)
        settings.reload()
        defer {
            DelayedProbe.started = nil
            DelayedProbe.pending = nil
        }

        for succeeds in [false, true] {
            let started = expectation(description: "candidate probe started")
            DelayedProbe.started = started
            let revision = settings.serviceRevision
            let save = Task {
                try await settings.checkAndActivateDirectService(service, key: "fixture-key", for: revision, pending: service)
            }
            await fulfillment(of: [started], timeout: 3)
            let probe = try XCTUnwrap(DelayedProbe.pending)
            XCTAssertEqual(probe.request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
            XCTAssertEqual(settings.service, subscription.service)
            XCTAssertTrue(keys.values.isEmpty)
            if succeeds {
                probe.succeed()
                try await save.value
                XCTAssertEqual(settings.service, service)
                XCTAssertEqual(store.apiKey(), "fixture-key")
                XCTAssertEqual(store.lastCheck?.passed, true)
                XCTAssertNil(store.pendingDirectService)
                XCTAssertEqual(store.lastMagpieSelection, subscription)
            } else {
                probe.respond(status: 401, body: #"{"error":{"message":"Rejected fixture"}}"#)
                do {
                    try await save.value
                    XCTFail("A failed probe must prevent activation")
                } catch let error as ChatClientError {
                    guard case .http(401, _) = error else { throw error }
                }
                XCTAssertEqual(settings.service, subscription.service)
                XCTAssertEqual(store.pendingDirectService, service)
                XCTAssertTrue(keys.values.isEmpty)
            }
        }
    }

    func testManualKeychainFailureKeepsSelectedSubscription() throws {
        let suite = "HowlerTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var keys = MemoryKeys().access
        keys.set = { _, _ in throw ConfigurationFailure.busy }
        let store = ServiceStore(defaults: defaults, keys: keys)
        let subscription = MagpieSelection(port: 3425, model: "sample/vision")
        try store.selectMagpie(subscription)
        XCTAssertThrowsError(try store.saveDirectService(Provider.openAI.service(), key: "fixture", for: store.revision))
        XCTAssertEqual(store.service, subscription.service)
        XCTAssertNil(store.directService)
    }

    func testManualServiceRequiresNewKeyForNewHost() throws {
        let suite = "HowlerTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ServiceStore(defaults: defaults, keys: MemoryKeys().access)
        let original = Provider.anthropic.service()
        try store.saveDirectService(original, key: "first-fixture", for: store.revision)
        let edited = Provider.anthropic.service(model: "another-model")
        try store.saveDirectService(edited, key: "", for: store.revision)
        XCTAssertEqual(store.apiKey(), "first-fixture")
        let next = Provider.openAI.service()
        XCTAssertThrowsError(try store.saveDirectService(next, key: "", for: store.revision))
        XCTAssertEqual(store.service, edited)
        XCTAssertEqual(store.apiKey(), "first-fixture")
        try store.saveDirectService(next, key: "next-fixture", for: store.revision)
        XCTAssertEqual(store.service, next)
        XCTAssertEqual(store.apiKey(), "next-fixture")
    }

    func testSelectingMagpiePreservesDirectServiceAndNeverForwardsItsKey() throws {
        let suite = "HowlerTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ServiceStore(defaults: defaults, keys: MemoryKeys().access)
        let direct = Provider.anthropic.service()
        try store.save(direct)
        try store.setAPIKey("fixture")
        let selection = MagpieSelection(port: 3425, model: "sample/vision")
        try store.selectMagpie(selection)
        XCTAssertEqual(store.service, selection.service)
        XCTAssertNil(store.apiKey())
        for key in ["", "fixture"] {
            let request = try RequestBuilder.streamingRequest(service: selection.service, apiKey: key,
                                                              messages: [.init(role: .user, content: "hello")])
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        }
        try store.selectMagpie(nil)
        XCTAssertEqual(store.service, direct)
        XCTAssertEqual(store.apiKey(), "fixture")
        XCTAssertEqual(store.lastMagpieSelection, selection)
        try store.selectMagpie(selection)
        try store.save(ServiceConfig.apply(["model=updated"], to: store.directService))
        XCTAssertEqual(store.service?.baseURL, direct.baseURL)
        XCTAssertEqual(store.apiKey(), "fixture")
    }
}
