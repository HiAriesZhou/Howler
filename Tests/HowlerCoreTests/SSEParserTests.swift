import XCTest
@testable import HowlerCore

final class SSEParserTests: XCTestCase {
    func testParsesEventsSeparatedByBlankLines() throws {
        var parser = SSEParser()
        let events = try parser.feed("data: one\n\ndata: two\n\n")
        XCTAssertEqual(events, [SSEEvent(data: "one"), SSEEvent(data: "two")])
    }

    func testEventFieldAndMultilineData() throws {
        var parser = SSEParser()
        let events = try parser.feed("event: message_start\ndata: a\ndata: b\nid: 7\n\n")
        XCTAssertEqual(events, [SSEEvent(event: "message_start", data: "a\nb", id: "7")])
    }

    func testCRLFAndCRLineEndings() throws {
        var parser = SSEParser()
        XCTAssertEqual(try parser.feed("data: crlf\r\n\r\n"), [SSEEvent(data: "crlf")])
        XCTAssertEqual(try parser.feed("data: cr\r\r"), [SSEEvent(data: "cr")])
    }

    func testCRLFSplitAcrossChunks() throws {
        var parser = SSEParser()
        XCTAssertEqual(try parser.feed("data: x\r"), [])
        // The "\n" completes the first CRLF; the following "\r" is the blank line.
        XCTAssertEqual(try parser.feed("\n\r"), [SSEEvent(data: "x")])
        // Second half of the blank line's CRLF must not produce anything.
        XCTAssertEqual(try parser.feed("\n"), [])
    }

    func testIgnoresCommentsAndUnknownFields() throws {
        var parser = SSEParser()
        let events = try parser.feed(": OPENROUTER PROCESSING\n\nretry: 1000\nfoo: bar\ndata: real\n\n")
        XCTAssertEqual(events, [SSEEvent(data: "real")])
    }

    func testValueWithoutSpaceAndColonsInValue() throws {
        var parser = SSEParser()
        XCTAssertEqual(try parser.feed("data:{\"a\":\"b: c\"}\n\n"), [SSEEvent(data: "{\"a\":\"b: c\"}")])
    }

    func testByteByByteWithMultibyteUTF8Split() throws {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for byte in Array("data: 你好 👋\n\n".utf8) {
            if let event = try parser.feed(byte) { events.append(event) }
        }
        XCTAssertEqual(events, [SSEEvent(data: "你好 👋")])
    }

    func testFinishFlushesTrailingEventWithoutBlankLine() throws {
        var parser = SSEParser()
        XCTAssertEqual(try parser.feed("data: tail"), [])
        XCTAssertEqual(try parser.finish(), SSEEvent(data: "tail"))
        XCTAssertNil(try parser.finish())
    }

    func testEventTypeResetsBetweenEvents() throws {
        var parser = SSEParser()
        let events = try parser.feed("event: ping\ndata: {}\n\ndata: plain\n\n")
        XCTAssertEqual(events.map(\.event), ["ping", nil])
    }

    func testStripsLeadingBOM() throws {
        var parser = SSEParser()
        let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("data: bom\n\n".utf8)
        XCTAssertEqual(try parser.feed(bytes), [SSEEvent(data: "bom")])
    }

    func testBlankLineWithoutDataDispatchesNothing() throws {
        var parser = SSEParser()
        XCTAssertEqual(try parser.feed("\n\nevent: x\n\n"), [])
    }
}

final class SSEParserBoundaryTests: XCTestCase {
    private let limit = 1024 * 1024

