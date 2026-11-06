import AppKit
import Security
import SwiftUI
import XCTest
import HowlerCore
@testable import Howler

@MainActor
final class NativeKeySetupTests: XCTestCase {
    private func service(_ host: String = "model.example") -> ModelService {
        .init(format: .openAICompatible, baseURL: URL(string: "https://\(host)")!, model: "fixture")
    }

    func testConnectionProbeHasTotalDeadlineEvenWithoutResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SilentSetupProbe.self]
        let client = ChatClient(session: URLSession(configuration: configuration))
        let started = Date()
        do {
            try await ConnectionTester.test(client: client, service: service(), apiKey: "synthetic",
                                            deadline: .milliseconds(50))
            XCTFail("Expected deadline")
        } catch {
            XCTAssertEqual(error as? ConnectionTesterError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testNativeSaveValidatesAndRejectsChangedDestination() async throws {
        let defaults = DemoDefaults(suiteName: "HowlerTests.NativeSave")!
        let keys = MemoryKeys()
        let store = ServiceStore(defaults: defaults, keys: keys.access)
        let original = service()
        try store.save(original)
        try store.setAPIKey("old-synthetic")
        let settings = AppSettings(defaults: defaults, keys: keys.access)
        let before = settings.connectionVersion
        for invalid in [" \n ", "two keys"] {
            do {
                try await settings.saveAPIKey(invalid, for: original)
                XCTFail("Invalid key should fail")
            } catch {}
            XCTAssertEqual(store.apiKey(), "old-synthetic")
        }
        try await settings.saveAPIKey("  new-synthetic\n", for: original)
        XCTAssertEqual(store.apiKey(), "new-synthetic")
        XCTAssertNotEqual(settings.connectionVersion, before)
        XCTAssertFalse(settings.isSavingAPIKey)

        try store.save(service("other.example"))
        do {
            try await settings.saveAPIKey("wrong-destination", for: original)
            XCTFail("A stale editor must not save for another service")
        } catch {}
        XCTAssertFalse(keys.values.values.contains("wrong-destination"))
        XCTAssertNil(store.apiKey())
    }

    func testExplicitCheckDoesNotTrustCachedKeyAndRecordsReadFailure() async throws {
        let defaults = DemoDefaults(suiteName: "HowlerTests.FreshCheck")!
        let keys = MemoryKeys()
        var deny = false
        var access = keys.access
        access.get = { account in
            if deny { throw KeychainError(status: errSecAuthFailed, operation: "read") }
            return keys.values[account]
        }
        let store = ServiceStore(defaults: defaults, keys: access)
        try store.save(service())
        try store.setAPIKey("synthetic")
        let settings = AppSettings(defaults: defaults, keys: access)
        XCTAssertEqual(settings.apiKey(), "synthetic")
        store.recordCheck(passed: true, message: nil, for: store.revision)
        deny = true
        await settings.check()
        guard case .failed(let message) = settings.checkState else {
            return XCTFail("Expected a readable Keychain failure")
        }
        XCTAssertTrue(message.contains("-25293"))
        XCTAssertEqual(store.lastCheck?.passed, false)
        XCTAssertTrue(settings.hasKey, "Presence is separate from readability")
        XCTAssertNil(settings.apiKey())
        XCTAssertTrue(settings.keyAccessError?.contains("-25293") == true)
    }

    func testDeniedNativeSaveKeepsOldKeyAndEndsBusyState() async throws {
        let defaults = DemoDefaults(suiteName: "HowlerTests.DeniedNativeSave")!
        let keys = MemoryKeys()
        let store = ServiceStore(defaults: defaults, keys: keys.access)
        try store.save(service())
        try store.setAPIKey("old-synthetic")
        var access = keys.access
        access.set = { _, _ in throw KeychainError(status: errSecUserCanceled, operation: "save") }
        let settings = AppSettings(defaults: defaults, keys: access)
        do {
            try await settings.saveAPIKey("new-synthetic", for: service())
            XCTFail("Expected cancelled save")
        } catch {
            XCTAssertEqual((error as? KeychainError)?.status, errSecUserCanceled)
        }
        XCTAssertEqual(store.apiKey(), "old-synthetic")
        XCTAssertFalse(settings.isSavingAPIKey)
    }

    func testEditorNeverLoadsExistingKeyAndRendersSecureField() async throws {
        _ = NSApplication.shared
        let defaults = DemoDefaults(suiteName: "HowlerTests.KeyEditor")!
        let keys = MemoryKeys()
        let store = ServiceStore(defaults: defaults, keys: keys.access)
        try store.save(service())
        try store.setAPIKey("never-display-existing-synthetic")
        var reads = 0
        var access = keys.access
        access.get = { _ in reads += 1; return "never-display-existing-synthetic" }
        let settings = AppSettings(defaults: defaults, keys: access)
        let host = NSHostingView(rootView: APIKeyEditor(settings: settings, service: service()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        func secureFields(_ view: NSView) -> [NSSecureTextField] {
            (view as? NSSecureTextField).map { [$0] } ?? view.subviews.flatMap(secureFields)
        }
        let field = try XCTUnwrap(secureFields(host).first)
        XCTAssertEqual(field.stringValue, "")
        XCTAssertEqual(reads, 0)
        if let folder = ProcessInfo.processInfo.environment["HOWLER_TEST_SNAPSHOTS"] {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                window.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(50))
                host.display()
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(folder)/key-editor-\(name).png"))
                }
            }
        }
    }
}

private final class SilentSetupProbe: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
