import XCTest
@testable import HowlerCore

final class FeedbackLinkTests: XCTestCase {
    func testOpensTheFeedbackFormWithTheFactsFilledIn() throws {
        let url = FeedbackLink.url(
            project: "https://github.com/HiAriesZhou/Howler",
            version: "0.1.10 (11)", macOS: "26.5.2 (25F84)", architecture: "arm64"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/HiAriesZhou/Howler/issues/new")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items, [
            "template": "feedback.yml",
            "version": "0.1.10 (11)",
            "macos": "26.5.2 (25F84)",
            "arch": "arm64",
        ])
        // Spaces and parentheses are encoded, not left raw.
        XCTAssertFalse(url.absoluteString.contains(" "))
    }
}
