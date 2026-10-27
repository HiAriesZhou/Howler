#if DEBUG
import AppKit
import SwiftUI

/// The app icon, drawn with the letter's own materials: a parchment tile burning from its
/// bottom edge, a matte crimson seal cut with an H, and the raven quill that just wrote it.
/// `scripts/icon.sh` renders it into `Resources/AppIcon.icns`; debug builds only.
///
/// `HOWLER_DEMO=appicon HOWLER_DEMO_OUT=dir` writes `AppIcon.iconset`, the README icon
/// (`icon.png`) and a preview of the menu bar mark (`menubar.png`).
@MainActor
enum AppIconArt {
    /// Icon canvas in points: the tile fills 412 of it, Apple's 824-of-1024 grid.
    static let canvas: CGFloat = 512

    /// Every image an `.iconset` needs, by file name and pixel size.
    private static let iconset: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    static func write(to directory: String) {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        let set = folder.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        for entry in iconset {
            // Up to 64 px, sparks and wax grain only add noise.
            let view = AppIconView(simplified: entry.pixels <= 64)
            if let image = render(view, pixels: entry.pixels) {
                save(image, to: set.appendingPathComponent("\(entry.name).png"))
            }
        }
        if let readme = render(AppIconView(simplified: false), pixels: 512) {
            save(readme, to: folder.appendingPathComponent("icon.png"))
        }
        let mark = MenuBarMark.image()
        if let tiff = mark.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: folder.appendingPathComponent("menubar.png"))
        }
    }

    private static func render<Content: View>(_ view: Content, pixels: Int) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = CGFloat(pixels) / canvas
        return renderer.cgImage
    }

    private static func save(_ image: CGImage, to url: URL) {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}

private struct AppIconView: View {
    let simplified: Bool

    var body: some View {
        BurningTile(progress: 0.31, sparks: !simplified) {
            // Centered and large enough that the fire takes a bite out of its lower rim.
            MatteSeal(size: 344, seed: 11, initial: "H", grain: !simplified)
        } above: {
            // The nib rests at the foot of the H's right stem, as if it had just written it;
            // the feather reaches into the tile's upper right corner and no further.
            Quill(tip: CGPoint(x: 326, y: 316), end: CGPoint(x: 432, y: 104))
                .shadow(color: .black.opacity(0.4), radius: 5, x: 5, y: 7)
        }
    }
}

// MARK: The burning tile

/// A parchment tile burning from its bottom edge. Whatever sits on the paper (`onPaper`)
/// burns with it; `above` stays clear of the fire.
private struct BurningTile<OnPaper: View, Above: View>: View {
    var progress: Double
    var sparks: Bool
    @ViewBuilder let onPaper: () -> OnPaper
    @ViewBuilder let above: () -> Above

    private let tile: CGFloat = 412
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous) }

    var body: some View {
        let field = BurnField(size: CGSize(width: tile, height: tile), seed: 0x5EA1)
        let frame = field.frame(at: progress)
        ZStack {
            // A full tile, as macOS 26 expects (it plates any other shape in gray): where the
            // paper has burned away, charred ground glows from below.
            ZStack {
                shape.fill(RadialGradient(
                    colors: [Color(hex: 0x6B2A12), Color(hex: 0x2A1810), Color(hex: 0x140D0A)],
                    center: UnitPoint(x: 0.5, y: 1.05), startRadius: 0, endRadius: tile * 0.75
                ))
                ZStack {
                    PaperTexture(showsCrease: false)
                    onPaper()
                    if let frame {
                        Image(decorative: frame.scorch, scale: 1).resizable().interpolation(.high).blur(radius: 2)
                    }
                }
                .frame(width: tile, height: tile)
                .clipShape(shape)
                .mask {
                    if let frame {
                        Image(decorative: frame.mask, scale: 1).resizable().interpolation(.high).blur(radius: 1.4)
                    }
                }
            }
            .frame(width: tile, height: tile)
            .compositingGroup()
            .shadow(color: .black.opacity(0.32), radius: 12, x: 0, y: 8)
            .overlay {
                if let frame {
                    // Warmed toward orange, and kept inside the tile.
                    Image(decorative: frame.glow, scale: 1)
                        .resizable().interpolation(.high).blur(radius: 5)
                        .colorMultiply(Color(red: 1, green: 0.72, blue: 0.45))
                        .blendMode(.plusLighter)
                        .frame(width: tile, height: tile)
                        .mask(shape)
                }
            }
            .overlay {
                if sparks { StillSparks(field: field, progress: progress) }
            }

            above()
        }
        .frame(width: AppIconArt.canvas, height: AppIconArt.canvas)
    }
}

