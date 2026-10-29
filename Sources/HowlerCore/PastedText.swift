import Foundation

/// Reading what came along with a copied picture.
public enum PastedText {
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
