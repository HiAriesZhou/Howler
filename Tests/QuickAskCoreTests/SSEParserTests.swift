import XCTest
@testable import QuickAskCore

final class SSEParserTests: XCTestCase {
    func testParsesEventsSeparatedByBlankLines() {
        var parser = SSEParser()
        let events = parser.feed("data: one\n\ndata: two\n\n")
        XCTAssertEqual(events, [SSEEvent(data: "one"), SSEEvent(data: "two")])
    }

    func testEventFieldAndMultilineData() {
        var parser = SSEParser()
        let events = parser.feed("event: message_start\ndata: a\ndata: b\nid: 7\n\n")
        XCTAssertEqual(events, [SSEEvent(event: "message_start", data: "a\nb", id: "7")])
    }

    func testCRLFAndCRLineEndings() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: crlf\r\n\r\n"), [SSEEvent(data: "crlf")])
        XCTAssertEqual(parser.feed("data: cr\r\r"), [SSEEvent(data: "cr")])
    }

    func testCRLFSplitAcrossChunks() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: x\r"), [])
        // The "\n" completes the first CRLF; the following "\r" is the blank line.
        XCTAssertEqual(parser.feed("\n\r"), [SSEEvent(data: "x")])
        // Second half of the blank line's CRLF must not produce anything.
        XCTAssertEqual(parser.feed("\n"), [])
    }

    func testIgnoresCommentsAndUnknownFields() {
        var parser = SSEParser()
        let events = parser.feed(": OPENROUTER PROCESSING\n\nretry: 1000\nfoo: bar\ndata: real\n\n")
        XCTAssertEqual(events, [SSEEvent(data: "real")])
    }

    func testValueWithoutSpaceAndColonsInValue() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data:{\"a\":\"b: c\"}\n\n"), [SSEEvent(data: "{\"a\":\"b: c\"}")])
    }

    func testByteByByteWithMultibyteUTF8Split() {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for byte in Array("data: 你好 👋\n\n".utf8) {
            if let event = parser.feed(byte) { events.append(event) }
        }
        XCTAssertEqual(events, [SSEEvent(data: "你好 👋")])
    }

    func testFinishFlushesTrailingEventWithoutBlankLine() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("data: tail"), [])
        XCTAssertEqual(parser.finish(), SSEEvent(data: "tail"))
        XCTAssertNil(parser.finish())
    }

    func testEventTypeResetsBetweenEvents() {
        var parser = SSEParser()
        let events = parser.feed("event: ping\ndata: {}\n\ndata: plain\n\n")
        XCTAssertEqual(events.map(\.event), ["ping", nil])
    }

    func testStripsLeadingBOM() {
        var parser = SSEParser()
        let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("data: bom\n\n".utf8)
        XCTAssertEqual(parser.feed(bytes), [SSEEvent(data: "bom")])
    }

    func testBlankLineWithoutDataDispatchesNothing() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed("\n\nevent: x\n\n"), [])
    }
}
