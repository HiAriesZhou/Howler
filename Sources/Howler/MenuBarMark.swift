import AppKit

/// The menu bar's mark: the quill that writes the answers, drawn as a template image so it
/// takes the menu bar's own color in light, dark and tinted menu bars. Drawn on an 18-point
/// grid; `side` is 18 for the status item and smaller beside menu item titles.
enum MenuBarMark {
    static func image(side: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: side / 18, y: side / 18)
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineCap(.round)

            // The feather: a leaf-shaped vane from the nib (bottom left) to the tip.
            let vane = CGMutablePath()
            vane.move(to: CGPoint(x: 3, y: 16.2))
            vane.addCurve(to: CGPoint(x: 15.6, y: 1.6), control1: CGPoint(x: 4.5, y: 9), control2: CGPoint(x: 9.5, y: 2.2))
            vane.addCurve(to: CGPoint(x: 3, y: 16.2), control1: CGPoint(x: 15.8, y: 7.5), control2: CGPoint(x: 10, y: 13.5))
            context.addPath(vane)
            context.fillPath()

            // The shaft and two barb partings, cut out of the vane.
            context.saveGState()
            context.setBlendMode(.clear)
            context.setLineWidth(0.85)
            context.move(to: CGPoint(x: 4.6, y: 14.4))
            context.addCurve(to: CGPoint(x: 14.6, y: 2.8), control1: CGPoint(x: 7.5, y: 9.5), control2: CGPoint(x: 11, y: 5.2))
            context.strokePath()
            for start in [CGPoint(x: 8.6, y: 8.4), CGPoint(x: 11.2, y: 5.6)] {
                context.move(to: start)
                context.addLine(to: CGPoint(x: start.x + 2.2, y: start.y + 1.6))
                context.strokePath()
            }
            context.restoreGState()

            // The nib.
            context.setLineWidth(1.1)
            context.move(to: CGPoint(x: 3.4, y: 15.8))
            context.addLine(to: CGPoint(x: 1.6, y: 17.4))
            context.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppInfo.name
        return image
    }
}
