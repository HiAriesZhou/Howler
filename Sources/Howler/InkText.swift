import AppKit
import HowlerCore
import SwiftUI

/// Where the quill is in a reply that is still being written.
struct WritingState: Equatable {
    /// How much of the newest character is still missing (0 = fully inked, <1).
    var gap: Double
    /// Pacer clock, for the quill's motion.
    var time: Double
}

/// A reply in ink: prose in the book face, fenced code on a washed patch with a copy
/// button. While `writing` is set, the last block shows fresh ink and the quill.
struct InkMarkdown: View {
    let markdown: String
    var writing: WritingState?

    @Environment(\.parchment) private var parchment

    var body: some View {
        let source = writing == nil ? markdown : Self.hidingPartialFence(markdown)
        let blocks = Self.paragraphs(MarkdownBlocks.parse(source))
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                let isWritingBlock = writing != nil && index == blocks.count - 1
                switch block {
                case .prose(let text):
                    InkProse(text: text, writing: isWritingBlock ? writing : nil)
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                        .overlay(alignment: .bottomLeading) {
                            if isWritingBlock, let writing {
                                QuillView(motion: .writing, time: writing.time)
                                    .offset(x: 10, y: 6)
                            }
                        }
                }
            }
        }
    }

    static let fontSize: CGFloat = 15.5

    /// Mid-stream, a fence arrives one backtick at a time; don't show "`" or "``" as text
    /// while the quill is still writing it.
    static func hidingPartialFence(_ markdown: String) -> String {
        let lastBreak = markdown.lastIndex(of: "\n").map { markdown.index(after: $0) } ?? markdown.startIndex
        let lastLine = markdown[lastBreak...].trimmingCharacters(in: .whitespaces)
        guard (1...2).contains(lastLine.count), lastLine.allSatisfy({ $0 == "`" || $0 == "~" }) else {
            return markdown
        }
        return String(markdown[..<lastBreak])
    }

    /// Mid-stream, `**bold` or `` `code `` is open until its closing mark arrives; close it
    /// provisionally so the emphasis appears as it is written instead of raw asterisks.
    static func closingOpenMarks(_ text: String) -> String {
        var result = text
        if result.components(separatedBy: "**").count.isMultiple(of: 2) { result += "**" }
        let ticks = result.filter { $0 == "`" }.count
        if !ticks.isMultiple(of: 2) { result += "`" }
        return result
    }

    /// Blank lines become paragraph spacing rather than an empty line of text.
    static func paragraphs(_ blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        blocks.flatMap { block -> [MarkdownBlock] in
            guard case .prose(let text) = block else { return [block] }
            return text
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .newlines) }
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map(MarkdownBlock.prose)
        }
    }
}

private struct InkProse: View {
    let text: String
    let writing: WritingState?

    @Environment(\.parchment) private var parchment

    var body: some View {
        let base = Text(InkAttributed.make(writing == nil ? text : InkMarkdown.closingOpenMarks(text)))
            .font(Lettering.prose(InkMarkdown.fontSize))
            .foregroundStyle(parchment.ink)
            .lineSpacing(4)
            .tint(parchment.seal)
            .frame(maxWidth: .infinity, alignment: .leading)

        if let writing {
            if #available(macOS 15.0, *) {
                base.textRenderer(InkRenderer(writing: writing, inks: parchment.quillInks))
            } else {
                // No per-glyph layout before macOS 15: the quill rides at the paragraph's end.
                base.overlay(alignment: .bottomTrailing) {
                    QuillView(motion: .writing, time: writing.time).offset(x: 36, y: 4)
                }
            }
        } else {
            base.textSelection(.enabled)
        }
    }
}

/// Fresh ink: the newest glyphs bloom from a faint golden shimmer into dark ink, and the
/// quill's nib rests on the baseline just after the last glyph.
@available(macOS 15.0, *)
private struct InkRenderer: TextRenderer {
    let writing: WritingState
    let inks: QuillArt.Inks
    /// How many glyphs are still "wet".
    private let wetGlyphs = 14.0

    /// Room above the line for the quill's feather. No trailing padding: it widens the
    /// width the paragraph wraps at, so the line being written would reflow once the
    /// quill lifts (and the quill is not clipped at the trailing edge anyway).
    var displayPadding: EdgeInsets {
        EdgeInsets(top: 48, leading: 0, bottom: 12, trailing: 0)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let slices = layout.flatMap { line in line.flatMap { run in run } }
        let count = slices.count
        for (index, slice) in slices.enumerated() {
            let age = Double(count - 1 - index) + 1 - writing.gap
            let dryness = min(1, max(0, age / wetGlyphs))
            if dryness >= 1 {
                context.draw(slice)
                continue
            }
            var shimmer = context
            shimmer.opacity = (1 - dryness) * 0.7
            shimmer.addFilter(.colorInvert())
            shimmer.addFilter(.colorMultiply(inks.magic))
            shimmer.addFilter(.blur(radius: 0.6 + (1 - dryness) * 1.6))
            shimmer.draw(slice)

            var wet = context
            wet.opacity = 0.08 + 0.92 * dryness
            wet.draw(slice)
        }

        guard let last = slices.last else { return }
        let bounds = last.typographicBounds
        let pose = QuillArt.pose(.writing, time: writing.time)
        let nib = CGPoint(
            x: bounds.rect.maxX + 1.5 + pose.lift.width,
            y: bounds.origin.y - 1 + pose.lift.height
        )
        QuillArt.draw(in: &context, nibPoint: nib, height: 34, angle: pose.angle, inks: inks, glow: 1)
    }
}

/// Inline Markdown → `AttributedString`, memoized: while the quill writes, every frame
/// re-renders the reply, but only the block under the nib actually changes.
@MainActor
enum InkAttributed {
    private(set) static var cache: [String: AttributedString] = [:]

    static func clear() {
        cache.removeAll()
    }

    static func make(_ text: String) -> AttributedString {
        if let cached = cache[text] { return cached }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let value = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        if cache.count > 256 { cache.removeAll(keepingCapacity: true) }
        cache[text] = value
        return value
    }
}

private struct CopyTextKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension EnvironmentValues {
    /// How the letter copies its own text (so it isn't re-attached as fresh context).
    var copyText: (String) -> Void {
        get { self[CopyTextKey.self] }
        set { self[CopyTextKey.self] = newValue }
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    @Environment(\.parchment) private var parchment
    @Environment(\.copyText) private var copyText
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(Lettering.marginalia(11.5))
                    .foregroundStyle(parchment.fadedInk)
                Spacer()
                Button {
                    copyText(code)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(parchment.fadedInk)
                }
                .buttonStyle(.borderless)
                .help("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.top, 7)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(parchment.ink)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            }
        }
        .background(parchment.codeWash.opacity(0.75), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(parchment.rule.opacity(0.8), style: StrokeStyle(lineWidth: 0.7, dash: [3, 2]))
        )
    }
}
