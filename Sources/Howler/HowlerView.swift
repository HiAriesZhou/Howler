import AppKit
import HowlerCore
import SwiftUI

/// The Howler: a sheet of enchanted parchment. You write on the line at the top, next to the
/// provider's wax seal; pasted text or a captured screen region shows up as a second seal
/// in the corner instead of text in the field; the answer is written below by a quill, and
/// the sheet grows to fit it.
struct HowlerView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var settings: AppSettings
    let margins: EdgeInsets
    let openSettings: () -> Void
    let showProviderMenu: () -> Void
    /// Offers "Paste from Clipboard" and "Capture Screen Region".
    let showAttachMenu: () -> Void
    /// Reports the sheet height the content would like (the controller clamps it).
    let onDesiredHeight: (CGFloat) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var inputFocused: Bool
    @State private var headerHeight: CGFloat = 0
    @State private var transcriptHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var unfolded = true
    @State private var showingContext = false
    @State private var sheetSize: CGSize = .zero
    @State private var burnField: BurnField?

    var body: some View {
        let parchment = Parchment.forScheme(viewModel.candlelit ? .dark : .light)
        TimelineView(.animation(paused: viewModel.burnStartedAt == nil)) { timeline in
            let progress = burnProgress(at: timeline.date)
            ZStack(alignment: .top) {
                // The shadow goes with the first flames, so no outline of the sheet lingers.
                shadow.opacity(1 - min(max((progress ?? 0) * 3, 0), 1))
                ZStack(alignment: .top) {
                    sheet(parchment)
                    if settings.isConfigured {
                        letter(parchment)
                    } else {
                        SetupPage(pressKey: viewModel.openCount, openSettings: openSettings)
                    }
                }
                .modifier(BurningLetter(field: burnField, progress: progress))
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { sheetSize = $0 }
        .onChange(of: viewModel.burnStartedAt) { _, start in
            burnField = start == nil ? nil : BurnField(size: sheetSize)
        }
        .scaleEffect(unfolded ? 1 : 0.97, anchor: .top)
        .rotation3DEffect(.degrees(unfolded ? 0 : 10), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
        .opacity(unfolded ? 1 : 0)
        .padding(margins)
        .environment(\.parchment, parchment)
        .environment(\.copyText, viewModel.copyText)
        .onAppear(perform: focusInput)
        .onChange(of: viewModel.openCount) { _, _ in
            unfold()
            focusInput()
        }
        .onChange(of: viewModel.focusTick) { _, _ in focusInput() }
        .onChange(of: desiredHeight, initial: true) { _, height in onDesiredHeight(height) }
        .onChange(of: viewModel.attachment == nil) { _, isEmpty in
            if isEmpty { showingContext = false }
        }
    }

    private var hasTranscript: Bool {
        !viewModel.messages.isEmpty || viewModel.errorText != nil
    }

    private var desiredHeight: CGFloat {
        headerHeight + (hasTranscript ? transcriptHeight + footerHeight : 0)
    }

    private func burnProgress(at date: Date) -> Double? {
        guard let start = viewModel.burnStartedAt, burnField != nil else { return nil }
        return BurnField.progress(elapsed: date.timeIntervalSince(start))
    }

    // MARK: Sheet

    /// Cast separately from the sheet so it can fade while the paper burns. The sheet's
    /// own area is cut out, so holes burned in the paper show the desktop, not a backing.
    private var shadow: some View {
        ZStack {
            DeckledSheet()
                .fill(Color.black)
                .shadow(color: .black.opacity(0.30), radius: 20, x: 0, y: 12)
                .shadow(color: .black.opacity(0.14), radius: 1.5, x: 0, y: 1)
            DeckledSheet()
                .fill(Color.black)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private func sheet(_ parchment: Parchment) -> some View {
        DeckledSheet()
            .fill(parchment.paper)
            .overlay(PaperTexture().clipShape(DeckledSheet()))
    }

    private func letter(_ parchment: Parchment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                header(parchment)
                if showingContext, let attachment = viewModel.attachment {
                    ContextCard(attachment: attachment) {
                        withAnimation(.easeOut(duration: 0.2)) { viewModel.removeAttachment() }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }

            if hasTranscript {
                Transcript(viewModel: viewModel, contentHeight: $transcriptHeight)
                footer(parchment)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            } else {
                EmptyPage(hasAttachment: viewModel.attachment != nil)
            }
        }
    }

    // MARK: Header: stamp, writing line, sigil

    private func header(_ parchment: Parchment) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Button(action: showProviderMenu) {
                ProviderStamp(provider: settings.activeProvider, pressKey: viewModel.openCount)
            }
            .buttonStyle(.plain)
            .help(stampHelp)

            VStack(alignment: .leading, spacing: 3) {
                TextField("Question", text: $viewModel.input, prompt: Text(placeholder), axis: .vertical)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(Lettering.hand(21))
                    .foregroundStyle(parchment.ink)
                    .tint(parchment.seal)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .onSubmit(viewModel.send)
                InkRule()
                    .stroke(parchment.rule, lineWidth: 0.9)
                    .frame(height: 5)
            }
            .padding(.top, 9)

            if viewModel.isStreaming {
                Button(action: viewModel.stop) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(parchment.seal)
                }
                .buttonStyle(.plain)
                .help("Lift the quill (stop)")
                .padding(.top, 12)
            }

            sigil
        }
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var sigil: some View {
        if let attachment = viewModel.attachment {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showingContext.toggle() }
            } label: {
                AttachmentSigil(
                    mode: .sealed(symbol: attachment.image == nil ? "doc.text" : "photo"),
                    caption: "\(attachment.title)\n\(attachment.sizeLabel)",
                    appearKey: viewModel.attachmentStamp
                )
            }
            .buttonStyle(.plain)
            .help("\(attachment.summary) — sealed into your next question. Click to read or remove it.")
            .accessibilityLabel("Attached context: \(attachment.summary)")
        } else {
            Button(action: showAttachMenu) {
                AttachmentSigil(mode: .empty, caption: "Attach", appearKey: viewModel.openCount)
            }
            .buttonStyle(.plain)
            .help("Seal in pasted text, a picture, or a region of the screen")
            .accessibilityLabel("Attach context")
        }
    }

    private var placeholder: String {
        viewModel.attachment == nil ? "Write upon the parchment…" : "Ask about it, or just press ↩…"
    }

    private var stampHelp: String {
        guard let provider = settings.activeProvider else { return "Choose a provider" }
        return "\(provider.displayName) · \(settings.model(for: provider)) — click to switch"
    }

    // MARK: Footer

    private func footer(_ parchment: Parchment) -> some View {
        VStack(spacing: 7) {
            InkRule()
                .stroke(parchment.rule.opacity(0.7), lineWidth: 0.7)
                .frame(height: 4)
            HStack {
                if let provider = settings.activeProvider {
                    Text("\(provider.displayName) · \(settings.model(for: provider))")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 16)
                Text("↩ write · ⇧⌘C copy · esc burn")
            }
            .font(Lettering.marginalia(11.5))
            .foregroundStyle(parchment.fadedInk)
        }
        .padding(.horizontal, 26)
        .padding(.top, 2)
        .padding(.bottom, 14)
    }

    // MARK: Motion

    /// The panel may not be key yet when this runs, and assigning `true` to a focus state
    /// that is already `true` does nothing, so clear it and set it again on the next turn.
    private func focusInput() {
        inputFocused = false
        DispatchQueue.main.async { inputFocused = true }
    }

    /// The sheet drops into place like paper laid on a desk.
    private func unfold() {
        guard !reduceMotion else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { unfolded = false }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { unfolded = true }
        }
    }
}