    func testLineAtLimitAcceptsASplitMultibyteCharacterAndCRLF() throws {
        var parser = SSEParser()
        let text = String(repeating: "a", count: limit - 10) + "👋"
        let bytes = Array(("data: " + text).utf8)
        XCTAssertEqual(bytes.count, limit)
        XCTAssertTrue(try parser.feed(bytes.dropLast(2)).isEmpty)
        XCTAssertTrue(try parser.feed(bytes.suffix(2)).isEmpty)
        let events = try parser.feed("\r\n\r\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, text)
    }

    func testLineOverLimitThrowsBeforeAnyNewline() throws {
        var parser = SSEParser()
        XCTAssertTrue(try parser.feed(repeatElement(UInt8(0x61), count: limit)).isEmpty)
        XCTAssertThrowsError(try parser.feed(UInt8(0x61))) {
            XCTAssertEqual($0.localizedDescription, "The server sent a line larger than 1 MiB.")
        }
    }

    func testMultibyteLineOverLimitCountsUTF8Bytes() throws {
        var parser = SSEParser()
        let line = "data: " + String(repeating: "界", count: (limit - 6) / 3)
        XCTAssertTrue(try parser.feed(line).isEmpty)
        let remaining = limit - line.utf8.count
        XCTAssertTrue(try parser.feed(repeatElement(UInt8(0x61), count: remaining)).isEmpty)
        XCTAssertThrowsError(try parser.feed(UInt8(0xE7)))
    }

    func testCommentsAndUnknownFieldsHaveTheSameLineLimit() throws {
        for prefix in [":", "unknown:", "event:", "id:"] {
            var parser = SSEParser()
            XCTAssertTrue(try parser.feed(prefix + String(repeating: "a", count: limit - prefix.utf8.count)).isEmpty)
            XCTAssertThrowsError(try parser.feed(UInt8(0x61)), prefix)
        }
    }

    func testEventAtLimitIncludesJoinedNewlinesAndResetsAfterDispatch() throws {
        var parser = SSEParser()
        let first = String(repeating: "a", count: limit / 2)
        let second = String(repeating: "界", count: (limit / 2 - 1) / 3)
            + String(repeating: "b", count: (limit / 2 - 1) % 3)
        XCTAssertTrue(try parser.feed("data: \(first)\ndata: \(second)\n").isEmpty)
        let events = try parser.feed("\ndata: next\n\n")
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.data.utf8.count, limit)
        XCTAssertEqual(events.last?.data, "next")
    }

    func testMultipleDataLinesOverLimitThrowWithoutDispatch() throws {
        var parser = SSEParser()
        let half = String(repeating: "a", count: limit / 2)
        XCTAssertTrue(try parser.feed("data: \(half)\n").isEmpty)
        XCTAssertThrowsError(try parser.feed("data: \(half)\n")) {
            XCTAssertEqual($0.localizedDescription, "The server sent an event larger than 1 MiB.")
        }
    }

    func testAccumulatedDataLimitThrowsBeforeTheNextLineEnds() throws {
        var parser = SSEParser()
        let half = String(repeating: "a", count: limit / 2)
        XCTAssertTrue(try parser.feed("data: \(half)\n").isEmpty)
        XCTAssertThrowsError(try parser.feed("data: \(half)"))
    }

    func testFinishCountsUTF8ReplacementBytesTowardTheEventLimit() throws {
        var parser = SSEParser()
        let half = String(repeating: "a", count: limit / 2)
        let almostHalf = String(repeating: "a", count: limit / 2 - 4)
        XCTAssertTrue(try parser.feed("data: \(half)\ndata: \(almostHalf)\ndata: ").isEmpty)
        XCTAssertNil(try parser.feed(UInt8(0xFF)))
        XCTAssertThrowsError(try parser.finish())
    }

    func testBOMAndTheOptionalSpaceDoNotChangeTheEventPayloadBudget() throws {
        var parser = SSEParser()
        let first = String(repeating: "a", count: limit / 2)
        let second = " " + String(repeating: "b", count: limit / 2 - 2)
        XCTAssertTrue(try parser.feed("\u{FEFF}data: \(first)\ndata: \(second)").isEmpty)
        let event = try parser.finish()
        XCTAssertEqual(event?.data.utf8.count, limit)
        XCTAssertTrue(event?.data.hasSuffix(second) == true)
    }

    func testManyEmptyDataLinesCountTheirJoinedNewlines() throws {
        var parser = SSEParser()
        for _ in 0...limit {
            _ = try parser.feed("data:\n")
        }
        XCTAssertThrowsError(try parser.feed("data:\n"))
    }
}
