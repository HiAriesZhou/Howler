import XCTest

final class CaptureLinkBundleTests: XCTestCase {
    func testTheAppBundleRegistersTheCaptureLink() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/bundle.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("<key>CFBundleURLSchemes</key>"))
        XCTAssertTrue(script.contains("<string>howler</string>"))
    }
}
