import HowlerCore
import SwiftUI

/// Sealing wax in three tones: lit, body and shadow.
struct Wax {
    let light: Color
    let base: Color
    let deep: Color

    static let crimson = Wax(light: Color(hex: 0xD9503F), base: Color(hex: 0xA0211B), deep: Color(hex: 0x560B08))
    static let amber = Wax(light: Color(hex: 0xF0C46A), base: Color(hex: 0xB5801F), deep: Color(hex: 0x5E3B08))
}

/// A blob of sealing wax pressed with a signet: an irregular puddle, a sunken disc where
/// the seal went in, and the mark standing in relief.
struct WaxSeal<Mark: View>: View {
    let wax: Wax
    var size: CGFloat = 48
    /// Shapes the puddle, so each seal spreads a little differently.
    var seed: UInt64 = 1
    /// Runes cut around the rim of the impression.
    var engraved = false
    @ViewBuilder let mark: () -> Mark

    var body: some View {
        ZStack {
            WaxPuddle(seed: seed)
                .fill(RadialGradient(
                    colors: [wax.light, wax.base, wax.deep],
                    center: UnitPoint(x: 0.36, y: 0.3),
                    startRadius: 0,
                    endRadius: size * 0.78
                ))
                .shadow(color: .black.opacity(0.38), radius: 1.2, x: 0.6, y: 1.4)
                .shadow(color: wax.deep.opacity(0.35), radius: 4, x: 0, y: 2.5)

            // The impression: sunken, so its rim is dark toward the light and lit away from it.
            Circle()
                .fill(RadialGradient(
                    colors: [wax.base, wax.deep.opacity(0.85)],
                    center: UnitPoint(x: 0.6, y: 0.65),
                    startRadius: 0,
                    endRadius: size * 0.42
                ))
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [wax.deep, wax.deep.opacity(0.4), wax.light.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: size * 0.035
                    )
                )
                .frame(width: size * 0.7, height: size * 0.7)

            if engraved {
                RuneRing()
                    .stroke(wax.deep.opacity(0.75), style: StrokeStyle(lineWidth: max(0.7, size * 0.018), lineCap: .round))
                    .frame(width: size * 0.66, height: size * 0.66)
            }

            // Relief: a lit edge offset toward the light, then the mark in shadowed wax.
            mark().foregroundStyle(wax.light.opacity(0.8)).offset(x: -0.6, y: -0.7)
            mark().foregroundStyle(wax.deep)

            Ellipse()
                .fill(Color.white.opacity(0.32))
                .frame(width: size * 0.3, height: size * 0.12)
                .rotationEffect(.degrees(-32))
                .offset(x: -size * 0.19, y: -size * 0.25)
                .blur(radius: 1.2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The outline of a puddle of wax: round-ish, with soft lumps where it spread.
struct WaxPuddle: Shape {
    let seed: UInt64

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let count = 18
        let points: [CGPoint] = (0..<count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi
            let wobble = 0.85 + 0.15 * (SeededRandom.jitter(index, seed: seed) + 1) / 2
            return CGPoint(x: center.x + cos(angle) * radius * wobble, y: center.y + sin(angle) * radius * wobble)
        }
        // Smooth closed curve through the midpoints, using each point as a control.
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var path = Path()
        path.move(to: mid(points[count - 1], points[0]))
        for index in 0..<count {
            path.addQuadCurve(to: mid(points[index], points[(index + 1) % count]), control: points[index])
        }
        path.closeSubpath()
        return path
    }
}

/// The model service's mark as a crimson wax seal (a monochrome letter or symbol — never a
/// trademarked logo). It is pressed again each time the letter opens or the service
/// changes.
struct ProviderStamp: View {
    let glyph: ProviderGlyph?
    /// Changes whenever the seal should be pressed again.
    let pressKey: Int
    var size: CGFloat = 48

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = true

    var body: some View {
        WaxSeal(wax: .crimson, size: size, seed: seed) {
            mark
        }
        .rotationEffect(.degrees(-8))
        .scaleEffect(pressed ? 1 : 1.6)
        .opacity(pressed ? 1 : 0)
        .onAppear(perform: press)
        .onChange(of: pressKey) { _, _ in press() }
        .onChange(of: glyph) { _, _ in press() }
    }

    private var seed: UInt64 {
        switch glyph {
        case .letters(let text), .symbol(let text): return UInt64(text.utf8.reduce(0) { $0 + Int($1) })
        case nil: return 7
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch glyph {
        case .letters(let letters):
            Text(letters).font(Lettering.proseBold(size * 0.38))
        case .symbol(let name):
            Image(systemName: name).font(.system(size: size * 0.3, weight: .bold))
        case nil:
            Text("?").font(Lettering.proseBold(size * 0.38))
        }
    }

    private func press() {
        guard !reduceMotion else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { pressed = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { pressed = true }
        }
    }
}

/// The amber seal in the letter's corner that stands for attached context. Sealed: the
/// context will travel with the next question. Empty: a bare spot for wax, where a click
/// offers to paste or capture something.
struct AttachmentSigil: View {
    enum Mode: Equatable {
        case sealed(symbol: String)
        case empty
    }

    let mode: Mode
    let caption: String
    /// Changes whenever the seal should be pressed again.
    let appearKey: Int

    @Environment(\.parchment) private var parchment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = true

    var body: some View {
        VStack(spacing: 4) {
            switch mode {
            case .sealed(let symbol):
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                    let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    WaxSeal(wax: .amber, size: 44, seed: 31, engraved: true) {
                        Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                    }
                    // A faint enchantment: the seal glows as if warm.
                    .shadow(color: parchment.magic.opacity(0.25 + 0.2 * sin(time * 2.2)), radius: 8)
                }
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(7))
            case .empty:
                ZStack {
                    Circle()
                        .strokeBorder(parchment.magic.opacity(0.7), style: StrokeStyle(lineWidth: 1.1, dash: [3, 3]))
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(parchment.magic)
                }
                .frame(width: 40, height: 40)
                .padding(2)
            }
            Text(caption)
                .font(Lettering.marginalia(10.5))
                .foregroundStyle(mode == .empty ? parchment.fadedInk : parchment.magic)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize()
        }
        .opacity(mode == .empty ? 0.6 : 1)
        .scaleEffect(appeared ? 1 : 1.7)
        .opacity(appeared ? 1 : 0)
        .onAppear(perform: pressIn)
        .onChange(of: appearKey) { _, _ in pressIn() }
        .onChange(of: mode) { _, _ in pressIn() }
    }

    private func pressIn() {
        guard !reduceMotion else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.58)) { appeared = true }
        }
    }
}

