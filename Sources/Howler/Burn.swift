import CoreGraphics
import SwiftUI

/// How a letter burns: for every patch of the sheet, the moment (0…1) the flame reaches
/// it. Fire is lit at two points below the bottom edge and climbs, with a ragged front
/// from layered noise, so the seal and the first line are the last to go.
struct BurnField {
    /// Seconds from the first flame to ash. Longer reads as dragging once you're done.
    static let duration: TimeInterval = 0.8
    /// Points per cell; the images are scaled up smoothly, which softens the front.
    private static let cell: CGFloat = 3

    let size: CGSize
    private let columns: Int
    private let rows: Int
    private let arrival: [Float]
    let embers: [Ember]

    struct Ember {
        let origin: CGPoint
        let lit: Double
        let rise: CGFloat
        let drift: CGFloat
        let radius: CGFloat
        let phase: Double
    }

    init(size: CGSize, seed: UInt64 = 0xF1AE) {
        self.size = size
        columns = max(2, Int(ceil(size.width / Self.cell)))
        rows = max(2, Int(ceil(size.height / Self.cell)))
        var random = SeededRandom(seed: seed)
        let ignitions = [
            CGPoint(x: CGFloat(columns) * random.range(0.15...0.35), y: CGFloat(rows) + 4),
            CGPoint(x: CGFloat(columns) * random.range(0.65...0.9), y: CGFloat(rows) + 10),
        ]
        let coarse = ValueNoise(seed: seed &+ 1, spacing: 18)
        let fine = ValueNoise(seed: seed &+ 2, spacing: 5)

        var times = [Float](repeating: 0, count: columns * rows)
        var lowest = Float.greatestFiniteMagnitude
        var highest = -Float.greatestFiniteMagnitude
        for row in 0..<rows {
            for column in 0..<columns {
                let point = CGPoint(x: CGFloat(column), y: CGFloat(row))
                let distance = ignitions.map { hypot($0.x - point.x, ($0.y - point.y) * 1.15) }.min() ?? 0
                let noise = 0.7 * coarse.value(column, row) + 0.3 * fine.value(column, row)
                let time = Float(distance) / Float(rows + columns / 3) + 0.32 * Float(noise)
                times[row * columns + column] = time
                lowest = min(lowest, time)
                highest = max(highest, time)
            }
        }
        let span = max(highest - lowest, 0.0001)
        arrival = times.map { ($0 - lowest) / span }

        // Sparks leave from wherever the front passes.
        var embers: [Ember] = []
        for _ in 0..<90 {
            let column = Int(random.range(0...CGFloat(columns - 1)))
            let row = Int(random.range(0...CGFloat(rows - 1)))
            embers.append(Ember(
                origin: CGPoint(x: CGFloat(column) * Self.cell, y: CGFloat(row) * Self.cell),
                lit: Double(arrival[row * columns + column]),
                rise: random.range(40...120),
                drift: random.range(-14...14),
                radius: random.range(0.8...2.2),
                phase: Double(random.range(0...6))
            ))
        }
        self.embers = embers
    }

    /// Burn progress for a moment of the animation: a brief catch, then the fire takes hold.
    static func progress(elapsed: TimeInterval) -> Double {
        let t = min(max(elapsed / duration, 0), 1)
        return -0.04 + 1.12 * pow(t, 1.2)
    }

    struct Frame {
        /// Opaque where paper remains.
        let mask: CGImage
        /// Scorch, char and the glowing edge, drawn over the paper.
        let scorch: CGImage
        /// The glowing edge alone, for a bloom around it.
        let glow: CGImage
    }

    func frame(at progress: Double) -> Frame? {
        let count = columns * rows
        var mask = [UInt8](repeating: 0, count: count * 4)
        var scorch = [UInt8](repeating: 0, count: count * 4)
        var glow = [UInt8](repeating: 0, count: count * 4)
        let p = Float(progress)
        for index in 0..<count {
            let d = arrival[index] - p // > 0: not burned yet
            let o = index * 4

            let intact = Self.clamp((d + 0.006) / 0.018)
            mask[o + 3] = UInt8(intact * 255)

            // Painted from the outside in: browning, char, then the burning edge on top.
            var color = (r: Float(0), g: Float(0), b: Float(0), a: Float(0))
            let tint = 1 - Self.clamp((d - 0.07) / 0.12)
            if tint > 0 { color = Self.over(color, (0.45, 0.25, 0.08), 0.28 * tint) }
            let char = 1 - Self.clamp((d - 0.018) / 0.07)
            if char > 0 { color = Self.over(color, (0.13, 0.07, 0.03), 0.9 * char) }
            let ember = d > -0.012 ? 1 - Self.clamp(d / 0.028) : 0
            if ember > 0 {
                let heat = Self.clamp(1 - d / 0.028) // 1 at the front
                let flame = (r: Float(1), g: 0.35 + 0.55 * heat, b: 0.08 + 0.4 * heat * heat)
                color = Self.over(color, flame, ember)
                glow[o] = UInt8(flame.r * ember * 255)
                glow[o + 1] = UInt8(flame.g * ember * 255)
                glow[o + 2] = UInt8(flame.b * ember * 255)
                glow[o + 3] = UInt8(ember * 255)
            }
            // Premultiplied RGBA.
            scorch[o] = UInt8(color.r * 255)
            scorch[o + 1] = UInt8(color.g * 255)
            scorch[o + 2] = UInt8(color.b * 255)
            scorch[o + 3] = UInt8(color.a * 255)
        }
        guard let maskImage = image(mask), let scorchImage = image(scorch), let glowImage = image(glow) else {
            return nil
        }
        return Frame(mask: maskImage, scorch: scorchImage, glow: glowImage)
    }

