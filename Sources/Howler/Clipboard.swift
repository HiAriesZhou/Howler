import AppKit
import HowlerCore

/// The general pasteboard, read only when the user asks: "Paste from Clipboard" or ⌘V.
/// Nothing watches it in the background.
@MainActor
enum Clipboard {
    private static var pasteboard: NSPasteboard { .general }

    /// Text of any length, or else a picture.
    static func attachment() -> ContextAttachment? {
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

    /// The clipboard holds a picture and no text — what ⌘V should seal in instead of
    /// pasting into the question. Checks types only; contents are not read.
    static var holdsOnlyImage: Bool {
        let types = pasteboard.types ?? []
        return !types.contains(.string) && (types.contains(.png) || types.contains(.tiff))
    }

    static func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
