import Foundation

/// Reading what was pasted: whether it belongs in the question, and what came along with
/// a copied picture.
public enum PastedText {
    /// Pastes this long, in characters, are sealed as an attachment.
    public static let attachmentCharacters = 280
    /// So are pastes of this many lines or more: a copied answer or code block would bury
    /// the question even when short.
    public static let attachmentLines = 3

    public static func belongsInAttachment(_ pasted: String) -> Bool {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= attachmentCharacters
            || trimmed.split(separator: "\n", omittingEmptySubsequences: false).count >= attachmentLines
    }

    /// True for nothing at all or a single web or file link, which is what browsers put
    /// beside a copied image: the picture is what was meant. Anything else is real text
    /// (Office apps, for one, copy text together with a picture of it).
    public static func isLoneLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        guard !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased()
        else { return false }
        return ["http", "https", "file"].contains(scheme)
    }
}
