import AppKit
import SwiftUI

/// The menu bar's mark: the app icon's wax seal with its H cut through, drawn as a template
/// image so it takes the menu bar's own color in light, dark and tinted menu bars.
enum MenuBarMark {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let seal = WaxPuddle(seed: 11).path(in: rect.insetBy(dx: 0.5, dy: 0.5)).cgPath
            context.addPath(seal)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()

            // Knock the initial out of the wax.
            context.setBlendMode(.clear)
            let font = NSFont(name: "IowanOldStyle-Bold", size: 12) ?? .boldSystemFont(ofSize: 11)
            let initial = NSAttributedString(string: "H", attributes: [.font: font, .foregroundColor: NSColor.black])
            let bounds = initial.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
            initial.draw(at: NSPoint(
                x: rect.midX - bounds.width / 2 - bounds.minX,
                y: rect.midY - bounds.height / 2 - (font.ascender - bounds.maxY)
            ))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppInfo.name
        return image
    }
}
