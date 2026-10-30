import AppKit
import HowlerCore
import SwiftUI

/// Drives the quill: reveals streamed text at a handwriting pace (see `QuillPacing`) and
/// supplies the clock for its motion. Ticks only while a reply is being written.
@MainActor
final class QuillPacer: ObservableObject {
    struct Frame: Equatable {
        /// Characters inked so far; fractional while the next one is still appearing.
        var revealed: Double = 0
        /// Seconds since the question was sent.
        var time: TimeInterval = 0
    }

    @Published private(set) var frame = Frame()
    /// Called once the stream has ended and the ink has caught up with it.
    var onCaughtUp: (() -> Void)?
    /// Reduce Motion: reveal text as it arrives, without pacing.
    var instant = false {
        didSet {
            guard instant != oldValue else { return }
            if instant { frame.revealed = Double(target) }
            if timer != nil { startTimer() }
        }
    }

    private var target = 0
    private var streamEnded = false
    private var startedAt: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var timer: Timer?

    func begin() {
        stopTimer()
        target = 0
        streamEnded = false
        startedAt = CACurrentMediaTime()
        lastTick = startedAt
        frame = Frame()
        startTimer()
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: instant ? 1 : 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common) // keep writing while the user scrolls
        self.timer = timer
    }

    func update(target: Int) {
        self.target = target
        if instant { frame.revealed = Double(target) }
    }

    func endStream() {
        streamEnded = true
        if instant || timer == nil { finish() }
    }

    /// Ink everything received so far at once (Stop, or a new question cutting in).
    func snapToEnd() {
        streamEnded = true
        frame.revealed = Double(target)
        finish()
    }

    func reset() {
        stopTimer()
        target = 0
        streamEnded = false
        frame = Frame()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = now - lastTick
        lastTick = now
        let revealed = instant
            ? Double(target)
            : QuillPacing.advance(frame.revealed, toward: target, elapsed: elapsed)
        frame = Frame(revealed: revealed, time: now - startedAt)
        if streamEnded && revealed >= Double(target) { finish() }
    }

    private func finish() {
        stopTimer()
        onCaughtUp?()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

/// The quill itself, drawn as vector art so it can be painted both by SwiftUI views and
/// from inside a `TextRenderer` (where it follows the last written glyph).
enum QuillArt {
    struct Inks {
        var ink: Color
        var vane: Color
        var magic: Color
    }

    /// The nib in the art's 100×100 design space; everything is placed relative to it.
    private static let nib = CGPoint(x: 3, y: 97)

    enum Motion {
        case writing
        case thinking
    }

    /// Pose for a moment in time: writing is a quick scribble, thinking a slow hover.
    static func pose(_ motion: Motion, time: Double) -> (angle: Angle, lift: CGSize) {
        switch motion {
        case .writing:
            return (
                .degrees(sin(time * 17) * 3.2 + sin(time * 5.3) * 1.5),
                CGSize(width: sin(time * 6.1) * 0.8, height: -abs(sin(time * 8.5)) * 1.8)
            )
        case .thinking:
            return (
                .degrees(sin(time * 1.7) * 6 - 4),
                CGSize(width: sin(time * 1.1) * 1.5, height: -6 + sin(time * 2.4) * 3.5)
            )
        }
    }

    /// Draws the quill with its nib at `nibPoint`, `height` points tall.
    static func draw(
        in context: inout GraphicsContext,
        nibPoint: CGPoint,
        height: CGFloat,
        angle: Angle,
        inks: Inks,
        glow: Double
    ) {
        var ctx = context
        ctx.translateBy(x: nibPoint.x, y: nibPoint.y)
        ctx.rotate(by: angle)
        let scale = height / 100
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -nib.x, y: -nib.y)

        if glow > 0 {
            let radius: CGFloat = 9
            ctx.fill(
                Path(ellipseIn: CGRect(x: nib.x - radius, y: nib.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [inks.magic.opacity(0.55 * glow), inks.magic.opacity(0)]),
                    center: nib, startRadius: 0, endRadius: radius
                )
            )
        }

        // Vane: a long, asymmetric feather from just above the grip to the tip.
        var vane = Path()
        vane.move(to: CGPoint(x: 22, y: 78))
        vane.addCurve(to: CGPoint(x: 97, y: 2), control1: CGPoint(x: 8, y: 44), control2: CGPoint(x: 52, y: -2))
        vane.addCurve(to: CGPoint(x: 22, y: 78), control1: CGPoint(x: 100, y: 34), control2: CGPoint(x: 64, y: 70))
        vane.closeSubpath()
        ctx.fill(vane, with: .linearGradient(
            Gradient(colors: [inks.vane, inks.vane.opacity(0.92), inks.ink.opacity(0.35)]),
            startPoint: CGPoint(x: 30, y: 70), endPoint: CGPoint(x: 97, y: 2)
        ))

        // Barbs: fine diagonal strokes off the shaft, with a couple of splits in the vane.
        for step in stride(from: 0.12, through: 0.92, by: 0.07) {
            let base = point(onShaftAt: step)
            let upper = CGPoint(x: base.x - 15 * (1 - step * 0.5), y: base.y - 10)
            let lower = CGPoint(x: base.x + 13 * (1 - step * 0.4), y: base.y + 4)
            var barb = Path()
            barb.move(to: base)
            barb.addQuadCurve(to: upper, control: CGPoint(x: base.x - 5, y: base.y - 7))
            barb.move(to: base)
            barb.addQuadCurve(to: lower, control: CGPoint(x: base.x + 6, y: base.y - 1))
            ctx.stroke(barb, with: .color(inks.ink.opacity(0.18)), lineWidth: 0.6)
        }
        ctx.stroke(vane, with: .color(inks.ink.opacity(0.55)), lineWidth: 0.9)

        // Shaft (rachis) and the darker, ink-stained barrel and nib.
        var shaft = Path()
        shaft.move(to: nib)
        shaft.addQuadCurve(to: CGPoint(x: 94, y: 6), control: CGPoint(x: 46, y: 56))
        ctx.stroke(shaft, with: .color(inks.ink.opacity(0.75)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

        var barrel = Path()
        barrel.move(to: nib)
        barrel.addLine(to: CGPoint(x: 20, y: 80))
        ctx.stroke(barrel, with: .color(inks.ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        var tip = Path()
        tip.move(to: CGPoint(x: nib.x - 1.5, y: nib.y + 1.5))
        tip.addLine(to: CGPoint(x: nib.x + 3, y: nib.y - 6))
        tip.addLine(to: CGPoint(x: nib.x + 6, y: nib.y - 3))
        tip.closeSubpath()
        ctx.fill(tip, with: .color(inks.ink))
    }

    private static func point(onShaftAt t: CGFloat) -> CGPoint {
        // Quadratic Bézier from the nib to (94, 6) via (46, 56).
        let start = nib, control = CGPoint(x: 46, y: 56), end = CGPoint(x: 94, y: 6)
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }
}

extension Parchment {
    var quillInks: QuillArt.Inks {
        QuillArt.Inks(ink: ink, vane: Color(hex: 0xFFFBF0), magic: magic)
    }
}

/// A standalone quill, nib at the bottom-leading corner of its frame.
struct QuillView: View {
    let motion: QuillArt.Motion
    let time: Double
    var height: CGFloat = 34
    var reduceMotion: Bool?

    @Environment(\.parchment) private var parchment
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        Canvas { context, size in
            let clock = (reduceMotion ?? systemReduceMotion) ? 0 : time
            let pose = QuillArt.pose(motion, time: clock)
            QuillArt.draw(
                in: &context,
                nibPoint: CGPoint(x: 4 + pose.lift.width, y: size.height - 4 + pose.lift.height),
                height: height,
                angle: pose.angle,
                inks: parchment.quillInks,
                glow: motion == .writing ? 1 : 0.5 + 0.5 * sin(clock * 3)
            )
        }
        .frame(width: height + 12, height: height + 12)
        .accessibilityHidden(true)
    }
}

/// Before the first word: the quill hovers over the page while the model thinks.
struct ThinkingLine: View {
    let time: Double
    @Environment(\.parchment) private var parchment

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            QuillView(motion: .thinking, time: time)
            Text(label)
                .font(Lettering.marginalia(14))
                .foregroundStyle(parchment.fadedInk)
                .padding(.bottom, 6)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thinking")
    }

    private var label: String {
        let seconds = Int(time)
        return seconds >= 2 ? "The quill is thinking… \(seconds)s" : "The quill is thinking…"
    }
}