/// What's sealed in, unfolded below the writing line when the sigil is clicked.
private struct ContextCard: View {
    let attachment: ContextAttachment
    let remove: () -> Void

    @Environment(\.parchment) private var parchment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(attachment.isTruncated ? "\(attachment.summary) · trimmed" : attachment.summary)
                    .font(Lettering.marginalia(12))
                    .foregroundStyle(parchment.magic)
                Spacer()
                Button("Remove", action: remove)
                    .buttonStyle(.plain)
                    .font(Lettering.marginalia(12))
                    .foregroundStyle(parchment.seal)
            }
            if let image = attachment.image, let picture = NSImage(data: image.data) {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 150, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(attachment.preview(maxLines: 8))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(parchment.fadedInk)
                    .lineLimit(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(parchment.codeWash.opacity(0.55), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(parchment.magic.opacity(0.55), style: StrokeStyle(lineWidth: 0.7, dash: [3, 2]))
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

/// The blank parchment, before the first question.
private struct EmptyPage: View {
    let hasAttachment: Bool
    @Environment(\.parchment) private var parchment

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Text(hasAttachment ? "Your context is sealed in — ask about it." : "Write a question, and the quill will answer.")
                .font(Lettering.script(23))
                .foregroundStyle(parchment.fadedInk.opacity(0.8))
                .contentTransition(.opacity)
            Text("↩ send · ⌥↩ new line · esc burn")
                .font(Lettering.marginalia(11.5))
                .foregroundStyle(parchment.fadedInk.opacity(0.6))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
        .animation(.easeInOut(duration: 0.3), value: hasAttachment)
    }
}

/// Shown until a provider and key are configured.
private struct SetupPage: View {
    let pressKey: Int
    let openSettings: () -> Void
    @Environment(\.parchment) private var parchment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ProviderStamp(provider: nil, pressKey: pressKey)
                VStack(alignment: .leading, spacing: 6) {
                    Text("This parchment has no ink yet.")
                        .font(Lettering.script(27))
                        .foregroundStyle(parchment.ink)
                    Text("Choose a provider and paste an API key, and it will start answering.")
                        .font(Lettering.prose(14))
                        .foregroundStyle(parchment.fadedInk)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 12)
            HStack {
                Spacer()
                Button(action: openSettings) {
                    Text("Open Settings")
                        .font(Lettering.proseBold(14))
                        .foregroundStyle(parchment.paper)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(parchment.seal))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}
