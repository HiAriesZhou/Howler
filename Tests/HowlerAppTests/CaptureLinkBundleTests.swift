import XCTest

final class CaptureLinkBundleTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func generatedPlist() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("scripts/info-plist.sh").path]
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0,
                       String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        return data
    }

    private func registersCaptureLink(_ data: Data) throws -> Bool {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let types = plist["CFBundleURLTypes"] as? [[String: Any]] else { return false }
        return types.contains { type in
            (type["CFBundleURLSchemes"] as? [String])?.contains("howler") == true
        }
    }

    func testTheAppBundleRegistersTheCaptureLink() throws {
        let data = try generatedPlist()
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "Howler")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        let types = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertEqual(types.count, 1)
        XCTAssertEqual(types.first?["CFBundleURLName"] as? String, plist["CFBundleIdentifier"] as? String)
        XCTAssertEqual(types.first?["CFBundleURLSchemes"] as? [String], ["howler"])
        XCTAssertTrue(try registersCaptureLink(data))
    }

    func testCaptureSchemeInsideAnUnrelatedOuterDictionaryIsNotRegistered() throws {
        let generated = try XCTUnwrap(PropertyListSerialization.propertyList(from: generatedPlist(), format: nil) as? [String: Any])
        let invalid = ["UnrelatedOuterKey": generated]
        let data = try PropertyListSerialization.data(fromPropertyList: invalid, format: .xml, options: 0)
        XCTAssertFalse(try registersCaptureLink(data))
    }

    func testCaptureSchemeWithoutURLTypesIsNotRegistered() throws {
        let invalid: [String: Any] = ["CFBundleURLSchemes": ["howler"]]
        let data = try PropertyListSerialization.data(fromPropertyList: invalid, format: .xml, options: 0)
        XCTAssertFalse(try registersCaptureLink(data))
    }

    func testCaptureSchemeInAWronglyTypedURLTypesDictionaryIsNotRegistered() throws {
        let invalid: [String: Any] = ["CFBundleURLTypes": ["CFBundleURLSchemes": ["howler"]]]
        let data = try PropertyListSerialization.data(fromPropertyList: invalid, format: .xml, options: 0)
        XCTAssertFalse(try registersCaptureLink(data))
    }
}