/// Sealing wax as it really looks once set: matte, grainy, unevenly dense, pressed into a
/// shallow disc with the initial cut into it. No gloss.
private struct MatteSeal: View {
    let size: CGFloat
    let seed: UInt64
    var initial: String?
    var grain = true

    private let light = Color(hex: 0xB43A2E)
    private let base = Color(hex: 0x951F18)
    private let deep = Color(hex: 0x5C0E0A)

    var body: some View {
        ZStack {
            WaxPuddle(seed: seed)
                .fill(RadialGradient(colors: [light, base, deep], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.75))
            if grain {
                Grain(seed: seed, light: Color(hex: 0xD06A55), dark: deep)
                    .mask(WaxPuddle(seed: seed))
            }
            // Thickness: the rounded edge of the puddle, lit at the top left, in shade at the bottom right.
            WaxPuddle(seed: seed)
                .stroke(LinearGradient(colors: [Color(hex: 0xD86450).opacity(0.7), light.opacity(0.1), deep.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: size * 0.07)
                .blur(radius: size * 0.018)
                .mask(WaxPuddle(seed: seed))
            WaxPuddle(seed: seed)
                .stroke(deep.opacity(0.6), lineWidth: 1.2)

            // The impression: a shallow, slightly darker disc with a dull rim.
            Circle()
                .fill(RadialGradient(colors: [base.opacity(0.9), deep.opacity(0.55)], center: UnitPoint(x: 0.62, y: 0.66), startRadius: 0, endRadius: size * 0.4))
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(colors: [deep.opacity(0.9), deep.opacity(0.3), light.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: size * 0.03
                    )
                )
                .overlay {
                    if grain { Grain(seed: seed &+ 3, light: Color(hex: 0xC85A47), dark: deep).clipShape(Circle()).opacity(0.7) }
                }
                .frame(width: size * 0.7, height: size * 0.7)

            if let initial {
                // Cut in, not raised: the letter sits in shadow and its lower right edge catches the light.
                let font = Lettering.proseBold(size * 0.5)
                ZStack {
                    Text(initial).font(font).foregroundStyle(Color(hex: 0xE07A62).opacity(0.5)).offset(x: 1.2, y: 1.6)
                    Text(initial).font(font).foregroundStyle(deep.opacity(0.92))
                    Text(initial).font(font).foregroundStyle(.black.opacity(0.25)).offset(x: -0.8, y: -1).blur(radius: 1)
                        .mask(Text(initial).font(font))
                }
                .offset(y: -size * 0.01)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 2)
        .shadow(color: deep.opacity(0.3), radius: 6, x: 0, y: 4)
    }
}

/// The paste-like body of wax: fine speckle and soft blotches of thicker and thinner color.
private struct Grain: View {
    let seed: UInt64
    let light: Color
    let dark: Color

    var body: some View {
        Canvas { context, size in
            var random = SeededRandom(seed: seed &* 31 &+ 7)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 7))
                for _ in 0..<26 {
                    let w = random.range(18...64), h = random.range(14...48)
                    let rect = CGRect(x: random.range(-20...size.width), y: random.range(-20...size.height), width: w, height: h)
                    let tone = random.unit() < 0.55 ? dark.opacity(random.range(0.12...0.28)) : light.opacity(random.range(0.08...0.18))
                    layer.fill(Path(ellipseIn: rect), with: .color(tone))
                }
            }
            for _ in 0..<2600 {
                let point = CGPoint(x: random.range(0...size.width), y: random.range(0...size.height))
                let radius = random.range(0.35...1.1)
                let tone = random.unit() < 0.6 ? dark.opacity(random.range(0.12...0.32)) : light.opacity(random.range(0.08...0.22))
                context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: radius * 2, height: radius * 2)), with: .color(tone))
            }
        }
    }
}

/// A dark raven quill from `tip` (the nib, in canvas points) to `end` (the feather's tip).
/// The broad side of the vane faces down and right, away from the seal's initial. A small
/// gold spark at the nib: the quill writes by itself.
private struct Quill: View {
    let tip: CGPoint
    let end: CGPoint

