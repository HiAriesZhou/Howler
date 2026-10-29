import AppKit
import HowlerCore
import UniformTypeIdentifiers

/// The general pasteboard, read only when the user asks: "Paste from Clipboard" or ⌘V.
/// Nothing watches it in the background.
@MainActor
enum Clipboard {
    private static var pasteboard: NSPasteboard { .general }

    /// A copied picture, else text of any length, else whatever picture there is.
    static func attachment() -> ContextAttachment? {
        if let picture = pictureToSeal() {
            return ContextAttachment(source: .pasted, image: picture)
        }
        if let text = pasteboard.string(forType: .string),
           let attachment = ContextAttachment(source: .pasted, text: text) {
            return attachment
        }
        return image().map { ContextAttachment(source: .pasted, image: $0) }
    }

    /// A picture, scaled for upload.
    static func image() -> ImageData? {
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else { return nil }
        return UploadImage.prepare(data)
    }

    /// A picture ⌘V should seal in instead of pasting into the question: a copied image
    /// file (Finder puts its name beside it as text), or image data with nothing but a link
    /// beside it (a browser's Copy Image). Text that comes with a picture of itself, as
    /// from Office apps, stays text.
    static func pictureToSeal() -> ImageData? {
        if let file = copiedFile() {
            return imageFile(file)
        }
        let types = pasteboard.types ?? []
        guard types.contains(.png) || types.contains(.tiff),
              PastedText.isLoneLink(pasteboard.string(forType: .string) ?? "")
        else { return nil }
        return image()
    }

    /// Larger files are photos or scans no model needs at full size; reading one would stall.
    private static let maxImageFileBytes = 50_000_000

    private static func copiedFile() -> URL? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.count == 1 ? urls?.first : nil
    }

    private static func imageFile(_ url: URL) -> ImageData? {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxImageFileBytes,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UploadImage.prepare(data)
    }

    static func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
