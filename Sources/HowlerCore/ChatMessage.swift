import Foundation

public struct ChatMessage: Equatable, Identifiable, Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public let id: UUID
    public var role: Role
    /// What the user typed (or the model wrote). Shown in the transcript.
    public var content: String
    /// Context sent with a user turn but kept out of the visible text.
    public var attachment: ContextAttachment?
    /// Per-turn task instructions, kept out of the visible question and independent of system prompts.
    public var taskInstructions: String?

    public init(id: UUID = UUID(), role: Role, content: String, attachment: ContextAttachment? = nil,
                taskInstructions: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.attachment = attachment
        self.taskInstructions = taskInstructions
    }

    /// The text sent to the provider for this turn (attached text folded in).
    public var wireContent: String {
        let question = attachment?.prompt(for: content) ?? content
        guard let taskInstructions, !taskInstructions.isEmpty else { return question }
        return taskInstructions + "\n\n<user_question>\n" + question + "\n</user_question>"
    }

    /// An attached picture, sent as its own content part.
    public var image: ImageData? {
        attachment?.image
    }
}
