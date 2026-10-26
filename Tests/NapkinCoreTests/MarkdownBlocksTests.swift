import XCTest
@testable import NapkinCore

final class MarkdownBlocksTests: XCTestCase {
    func testSplitsProseAndCode() {
        let markdown = """
        Here is code:

        ```swift
        let x = 1
        ```
        Done.
        """
        XCTAssertEqual(MarkdownBlocks.parse(markdown), [
            .prose("Here is code:"),
            .code(language: "swift", code: "let x = 1"),
            .prose("Done."),
        ])
    }

    func testUnterminatedFenceWhileStreaming() {
        XCTAssertEqual(MarkdownBlocks.parse("```\nprint(1)"), [.code(language: nil, code: "print(1)")])
    }

    func testBlockSyntaxRewrites() {
        XCTAssertEqual(MarkdownBlocks.parse("## Title\n- a\n  * b\n---"), [
            .prose("**Title**\n• a\n  • b\n──────────"),
        ])
    }

    func testInlineMarkdownIsLeftAlone() {
        XCTAssertEqual(MarkdownBlocks.parse("**bold** and `code`"), [.prose("**bold** and `code`")])
    }
}
