import AppKit
import HowlerCore
import SwiftUI

/// The model section of Settings: what writes the letters and whether it works, plus the
/// setup prompt. The setup itself happens on the command line, usually through an AI
/// assistant, so this page never asks for an API key.
struct ModelSettings: View {
    @ObservedObject var settings: AppSettings

    @State private var copied = false

    var body: some View {
        Group {
            if let service = settings.service {
                configured(service)
            } else {
                setupGuide
            }
        }
        .onAppear { settings.reload() }
    }

    // MARK: Set up

    /// No model yet: how to get one, step by step, ending in the button that starts it.
    private var setupGuide: some View {
        HStack(alignment: .top, spacing: 14) {
            ProviderStamp(glyph: nil, pressKey: 0, size: 40)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Set up a model")
                        .font(.title3.weight(.semibold))
                    Text("An AI assistant does it for you in a minute.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 7) {
                    step(1, "Copy the setup prompt.")
                    step(2, "Paste it into Claude Code, Codex or another AI assistant that can run commands.")
                    step(3, "Pick a model, and copy your API key when it asks. It never needs the key in the chat.")
                }
                HStack(spacing: 10) {
                    copyButton
                        .buttonStyle(.borderedProminent)
                        .tint(Wax.crimson.base)
                    if copied {
                        Text("Now paste it into your assistant.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Wax.crimson.base)
                .frame(width: 17, height: 17)
                .background(Circle().fill(Wax.crimson.base.opacity(0.12)))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Configured

    private func configured(_ service: ModelService) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                ProviderStamp(glyph: service.glyph, pressKey: stampKey, size: 40)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(service.model)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text("\(service.host) · \(service.format.displayName)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    status
                }
                Spacer(minLength: 12)
                Button(settings.checkState == .checking ? "Checking…" : "Check") {
                    Task { await settings.check() }
                }
                .disabled(settings.checkState == .checking || !settings.hasKey)
                .help("Send a tiny real request to make sure it answers")
            }

            if case .failed(let message) = settings.checkState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 58)
            }

            Divider()

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Change the setup")
                    Text("Hand the prompt to your AI assistant.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                copyButton
            }
        }
    }

    private var copyButton: some View {
        Button(action: copyPrompt) {
            Label(copied ? "Copied" : "Copy Setup Prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .help("Copies instructions for Claude Code, Codex or another assistant. It never asks you to paste the key into the chat.")
    }

    private var status: some View {
        HStack(spacing: 5) {
            if settings.checkState == .checking {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(statusColor).frame(width: 6, height: 6)
            }
            Text(statusText)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(statusColor == .secondary ? Color.secondary : statusColor)
        .padding(.top, 1)
    }

    private var statusText: String {
        guard settings.hasKey else { return "No API key" }
        switch settings.checkState {
        case .unchecked: return "Not checked yet"
        case .checking: return "Checking…"
        case .passed: return "Ready"
        case .failed: return "Failed"
        }
    }

    private var statusColor: Color {
        guard settings.hasKey else { return .orange }
        switch settings.checkState {
        case .unchecked, .checking: return .secondary
        case .passed: return .green
        case .failed: return .red
        }
    }

    /// Press the seal again whenever the service changes.
    private var stampKey: Int {
        settings.service?.summary.hashValue ?? 0
    }

    private func copyPrompt() {
        let executable = Bundle.main.executablePath ?? "/Applications/\(AppInfo.name).app/Contents/MacOS/\(AppInfo.name)"
        let prompt = SetupGuide.prompt(appName: AppInfo.name, executable: executable, current: settings.service)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }
}
