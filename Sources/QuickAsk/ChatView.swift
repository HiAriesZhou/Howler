import QuickAskCore
import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void

    @FocusState private var inputFocused: Bool

    var body: some View {
        Group {
            if settings.isConfigured, let provider = settings.activeProvider {
                chat(provider: provider)
            } else {
                notConfigured
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Not configured

    private var notConfigured: some View {
        VStack(spacing: 12) {
            Text("\(AppInfo.name) needs an AI provider and API key.")
                .font(.headline)
            Button("Configure in Settings", action: openSettings)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: Chat

    private func chat(provider: Provider) -> some View {
        VStack(spacing: 0) {
            inputBar(provider: provider)
            if !viewModel.messages.isEmpty || viewModel.errorText != nil {
                Divider()
                transcript
                Divider()
                footer(provider: provider)
            }
        }
    }

    private func inputBar(provider: Provider) -> some View {
        HStack(spacing: 12) {
            ProviderGlyphView(provider: provider, size: 24)
            TextField("Ask anything…", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit { viewModel.send() }
            if viewModel.isStreaming {
                Button {
                    viewModel.stop()
                } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.borderless)
                .help("Stop")
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: PanelController.compactHeight)
        .onAppear { inputFocused = true }
        .onChange(of: viewModel.focusRequest) { _, _ in inputFocused = true }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.messages) { message in
                        MessageRow(
                            message: message,
                            isPending: viewModel.isStreaming && message.id == viewModel.messages.last?.id
                        )
                    }
                    if let error = viewModel.errorText {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(18)
            }
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    private static let bottomID = "bottom"

    private func footer(provider: Provider) -> some View {
        HStack {
            Text("\(provider.displayName) · \(settings.model(for: provider))")
            Spacer()
            Text("↩ send · ⌥↩ newline · esc close")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let isPending: Bool

    var body: some View {
        switch message.role {
        case .user:
            Text(message.content)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        case .assistant:
            if message.content.isEmpty {
                if isPending {
                    ProgressView().controlSize(.small)
                }
            } else {
                MarkdownView(markdown: message.content)
            }
        }
    }
}
