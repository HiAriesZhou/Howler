import HowlerCore
import SwiftUI

/// Everything written on the letter so far. Follows the quill down the page only while
/// the reader is already at the bottom, so scrolling up to reread is never yanked back.
struct Transcript: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var contentHeight: CGFloat

    @State private var viewportHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    /// How close to the bottom still counts as "following along".
    private static let followSlack: CGFloat = 90
    private static let bottomID = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        switch message.role {
                        case .user:
                            if index > 0 { Flourish().padding(.vertical, 6) }
                            QuestionLine(message: message)
                        case .assistant:
                            answer(for: message)
                        }
                    }
                    if let error = viewModel.errorText {
                        ErrorLine(text: error)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, 30)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("transcript")) } action: { frame in
                    scrollOffset = -frame.minY
                    if abs(frame.height - contentHeight) > 0.5 {
                        let wasFollowing = contentHeight - (scrollOffset + viewportHeight) < Self.followSlack
                        contentHeight = frame.height
                        // The sheet grows first; only once it is at full height does the
                        // page itself need to scroll after the quill.
                        guard wasFollowing else { return }
                        DispatchQueue.main.async {
                            if contentHeight > viewportHeight + 0.5 {
                                proxy.scrollTo(Self.bottomID, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: "transcript")
            .scrollIndicators(.never)
            .mask(PageFade())
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .onChange(of: viewModel.messages.count) { _, _ in
                // A new question always brings the page back to the bottom.
                DispatchQueue.main.async { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
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
                CopyAnswerButton(
                    copied: viewModel.copiedID == message.id,
                    isLatest: message.id == viewModel.lastAnswer?.id
                ) {
                    viewModel.copy(message)
                }
            }
            .transition(.opacity)
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
    let isLatest: Bool
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
        .keyboardShortcut(isLatest ? KeyboardShortcut("c", modifiers: [.command, .shift]) : nil)
        .help("Copy this answer")
        .animation(.easeOut(duration: 0.15), value: copied)
    }
}
