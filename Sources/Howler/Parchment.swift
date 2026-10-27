import AppKit
import SwiftUI

/// The letter's materials: paper, inks and lettering. The sheet stays paper-colored in
/// both appearances (it is paper); in Dark Mode it is candlelit — dimmer, so it doesn't
/// glare against a dark desktop.
struct Parchment {
    let paper: Color
    let paperEdge: Color
    let fiber: Color
    let ink: Color
    let fadedInk: Color
    let rule: Color
    /// Sealing-wax red for the provider stamp and links.
    let seal: Color
    /// The glow of magic: attachment sigils, fresh ink.
    let magic: Color
    let error: Color
    let codeWash: Color

    static func forScheme(_ scheme: ColorScheme) -> Parchment {
        switch scheme {
        case .dark:
            return Parchment(
                paper: Color(hex: 0xE4D6B8), paperEdge: Color(hex: 0xBFA67A), fiber: Color(hex: 0x7A5F38),
                ink: Color(hex: 0x24180E), fadedInk: Color(hex: 0x6E5839), rule: Color(hex: 0xA88F64),
                seal: Color(hex: 0x8C2620), magic: Color(hex: 0x9C6A10), error: Color(hex: 0x962119),
                codeWash: Color(hex: 0xD6C4A0)
            )
        default:
            return Parchment(
                paper: Color(hex: 0xF8F0DE), paperEdge: Color(hex: 0xE3CFA6), fiber: Color(hex: 0x9C7E50),
                ink: Color(hex: 0x2B1E13), fadedInk: Color(hex: 0x8A7255), rule: Color(hex: 0xC8B187),
                seal: Color(hex: 0x9B2F2A), magic: Color(hex: 0xA8741A), error: Color(hex: 0xA12A22),
                codeWash: Color(hex: 0xEBDDBF)
            )
        }
    }
}

private struct ParchmentKey: EnvironmentKey {
    static let defaultValue = Parchment.forScheme(.light)
}

