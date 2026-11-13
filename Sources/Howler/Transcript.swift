import AppKit
import HowlerCore
import SwiftUI

/// Everything written on the letter so far, newest exchange first, right under the writing
/// line. The page grows downward; once the sheet is full, older exchanges continue below
/// the fold. The page never scrolls on its own to follow the quill.
///
/// A reader at the top stays there and watches the newest answer grow below the line.
/// A reader who has scrolled down keeps their place: when the newest answer grows above
/// the view, or the next queued exchange begins, the page moves down by the same amount.
/// Asking a question returns to the top.
struct Transcript: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var contentHeight: CGFloat
    @Environment(\.parchment) private var parchment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scroller = PageScroller()
    @State private var scrollOffset: CGFloat = 0
    @State private var newest: TrackedTurn?
    @State private var layout: TranscriptLayout?

    /// How close to the top still counts as reading the newest exchange.
    private static let topSlack: CGFloat = 40
    private static let topID = "top"

    var body: some View {
        let turns = viewModel.turns
        let taskCount = viewModel.queue.tasks.count
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.topID)
                    VStack(alignment: .leading, spacing: 14) {
                        if let error = viewModel.errorText {
                            ErrorLine(text: error)
                        }
                        ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                            VStack(alignment: .leading, spacing: 14) {
                                if index > 0 { Flourish().padding(.vertical, 6) }
                                QuestionLine(message: turn.question)
                                answer(for: turn.answer)
                            }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("transcript")) } action: { frame in
                                if index == 0 { holdIfGrownAbove(turn.id, frame) }
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .background(ScrollViewLocator(scroller: scroller))
                .onGeometryChange(for: TranscriptLayout.self) {
                    TranscriptLayout(frame: $0.frame(in: .named("transcript")),
                                     newest: turns.first?.id, tasks: taskCount)
                } action: { next in
                    let previous = layout
                    layout = next
                    scrollOffset = -next.frame.minY
                    contentHeight = next.frame.height
                    guard let previous else { return }
                    if next.tasks > previous.tasks {
                        scrollToTop(proxy)
                    } else if next.newest != previous.newest {
                        if scrollOffset < Self.topSlack {
                            scrollToTop(proxy)
                        } else {
                            scroller.shift(by: next.frame.height - previous.frame.height)
                        }
                    }
                }
            }
            .coordinateSpace(name: "transcript")
            .scrollIndicators(.never)
            .mask(PageFade())
        }
    }

    /// Keeps a reader below the newest exchange in place while its answer is written.
    private func holdIfGrownAbove(_ id: UUID, _ frame: CGRect) {
        let previous = newest
        newest = TrackedTurn(id: id, frame: frame)
        guard let previous, previous.id == id else { return }
        let growth = frame.height - previous.frame.height
        guard abs(growth) > 0.5, previous.frame.maxY <= 0 else { return }
        scroller.shift(by: growth)
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                proxy.scrollTo(Self.topID, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func answer(for message: ChatMessage) -> some View {
        if message.id == viewModel.writingID {
            WritingAnswer(content: message.content, quill: viewModel.quill)
        } else if !message.content.isEmpty {
            VStack(alignment: .trailing, spacing: 2) {
                InkMarkdown(markdown: message.content)
                CopyAnswerButton(copied: viewModel.copiedID == message.id) {
                    viewModel.copy(message)
                }
            }
            .transition(.opacity)
        }
        if viewModel.queue.tasks.contains(where: { $0.replyID == message.id && $0.state == .skipped }) {
            Text("Incomplete reply · skipped")
                .font(Lettering.marginalia(12))
                .foregroundStyle(parchment.error)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Incomplete reply. Skipped by user.")
        }
    }
}

/// Text scrolling under the writing line or the footer fades into the paper instead of
/// being cut off (and stands in for a scroll bar, which would look foreign on paper).
private struct PageFade: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 10)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16)
        }
    }
}

/// A reply mid-stroke: thinking, then ink appearing under the quill.
private struct WritingAnswer: View {
    let content: String
    @ObservedObject var quill: QuillPacer

    var body: some View {
        let frame = quill.frame
        let count = Int(frame.revealed.rounded(.up))
        if count == 0 {
            ThinkingLine(time: frame.time)
        } else {
            InkMarkdown(
                markdown: String(content.prefix(count)),
                writing: WritingState(gap: Double(count) - frame.revealed, time: frame.time)
            )
        }
    }
}

private struct QuestionLine: View {
    let message: ChatMessage
    @Environment(\.parchment) private var parchment

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let attachment = message.attachment {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(parchment.magic)
                    .help("Asked with \(attachment.summary)")
                    .accessibilityLabel("With \(attachment.summary)")
            }
            Text(message.content)
                .font(Lettering.hand(18))
                .foregroundStyle(parchment.ink.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

private struct ErrorLine: View {
    let text: String
    @Environment(\.parchment) private var parchment

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("✗")
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Lettering.marginalia(14))
        .foregroundStyle(parchment.error)
        .textSelection(.enabled)
    }
}

private struct CopyAnswerButton: View {
    let copied: Bool
    let action: () -> Void

    @Environment(\.parchment) private var parchment
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(copied ? "✓ Copied" : "❧ Copy")
                .font(Lettering.marginalia(12))
                .foregroundStyle(copied ? parchment.magic : parchment.fadedInk.opacity(hovering ? 1 : 0.7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy this answer")
        .animation(.easeOut(duration: 0.15), value: copied)
    }
}

private struct TrackedTurn {
    let id: UUID
    let frame: CGRect
}

private struct TranscriptLayout: Equatable {
    let frame: CGRect
    let newest: UUID?
    let tasks: Int
}

/// Moves the transcript's AppKit scroll view by an exact distance, which SwiftUI's
/// `ScrollView` cannot do on macOS 14.
@MainActor
private final class PageScroller {
    weak var scrollView: NSScrollView?

    func shift(by distance: CGFloat) {
        guard let scrollView else { return }
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: max(0, clip.bounds.origin.y + distance)))
        scrollView.reflectScrolledClipView(clip)
    }
}

/// Finds the scroll view that hosts the transcript.
private struct ScrollViewLocator: NSViewRepresentable {
    let scroller: PageScroller

    func makeNSView(context: Context) -> NSView { LocatorView(scroller: scroller) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class LocatorView: NSView {
        let scroller: PageScroller

        init(scroller: PageScroller) {
            self.scroller = scroller
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scroller.scrollView = enclosingScrollView
        }
    }
}
