import XCTest
@testable import HowlerCore

final class PastedTextTests: XCTestCase {
    func testALoneLinkLetsThePictureWin() {
        // What browsers put beside a copied image.
        XCTAssertTrue(PastedText.isLoneLink("https://example.com/cat.png"))
        XCTAssertTrue(PastedText.isLoneLink("  https://example.com/a?b=1&c=2\n"))
        XCTAssertTrue(PastedText.isLoneLink("file:///Users/me/Desktop/shot.png"))
        XCTAssertTrue(PastedText.isLoneLink(""))
    }

    func testRealTextStaysText() {
        // Office apps copy text with a picture of it; the text is what was meant.
        XCTAssertFalse(PastedText.isLoneLink("Quarterly results"))
        XCTAssertFalse(PastedText.isLoneLink("see https://example.com for details"))
        XCTAssertFalse(PastedText.isLoneLink("https://a.com\nhttps://b.com"))
        XCTAssertFalse(PastedText.isLoneLink("example.com"))
        XCTAssertFalse(PastedText.isLoneLink("mailto:me@example.com"))
    }
}

final class PasteSealingTests: XCTestCase {
    func testLongOrMultiLinePastesAreSealed() {
        XCTAssertTrue(PastedText.belongsInAttachment(String(repeating: "a", count: 280)))
        // A copied answer: short, but several lines of Markdown.
        XCTAssertTrue(PastedText.belongsInAttachment("\"Howler\" 常见意思有：\n1. **大声哭喊**\n2. **大错**"))
    }

    func testShortPastesStayInTheQuestion() {
        XCTAssertFalse(PastedText.belongsInAttachment("what does howler mean"))
        XCTAssertFalse(PastedText.belongsInAttachment("first line\nsecond line"))
        XCTAssertFalse(PastedText.belongsInAttachment("trailing newlines\n\n\n"))
    }
}