extension EnvironmentValues {
    var parchment: Parchment {
        get { self[ParchmentKey.self] }
        set { self[ParchmentKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Lettering. Latin text is set in Iowan Old Style (bookish, very legible); Chinese falls
/// back to Songti for prose and Kaiti — brush handwriting — for what the user writes.
@MainActor
enum Lettering {
    /// Fonts are rebuilt on every frame while the quill writes; build each one once.
    private static var cache: [String: Font] = [:]

    /// What the user writes: the input line and questions in the transcript.
    static func hand(_ size: CGFloat) -> Font {
        font("IowanOldStyle-Italic", size: size, cascade: ["STKaiti", "Kaiti SC", "STSongti-SC-Regular"])
    }

    /// What the letter writes back.
    static func prose(_ size: CGFloat) -> Font {
        font("IowanOldStyle-Roman", size: size, cascade: ["STSongti-SC-Regular", "Songti SC"])
    }

    static func proseBold(_ size: CGFloat) -> Font {
        font("IowanOldStyle-Bold", size: size, cascade: ["STSongti-SC-Bold", "Songti SC"])
    }

    /// Flourishes and empty-page whispers.
    static func script(_ size: CGFloat) -> Font {
        font("SnellRoundhand", size: size, cascade: ["STKaiti", "Kaiti SC"])
    }

    /// Small marginal notes (provider, model, hints).
    static func marginalia(_ size: CGFloat) -> Font {
        font("IowanOldStyle-Italic", size: size, cascade: ["STKaiti", "Kaiti SC"])
    }

    private static func font(_ name: String, size: CGFloat, cascade: [String]) -> Font {
        let key = "\(name)@\(size)"
        if let cached = cache[key] { return cached }
        let font = makeFont(name, size: size, cascade: cascade)
        cache[key] = font
        return font
    }

    private static func makeFont(_ name: String, size: CGFloat, cascade: [String]) -> Font {
        guard let base = NSFont(name: name, size: size) else {
            return .system(size: size, design: .serif)
        }
        let fallbacks = cascade
            .filter { NSFont(name: $0, size: size) != nil }
            .map { NSFontDescriptor(fontAttributes: [.name: $0]) }
        let descriptor = base.fontDescriptor.addingAttributes([.cascadeList: fallbacks])
        let font = NSFont(descriptor: descriptor, size: size) ?? base
        return Font(font as CTFont)
    }
}

/// A small deterministic random source so paper fibers and torn edges look the same every
/// time the letter opens (and don't shimmer as it grows).
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }

    mutating func range(_ range: ClosedRange<CGFloat>) -> CGFloat {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// A stable value in -1...1 for an integer position.
    static func jitter(_ index: Int, seed: UInt64) -> CGFloat {
        var random = SeededRandom(seed: seed &+ UInt64(bitPattern: Int64(index)) &* 0x2545_F491_4F6C_DD1D)
        return random.unit() * 2 - 1
    }
}

/// A sheet with softly deckled edges: hand-made paper is never ruler straight.
/// Edge offsets depend only on absolute position, so the sheet can grow without its
/// existing edges changing shape.
struct DeckledSheet: Shape {
    var roughness: CGFloat = 1.3
    private let step: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let inset = roughness
        let r = rect.insetBy(dx: inset, dy: inset)
        var path = Path()

        func offset(_ index: Int, _ seed: UInt64) -> CGFloat {
            SeededRandom.jitter(index, seed: seed) * roughness
        }

        // Top edge, left → right.
        path.move(to: CGPoint(x: r.minX, y: r.minY + offset(0, 1)))
        var x = r.minX + step
        var i = 1
        while x < r.maxX {
            path.addLine(to: CGPoint(x: x, y: r.minY + offset(i, 1)))
            x += step
            i += 1
        }
        // Right edge, top → bottom.
        var y = r.minY
        i = 0
        while y < r.maxY {
            path.addLine(to: CGPoint(x: r.maxX + offset(i, 2), y: y))
            y += step
            i += 1
        }
        // Bottom edge, right → left (indexed from the left so it is stable as width is fixed).
        var bottomPoints: [CGPoint] = []
        x = r.minX
        i = 0
        while x <= r.maxX {
            bottomPoints.append(CGPoint(x: x, y: r.maxY + offset(i, 3)))
            x += step
            i += 1
        }
        for point in bottomPoints.reversed() { path.addLine(to: point) }
        // Left edge, bottom → top (indexed from the top).
        var leftPoints: [CGPoint] = []
        y = r.minY
        i = 0
        while y <= r.maxY {
            leftPoints.append(CGPoint(x: r.minX + offset(i, 4), y: y))
            y += step
            i += 1
        }
        for point in leftPoints.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// Paper body: warm center, aged edges, fibers, flecks and a faint fold crease.
struct PaperTexture: View {
    /// The fold down the middle; the app icon leaves it out.
    var showsCrease = true
    @Environment(\.parchment) private var parchment

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(parchment.paper))

            // Aged edges: darken toward every side.
            let edge = parchment.paperEdge
            let depth: CGFloat = 70
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [edge.opacity(0.55), edge.opacity(0)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: depth)
            ))
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [edge.opacity(0), edge.opacity(0.65)]),
                startPoint: CGPoint(x: 0, y: size.height - depth * 1.4), endPoint: CGPoint(x: 0, y: size.height)
            ))
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [edge.opacity(0.5), edge.opacity(0)]),
                startPoint: .zero, endPoint: CGPoint(x: depth, y: 0)
            ))
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [edge.opacity(0), edge.opacity(0.5)]),
                startPoint: CGPoint(x: size.width - depth, y: 0), endPoint: CGPoint(x: size.width, y: 0)
            ))

            // Fibers and flecks, laid out in fixed tiles so growing the sheet only adds more.
            let tile: CGFloat = 120
            let columns = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0..<rows {
                for column in 0..<columns {
                    var random = SeededRandom(seed: UInt64(row * 97 + column * 13 + 7))
                    let origin = CGPoint(x: CGFloat(column) * tile, y: CGFloat(row) * tile)
                    for _ in 0..<9 {
                        let start = CGPoint(x: origin.x + random.range(0...tile), y: origin.y + random.range(0...tile))
                        let angle = random.range(0...(2 * .pi))
                        let length = random.range(5...16)
                        let end = CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
                        let bend = CGPoint(
                            x: (start.x + end.x) / 2 + random.range(-3...3),
                            y: (start.y + end.y) / 2 + random.range(-3...3)
                        )
                        var fiber = Path()
                        fiber.move(to: start)
                        fiber.addQuadCurve(to: end, control: bend)
                        context.stroke(fiber, with: .color(parchment.fiber.opacity(random.range(0.05...0.13))), lineWidth: random.range(0.4...0.8))
                    }
                    for _ in 0..<6 {
                        let point = CGPoint(x: origin.x + random.range(0...tile), y: origin.y + random.range(0...tile))
                        let radius = random.range(0.3...1.1)
                        context.fill(
                            Path(ellipseIn: CGRect(x: point.x, y: point.y, width: radius, height: radius)),
                            with: .color(parchment.fiber.opacity(random.range(0.08...0.22)))
                        )
                    }
                }
            }

            // The letter's fold: a faint crease down the middle.
            guard showsCrease else { return }
            let crease = size.width * 0.5
            context.fill(
                Path(CGRect(x: crease - 0.5, y: 0, width: 0.6, height: size.height)),
                with: .color(parchment.fiber.opacity(0.10))
            )
            context.fill(
                Path(CGRect(x: crease + 0.4, y: 0, width: 1.4, height: size.height)),
                with: .color(Color.white.opacity(0.18))
            )
        }
    }
}

/// A hand-drawn rule: the line you write on.
struct InkRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: y))
        let segments = max(Int(rect.width / 60), 1)
        for segment in 1...segments {
            let x = rect.minX + rect.width * CGFloat(segment) / CGFloat(segments)
            let control = CGPoint(
                x: x - rect.width / CGFloat(segments) / 2,
                y: y + SeededRandom.jitter(segment, seed: 42) * 0.9
            )
            path.addQuadCurve(to: CGPoint(x: x, y: y + SeededRandom.jitter(segment, seed: 43) * 0.4), control: control)
        }
        return path
    }
}

/// "— ❦ —": the flourish between one exchange and the next.
struct Flourish: View {
    @Environment(\.parchment) private var parchment

    var body: some View {
        HStack(spacing: 10) {
            InkRule().stroke(parchment.rule, lineWidth: 0.8).frame(width: 48, height: 4)
            Text("❦").font(Lettering.prose(13)).foregroundStyle(parchment.fadedInk)
            InkRule().stroke(parchment.rule, lineWidth: 0.8).frame(width: 48, height: 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}