    var body: some View {
        Canvas { context, _ in
            var c = context
            c.translateBy(x: tip.x, y: tip.y)
            c.rotate(by: .radians(atan2(end.y - tip.y, end.x - tip.x)))
            c.scaleBy(x: 1, y: -1) // broad side of the vane to the lower right
            let L = hypot(end.x - tip.x, end.y - tip.y)

            // Vane: wider above the shaft than below, tapering to a slightly hooked tip.
            let vaneStart = 0.29 * L
            var vane = Path()
            vane.move(to: CGPoint(x: vaneStart, y: 0))
            vane.addCurve(to: CGPoint(x: L, y: -0.035 * L), control1: CGPoint(x: 0.42 * L, y: -0.21 * L), control2: CGPoint(x: 0.86 * L, y: -0.17 * L))
            vane.addCurve(to: CGPoint(x: vaneStart + 0.05 * L, y: 0.004 * L), control1: CGPoint(x: 0.9 * L, y: 0.06 * L), control2: CGPoint(x: 0.52 * L, y: 0.12 * L))
            vane.closeSubpath()
            c.fill(vane, with: .linearGradient(
                Gradient(colors: [Color(hex: 0x1C1410), Color(hex: 0x3A2B20), Color(hex: 0x5A4532)]),
                startPoint: CGPoint(x: vaneStart, y: 0.1 * L), endPoint: CGPoint(x: L, y: -0.12 * L)
            ))

            // Barbs: fine, curved toward the tip, a little uneven, with two natural splits.
            c.drawLayer { layer in
                layer.clip(to: vane)
                var random = SeededRandom(seed: 0xFEA7)
                var x = vaneStart
                while x < L {
                    for side in [-1.0, 1.0] {
                        let reach = (side < 0 ? 0.26 : 0.17) * L
                        let lean = CGFloat(side < 0 ? random.range(0.55...0.75) : random.range(0.7...0.95))
                        var barb = Path()
                        barb.move(to: CGPoint(x: x, y: 0))
                        barb.addQuadCurve(
                            to: CGPoint(x: x + reach * lean, y: CGFloat(side) * reach * 0.62),
                            control: CGPoint(x: x + reach * 0.15, y: CGFloat(side) * reach * 0.42)
                        )
                        let tone = random.unit() < 0.5 ? Color(hex: 0x8E7760) : Color(hex: 0x120C08)
                        layer.stroke(barb, with: .color(tone.opacity(Double(random.range(0.12...0.34)))), lineWidth: random.range(0.35...0.7))
                    }
                    x += 1.5
                }
                // Splits: barbs pulled apart where the vane has parted.
                layer.blendMode = .destinationOut
                for (start, side) in [(0.6, -1.0), (0.78, 1.0), (0.86, -1.0)] {
                    var split = Path()
                    split.move(to: CGPoint(x: start * L, y: CGFloat(side) * 0.02 * L))
                    split.addQuadCurve(
                        to: CGPoint(x: start * L + 0.16 * L, y: CGFloat(side) * 0.2 * L),
                        control: CGPoint(x: start * L + 0.02 * L, y: CGFloat(side) * 0.14 * L)
                    )
                    layer.stroke(split, with: .color(.black), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
                layer.blendMode = .normal
                // A cool sheen along the upper vane.
                layer.fill(vane, with: .linearGradient(
                    Gradient(colors: [Color(hex: 0x9FB2C8).opacity(0.0), Color(hex: 0x9FB2C8).opacity(0.18), Color(hex: 0x9FB2C8).opacity(0.0)]),
                    startPoint: CGPoint(x: 0.5 * L, y: -0.16 * L), endPoint: CGPoint(x: 0.6 * L, y: 0.02 * L)
                ))
            }

            // Down: a few loose wisps where the vane begins.
            var random = SeededRandom(seed: 0xD0E1)
            for index in 0..<16 {
                let base = CGPoint(x: 0.28 * L + CGFloat(index) * 1.6, y: 0)
                let side: CGFloat = index.isMultiple(of: 2) ? 1 : -1
                var wisp = Path()
                wisp.move(to: base)
                wisp.addQuadCurve(
                    to: CGPoint(x: base.x + random.range(8...20), y: side * random.range(10...22)),
                    control: CGPoint(x: base.x - random.range(2...8), y: side * random.range(8...14))
                )
                c.stroke(wisp, with: .color(Color(hex: 0x4A3A2C).opacity(Double(random.range(0.3...0.6)))), lineWidth: random.range(0.4...0.8))
            }

            // Rachis: an ivory shaft running through the vane, thinning to the tip.
            var rachis = Path()
            rachis.move(to: CGPoint(x: 0.13 * L, y: 0))
            rachis.addQuadCurve(to: CGPoint(x: 0.99 * L, y: -0.032 * L), control: CGPoint(x: 0.7 * L, y: -0.004 * L))
            c.stroke(rachis, with: .linearGradient(
                Gradient(colors: [Color(hex: 0xF1E6CF), Color(hex: 0xC9B48E).opacity(0.7)]),
                startPoint: CGPoint(x: 0.13 * L, y: 0), endPoint: CGPoint(x: L, y: 0)
            ), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

            // Calamus: the bare horn barrel above the nib.
            let barrel = Path(roundedRect: CGRect(x: 0.11 * L, y: -4.2, width: 0.2 * L, height: 8.4), cornerRadius: 4.2)
            c.fill(barrel, with: .linearGradient(
                Gradient(colors: [Color(hex: 0xF4EAD4), Color(hex: 0xCDB892), Color(hex: 0x9E8762)]),
                startPoint: CGPoint(x: 0, y: -4.2), endPoint: CGPoint(x: 0, y: 4.2)
            ))

            // Nib: cut to a point, dark with ink, with its slit.
            var nib = Path()
            nib.move(to: .zero)
            nib.addQuadCurve(to: CGPoint(x: 0.125 * L, y: -5.2), control: CGPoint(x: 0.06 * L, y: -6.5))
            nib.addLine(to: CGPoint(x: 0.125 * L, y: 5.2))
            nib.addQuadCurve(to: .zero, control: CGPoint(x: 0.06 * L, y: 6.5))
            nib.closeSubpath()
            c.fill(nib, with: .linearGradient(
                Gradient(colors: [Color(hex: 0x1A120D), Color(hex: 0x4A3A2B)]),
                startPoint: .zero, endPoint: CGPoint(x: 0.125 * L, y: 0)
            ))
            var slit = Path()
            slit.move(to: CGPoint(x: 2, y: 0))
            slit.addLine(to: CGPoint(x: 0.07 * L, y: 0))
            c.stroke(slit, with: .color(Color(hex: 0xC9B48E).opacity(0.8)), lineWidth: 0.8)

            // The spark at the point of the nib.
            c.drawLayer { glow in
                glow.addFilter(.blur(radius: 6))
                glow.fill(Sparkle.path(center: CGPoint(x: -9, y: 0), radius: 20), with: .color(Color(hex: 0xFFC860).opacity(0.85)))
            }
            c.fill(Sparkle.path(center: CGPoint(x: -9, y: 0), radius: 15), with: .linearGradient(
                Gradient(colors: [Color(hex: 0xFFF1C4), Color(hex: 0xF0C46A)]),
                startPoint: CGPoint(x: -9, y: -15), endPoint: CGPoint(x: -9, y: 15)
            ))
        }
        .frame(width: AppIconArt.canvas, height: AppIconArt.canvas)
    }
}

// MARK: Shared pieces

/// The four-pointed spark used for AI throughout the app (✦).
private enum Sparkle {
    static func path(center c: CGPoint, radius r: CGFloat) -> Path {
        var path = Path()
        let tips = [CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x - r, y: c.y)]
        path.move(to: tips[0])
        for index in 0..<4 {
            let next = tips[(index + 1) % 4]
            path.addQuadCurve(to: next, control: CGPoint(x: c.x + (tips[index].x + next.x - 2 * c.x) * 0.12,
                                                         y: c.y + (tips[index].y + next.y - 2 * c.y) * 0.12))
        }
        path.closeSubpath()
        return path
    }
}

/// Sparks frozen mid-flight above the burning edge.
private struct StillSparks: View {
    let field: BurnField
    let progress: Double
    private let life = 0.22

    var body: some View {
        Canvas { context, _ in
            for ember in field.embers where progress > ember.lit && progress < ember.lit + life {
                let age = (progress - ember.lit) / life
                let x = ember.origin.x + ember.drift * CGFloat(age)
                let y = ember.origin.y - ember.rise * CGFloat(age) * 1.4
                let radius = ember.radius * 1.8 * CGFloat(1 - age * 0.5)
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius * 2, y: y - radius * 2, width: radius * 4, height: radius * 4)),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 1, green: 0.88, blue: 0.55).opacity(1 - age * 0.6),
                            Color(red: 1, green: 0.45, blue: 0.1).opacity(0.6),
                            Color(red: 0.8, green: 0.15, blue: 0).opacity(0),
                        ]),
                        center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius * 2
                    )
                )
            }
        }
        .frame(width: field.size.width, height: field.size.height)
    }
}
#endif
