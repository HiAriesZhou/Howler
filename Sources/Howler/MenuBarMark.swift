import AppKit
import SwiftUI

/// The menu bar's mark: the app icon's wax seal with its H cut through, drawn as a template
/// image so it takes the menu bar's own color in light, dark and tinted menu bars. `side` is
/// 18 points for the status item; menus use it smaller, beside their item titles.
enum MenuBarMark {
    static func image(side: CGFloat = 18) -> NSImage {
        let scale = side / 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let seal = WaxPuddle(seed: 11).path(in: rect.insetBy(dx: 0.5 * scale, dy: 0.5 * scale)).cgPath
            context.addPath(seal)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()

            // Knock the initial out of the wax.
            context.setBlendMode(.clear)
            let font = NSFont(name: "IowanOldStyle-Bold", size: 12 * scale) ?? .boldSystemFont(ofSize: 11 * scale)
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
