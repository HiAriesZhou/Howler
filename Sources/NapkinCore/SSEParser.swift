import Foundation

public struct SSEEvent: Equatable, Sendable {
    public var event: String?
    public var data: String
    public var id: String?

    public init(event: String? = nil, data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

/// Incremental Server-Sent Events parser (WHATWG event-stream rules).
///
/// Works on raw bytes so it can be fed straight from `URLSession.AsyncBytes`
/// (whose `.lines` view drops the blank lines that delimit events) and so a
/// multi-byte UTF-8 character split across network chunks decodes correctly.
public struct SSEParser {
    private var line: [UInt8] = []
    private var dataLines: [String] = []
    private var eventType: String?
    private var lastEventID: String?
    private var previousWasCR = false
    private var sawFirstLine = false

    public init() {}

    /// Feeds bytes and returns every event completed by them.
    public mutating func feed<S: Sequence>(_ bytes: S) -> [SSEEvent] where S.Element == UInt8 {
        var events: [SSEEvent] = []
        for byte in bytes {
            if let event = feed(byte) { events.append(event) }
        }
        return events
    }

    public mutating func feed(_ string: String) -> [SSEEvent] {
        feed(Array(string.utf8))
    }

    /// Feeds one byte; returns an event when a blank line completes one.
    public mutating func feed(_ byte: UInt8) -> SSEEvent? {
        switch byte {
        case 0x0A: // \n
            if previousWasCR {
                previousWasCR = false // second half of \r\n
                return nil
            }
            return endLine()
        case 0x0D: // \r
            previousWasCR = true
            return endLine()
        default:
            previousWasCR = false
            line.append(byte)
            return nil
        }
    }

    /// Call at end of stream: dispatches a trailing event that had no blank line after it.
    public mutating func finish() -> SSEEvent? {
        if !line.isEmpty {
            processLine()
        }
        return dispatch()
    }

    private mutating func endLine() -> SSEEvent? {
        if line.isEmpty {
            return dispatch()
        }
        processLine()
        return nil
    }

    private mutating func processLine() {
        var bytes = line
        line.removeAll(keepingCapacity: true)
        if !sawFirstLine {
            sawFirstLine = true
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        }
        let text = String(decoding: bytes, as: UTF8.self)
        if text.hasPrefix(":") { return } // comment / keep-alive

        let field: Substring
        var value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[..<colon]
            value = text[text.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(text)
            value = ""
        }

        switch field {
        case "data": dataLines.append(String(value))
        case "event": eventType = String(value)
        case "id": if !value.contains("\0") { lastEventID = String(value) }
        default: break // "retry" and unknown fields are ignored
        }
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            dataLines.removeAll()
            eventType = nil
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventType, data: dataLines.joined(separator: "\n"), id: lastEventID)
    }
}
