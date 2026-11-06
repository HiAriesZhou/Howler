import Security
import XCTest
@testable import Howler

final class KeychainFailureTests: XCTestCase {
    func testDeniedReplacementNeverDeletesOrRecreatesExistingItem() {
        for status in [errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled] {
            var calls: [String] = []
            var existingItem = true
            let operations = Keychain.Operations(
                update: { _, _ in calls.append("update"); return status },
                add: { _, _ in calls.append("add"); return errSecAuthFailed },
                delete: { _ in calls.append("delete"); existingItem = false; return errSecSuccess }
            )
            XCTAssertThrowsError(try Keychain.set("synthetic", account: "fixture", operations: operations))
            XCTAssertEqual(calls, ["update"], "Denied access must not trigger replacement")
            XCTAssertTrue(existingItem, "A failed save must retain the old item")
        }
    }

    func testOnlyMissingItemsAreAdded() throws {
        var additions = 0
        let operations = Keychain.Operations(
            update: { _, _ in errSecItemNotFound },
            add: { _, _ in additions += 1; return errSecSuccess },
            delete: { _ in XCTFail("Unexpected delete"); return errSecSuccess }
        )
        try Keychain.set("synthetic", account: "fixture", operations: operations)
        XCTAssertEqual(additions, 1)
    }

    func testReadDistinguishesMissingFromDeniedAndMalformedItems() throws {
        let missing = Keychain.Operations(copy: { _, _ in errSecItemNotFound })
        XCTAssertNil(try Keychain.get(account: "fixture", operations: missing))
        for status in [errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled] {
            let denied = Keychain.Operations(copy: { _, _ in status })
            XCTAssertThrowsError(try Keychain.get(account: "fixture", operations: denied)) { error in
                XCTAssertEqual((error as? KeychainError)?.status, status)
                XCTAssertTrue(error.localizedDescription.contains(String(status)))
            }
        }
        let malformed = Keychain.Operations(copy: { _, result in
            result?.pointee = Data([0xff]) as CFData
            return errSecSuccess
        })
        XCTAssertThrowsError(try Keychain.get(account: "fixture", operations: malformed))
    }

    func testCLIDeniedReadReplacesStaleSuccessWithoutWritingKeys() throws {
        let defaults = DemoDefaults(suiteName: "HowlerTests.DeniedCLI")!
        var denied = false
        var writes = 0
        let store = ServiceStore(defaults: defaults, keys: .init(
            exists: { $0.hasPrefix("api-key:") },
            get: { _ in
                if denied { throw KeychainError(status: errSecAuthFailed, operation: "read") }
                return "synthetic"
            },
            set: { _, _ in writes += 1 },
            delete: { _ in XCTFail("No key deletion expected") }
        ))
        try store.save(.init(format: .openAICompatible, baseURL: URL(string: "https://model.example")!, model: "fixture"))
        try store.setAPIKey("synthetic")
        store.recordCheck(passed: true, message: nil, for: store.revision)
        denied = true
        XCTAssertTrue(store.hasKey)
        XCTAssertThrowsError(try store.readAPIKey())
        XCTAssertEqual(CLI.run(["Howler", "check", "--verbose"], store: store), 1)
        XCTAssertEqual(store.lastCheck?.passed, false)
        XCTAssertTrue(store.lastCheck?.message?.contains("-25293") == true)
        XCTAssertEqual(writes, 1, "Reading a blocked item must not try to replace it")
    }
}