/// Eight small runes cut around the rim of a seal's impression.
private struct RuneRing: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * 0.8
        let tick = radius * 0.16
        for index in 0..<8 {
            let angle = Double(index) / 8 * 2 * .pi + .pi / 8
            let outward = CGPoint(x: cos(angle), y: sin(angle))
            let across = CGPoint(x: -outward.y, y: outward.x)
            let base = CGPoint(x: center.x + outward.x * (radius - tick), y: center.y + outward.y * (radius - tick))
            let top = CGPoint(x: center.x + outward.x * (radius + tick), y: center.y + outward.y * (radius + tick))
            path.move(to: base)
            path.addLine(to: top)
            // Each rune gets a different branch so the ring doesn't look mechanical.
            let branch = (index.isMultiple(of: 2) ? 1.0 : -1.0) * tick
            let mid = CGPoint(x: (base.x + top.x) / 2, y: (base.y + top.y) / 2)
            path.move(to: mid)
            path.addLine(to: CGPoint(x: mid.x + across.x * branch + outward.x * tick * 0.7,
                                     y: mid.y + across.y * branch + outward.y * tick * 0.7))
            if index % 3 == 0 {
                path.move(to: top)
                path.addLine(to: CGPoint(x: top.x - across.x * tick, y: top.y - across.y * tick))
            }
        }
        return path
    }
}
