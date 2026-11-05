import Foundation

/// An immutable submitted question plus its in-memory answer. No credentials are kept here.
public struct ConversationTask: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable { case question, screenshotIntroduction }
    public enum State: Equatable, Sendable {
        case queued, generating, revealing, completed, paused, skipped
    }

    public let id: UUID
    public let replyID: UUID
    public let kind: Kind
    public let question: String
    public let attachment: ContextAttachment?
    public let imageID: UUID?
    public let language: String
    public let systemPrompt: String?
    public internal(set) var answer = ""
    public internal(set) var state: State = .queued
    public internal(set) var issue: String?

    public init(id: UUID = UUID(), kind: Kind = .question, question: String,
                attachment: ContextAttachment? = nil, imageID: UUID? = nil,
                language: String = "en", systemPrompt: String? = nil) {
        self.id = id
        replyID = UUID()
        self.kind = kind
        self.question = question
        self.attachment = attachment
        self.imageID = imageID
        self.language = language
        self.systemPrompt = systemPrompt
    }
}

/// Serial generation and presentation. Each attempt has a new token, including retries.
/// A stale transport or animation completion cannot mutate a later attempt or conversation.
public struct ConversationQueue: Equatable, Sendable {
    public private(set) var tasks: [ConversationTask] = []
    public private(set) var runID: UUID?
    public private(set) var activeID: UUID?
    public private(set) var isPaused = false
    public private(set) var pauseReason: String?

    public init() {}

    public var active: ConversationTask? { tasks.first { $0.id == activeID } }
    public var waiting: [ConversationTask] { tasks.filter { $0.state == .queued } }

    public mutating func enqueue(_ task: ConversationTask) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
    }

    @discardableResult
    public mutating func startNext() -> UUID? {
        guard !isPaused, runID == nil,
              let index = tasks.firstIndex(where: { $0.state == .queued }) else { return nil }
        activeID = tasks[index].id
        runID = UUID()
        tasks[index].state = .generating
        return runID
    }

    public mutating func append(_ delta: String, for token: UUID) {
        guard token == runID, let index = activeIndex, tasks[index].state == .generating else { return }
        tasks[index].answer += delta
    }

    public mutating func generated(for token: UUID) {
        guard token == runID, let index = activeIndex, tasks[index].state == .generating else { return }
        if tasks[index].answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pause(reason: "The model returned no text. Retry or skip this reply.")
        } else {
            tasks[index].state = .revealing
        }
    }

    public mutating func presented(for token: UUID) {
        guard token == runID, let index = activeIndex, tasks[index].state == .revealing else { return }
        tasks[index].state = .completed
        runID = nil
        activeID = nil
    }

    public mutating func pause(reason: String) {
        isPaused = true
        pauseReason = reason
        if let index = activeIndex {
            tasks[index].state = .paused
            tasks[index].issue = reason
        }
        runID = nil
    }

    public mutating func retry() {
        guard isPaused, let index = activeIndex else { return }
        tasks[index].answer = ""
        tasks[index].issue = nil
        tasks[index].state = .queued
        resume()
    }

    /// Keep a partial answer as explicitly incomplete context, then allow the next task.
    public mutating func skip() {
        guard isPaused else { return }
        if let index = activeIndex {
            tasks[index].state = .skipped
            tasks[index].issue = "Incomplete reply"
        }
        resume()
    }

    /// Restore an unstarted user question to the composer. Introductions retain their images.
    public mutating func withdraw(_ id: UUID) -> ConversationTask? {
        guard let index = tasks.firstIndex(where: {
            $0.id == id && $0.state == .queued && $0.kind == .question
        }) else { return nil }
        return tasks.remove(at: index)
    }

    public mutating func clear() { self = ConversationQueue() }

    private var activeIndex: Int? { tasks.firstIndex { $0.id == activeID } }

    private mutating func resume() {
        isPaused = false
        pauseReason = nil
        activeID = nil
        runID = nil
    }
}
