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

    public init(id: UUID = UUID(), role: Role, content: String, attachment: ContextAttachment? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.attachment = attachment
    }

    /// The text sent to the provider for this turn (attached text folded in).
    public var wireContent: String {
        attachment?.prompt(for: content) ?? content
    }

    /// An attached picture, sent as its own content part.
    public var image: ImageData? {
        attachment?.image
    }
}