    private func image(_ pixels: [UInt8]) -> CGImage? {
        var pixels = pixels
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(
                data: buffer.baseAddress,
                width: columns,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: columns * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
    }

    private static func clamp(_ value: Float) -> Float { min(max(value, 0), 1) }

    /// Source-over compositing into premultiplied color.
    private static func over(
        _ under: (r: Float, g: Float, b: Float, a: Float),
        _ color: (r: Float, g: Float, b: Float),
        _ alpha: Float
    ) -> (r: Float, g: Float, b: Float, a: Float) {
        (
            r: color.r * alpha + under.r * (1 - alpha),
            g: color.g * alpha + under.g * (1 - alpha),
            b: color.b * alpha + under.b * (1 - alpha),
            a: alpha + under.a * (1 - alpha)
        )
    }
}

/// Smoothly interpolated lattice noise in 0…1.
private struct ValueNoise {
    let seed: UInt64
    let spacing: Int

    func value(_ x: Int, _ y: Int) -> Float {
        let gx = x / spacing, gy = y / spacing
        let fx = Float(x % spacing) / Float(spacing), fy = Float(y % spacing) / Float(spacing)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let top = lattice(gx, gy) + (lattice(gx + 1, gy) - lattice(gx, gy)) * sx
        let bottom = lattice(gx, gy + 1) + (lattice(gx + 1, gy + 1) - lattice(gx, gy + 1)) * sx
        return top + (bottom - top) * sy
    }

    private func lattice(_ x: Int, _ y: Int) -> Float {
        Float((SeededRandom.jitter(x &* 7919 &+ y &* 104_729, seed: seed) + 1) / 2)
    }
}

/// Draws a burning letter over `content`: the paper is eaten from the bottom up, with a
/// charred, glowing edge and sparks flying off it. With no burn in progress it changes
/// nothing — and keeps the same view structure, so scroll positions and focus survive
/// the moment the fire starts.
struct BurningLetter: ViewModifier {
    let field: BurnField?
    let progress: Double?

    func body(content: Content) -> some View {
        let frame = field.flatMap { field in progress.flatMap { field.frame(at: $0) } }
        content
            .overlay {
                if let frame {
                    Image(decorative: frame.scorch, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .blur(radius: 1.6)
                        .mask(DeckledSheet())
                }
            }
            .mask {
                if let frame {
                    Image(decorative: frame.mask, scale: 1).resizable().interpolation(.high).blur(radius: 1.2)
                } else {
                    Rectangle()
                }
            }
            .overlay {
                if let frame {
                    Image(decorative: frame.glow, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .blur(radius: 7)
                        .blendMode(.plusLighter)
                }
            }
            .overlay {
                if let field, let progress {
                    Sparks(field: field, progress: progress)
                }
            }
            .allowsHitTesting(frame == nil)
    }
}

private struct Sparks: View {
    let field: BurnField
    let progress: Double
    /// How long a spark lives, in burn progress.
    private let life = 0.22

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / max(field.size.width, 1)
            let scaleY = size.height / max(field.size.height, 1)
            for ember in field.embers where progress > ember.lit && progress < ember.lit + life {
                let age = (progress - ember.lit) / life
                let x = ember.origin.x * scaleX + ember.drift * CGFloat(age) + sin(ember.phase + age * 9) * 3
                let y = ember.origin.y * scaleY - ember.rise * CGFloat(age)
                let radius = ember.radius * CGFloat(1 - age * 0.5)
                let warmth = 1 - age
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius * 2, y: y - radius * 2, width: radius * 4, height: radius * 4)),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 1, green: 0.85, blue: 0.5).opacity(warmth),
                            Color(red: 1, green: 0.4, blue: 0.1).opacity(warmth * 0.6),
                            Color(red: 0.8, green: 0.15, blue: 0).opacity(0),
                        ]),
                        center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius * 2
                    )
                )
            }
        }
    }
}
