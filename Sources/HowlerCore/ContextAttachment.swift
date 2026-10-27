import Foundation

/// An encoded picture to send to a model, already scaled for upload.
public struct ImageData: Equatable, Sendable {
    public let data: Data
    /// "image/png" or "image/jpeg".
    public let mediaType: String
    public let width: Int
    public let height: Int

    public init(data: Data, mediaType: String, width: Int, height: Int) {
        self.data = data
        self.mediaType = mediaType
        self.width = width
        self.height = height
    }
}

/// Context that rides along with a question without being typed into it: something the
/// user pasted or a region of the screen they captured. The UI shows it as a wax seal;
/// text reaches the model wrapped in a `<context>` element ahead of the question, an
/// image as its own content part.
public struct ContextAttachment: Equatable, Sendable {
    public enum Source: String, Sendable {
        /// Pasted on purpose: a long paste into the question, or "Paste from Clipboard".
        case pasted
        /// A screen region the user captured.
        case screenshot
    }

    public enum Content: Equatable, Sendable {
        case text(String)
        case image(ImageData)
    }

    /// Keeps a stray giant paste (a log file, a whole book) from blowing the context window.
    public static let maxCharacters = 40_000

    public let source: Source
    public let content: Content
    /// Length before truncation, in characters (0 for images).
    public let characterCount: Int

    /// Returns nil when there is nothing but whitespace to attach.
    public init?(source: Source, text: String, limit: Int = maxCharacters) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.source = source
        self.characterCount = trimmed.count
        self.content = .text(trimmed.count > limit ? String(trimmed.prefix(limit)) : trimmed)
    }

    public init(source: Source, image: ImageData) {
        self.source = source
        self.content = .image(image)
        self.characterCount = 0
    }

    /// The text sent to the model, cut to the limit; nil for images.
    public var text: String? {
        if case .text(let text) = content { return text }
        return nil
    }

    public var image: ImageData? {
        if case .image(let image) = content { return image }
        return nil
    }

    public var isTruncated: Bool {
        guard let text else { return false }
        return characterCount > text.count
    }

    /// "Pasted text", "Pasted image" or "Screenshot".
    public var title: String {
        switch (source, content) {
        case (.screenshot, _): return "Screenshot"
        case (.pasted, .image): return "Pasted image"
        case (.pasted, .text): return "Pasted text"
        }
    }

    /// "1.3k chars" or "1280×720".
    public var sizeLabel: String {
        switch content {
        case .text: return "\(Self.formatCount(characterCount)) chars"
        case .image(let image): return "\(image.width)×\(image.height)"
        }
    }

    /// "Pasted text · 1.3k chars"
    public var summary: String {
        "\(title) · \(sizeLabel)"
    }

    public func preview(maxLines: Int) -> String {
        guard let text else { return "" }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return text }
        return lines.prefix(maxLines).joined(separator: "\n") + "\n…"
    }

    /// The user turn's text as the model sees it. Images don't change the text.
    public func prompt(for question: String) -> String {
        guard let text else { return question }
        let truncated = isTruncated ? #" truncated="true""# : ""
        return """
        <context source="\(source.rawValue)"\(truncated)>
        \(text)
        </context>

        \(question)
        """
    }

    static func formatCount(_ count: Int) -> String {
        guard count >= 1_000 else { return "\(count)" }
        let thousands = (Double(count) / 100).rounded() / 10
        return thousands.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(thousands))k"
            : "\(thousands)k"
    }
}
