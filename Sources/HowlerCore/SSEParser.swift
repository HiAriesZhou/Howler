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

public enum SSEParserError: Error, Equatable, LocalizedError {
    case lineTooLarge
    case eventTooLarge

    public var errorDescription: String? {
        switch self {
        case .lineTooLarge: return "The server sent a line larger than 1 MiB."
        case .eventTooLarge: return "The server sent an event larger than 1 MiB."
        }
    }
}

/// Incremental Server-Sent Events parser (WHATWG event-stream rules).
///
/// Works on raw bytes so it can be fed straight from `URLSession.AsyncBytes`
/// (whose `.lines` view drops the blank lines that delimit events) and so a
/// multi-byte UTF-8 character split across network chunks decodes correctly.
public struct SSEParser {
    private static let maximumLineBytes = 1024 * 1024
    private static let maximumEventBytes = 1024 * 1024
    private var dataByteCount = 0
    private var dataValueOffset: Int?
    private var line: [UInt8] = []
    private var dataLines: [String] = []
    private var eventType: String?
    private var lastEventID: String?
    private var previousWasCR = false
    private var sawFirstLine = false

    public init() {}

    /// Feeds bytes and returns every event completed by them.
    public mutating func feed<S: Sequence>(_ bytes: S) throws -> [SSEEvent] where S.Element == UInt8 {
        var events: [SSEEvent] = []
        for byte in bytes {
            if let event = try feed(byte) { events.append(event) }
        }
        return events
    }

    public mutating func feed(_ string: String) throws -> [SSEEvent] {
        try feed(string.utf8)
    }

    /// Feeds one byte; returns an event when a blank line completes one.
    public mutating func feed(_ byte: UInt8) throws -> SSEEvent? {
        switch byte {
        case 0x0A: // \n
            if previousWasCR {
                previousWasCR = false // second half of \r\n
                return nil
            }
            return try endLine()
        case 0x0D: // \r
            previousWasCR = true
            return try endLine()
        default:
            previousWasCR = false
            guard line.count < Self.maximumLineBytes else { throw SSEParserError.lineTooLarge }
            line.append(byte)
            try checkPendingEvent()
            return nil
        }
    }

    /// Call at end of stream: dispatches a trailing event that had no blank line after it.
    public mutating func finish() throws -> SSEEvent? {
        if !line.isEmpty {
            try processLine()
        }
        return dispatch()
    }

    private mutating func endLine() throws -> SSEEvent? {
        if line.isEmpty {
            return dispatch()
        }
        try processLine()
        return nil
    }

    private mutating func checkPendingEvent() throws {
        if (line.count == 5 && line == [0x64, 0x61, 0x74, 0x61, 0x3A]) ||
            (!sawFirstLine && line.count == 8 && line == [0xEF, 0xBB, 0xBF, 0x64, 0x61, 0x74, 0x61, 0x3A]) {
            dataValueOffset = line.count
        }
        guard var offset = dataValueOffset else { return }
        if (offset == 5 || offset == 8), line.count == offset + 1, line.last == 0x20 {
            offset += 1
            dataValueOffset = offset
        }
        let byteCount = line.count - offset + (dataLines.isEmpty ? 0 : 1)
        guard byteCount <= Self.maximumEventBytes - dataByteCount else {
            throw SSEParserError.eventTooLarge
        }
    }

    private mutating func processLine() throws {
        dataValueOffset = nil
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
        case "data":
            let byteCount = value.utf8.count + (dataLines.isEmpty ? 0 : 1)
            guard byteCount <= Self.maximumEventBytes - dataByteCount else {
                throw SSEParserError.eventTooLarge
            }
            dataByteCount += byteCount
            dataLines.append(String(value))
        case "event": eventType = String(value)
        case "id": if !value.contains("\0") { lastEventID = String(value) }
        default: break // "retry" and unknown fields are ignored
        }
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            dataLines.removeAll()
            dataByteCount = 0
            eventType = nil
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventType, data: dataLines.joined(separator: "\n"), id: lastEventID)
    }
}
