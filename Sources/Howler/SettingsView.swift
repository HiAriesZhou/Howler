import HowlerCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    @State private var selection: Provider?
    @State private var keyInput = ""
    @State private var modelInput = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Provider").font(.headline)

            List(Provider.allCases, selection: $selection) { provider in
                ProviderRow(
                    provider: provider,
                    isActive: settings.activeProvider == provider,
                    hasKey: settings.hasKey(for: provider)
                )
                .tag(provider)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .frame(height: 6 * 34 + 8)

            if let provider = selection {
                details(for: provider)
            } else {
                Text("Select a provider to configure it.")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            Divider()
            Text("Hotkey \(HotKey.defaultDisplay) toggles the chat panel. Conversations are never saved; only the provider, model and API key (in Keychain) are stored.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 480, height: 560)
        .onAppear {
            selection = settings.activeProvider
            loadFields()
        }
        .onChange(of: selection) { _, _ in loadFields() }
    }

    @ViewBuilder
    private func details(for provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("API key").frame(width: 60, alignment: .leading)
                SecureField(
                    "API key",
                    text: $keyInput,
                    prompt: Text(settings.hasKey(for: provider)
                        ? "Saved in Keychain — leave blank to keep"
                        : "Paste your \(provider.displayName) API key")
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Model").frame(width: 60, alignment: .leading)
                TextField("Model", text: $modelInput, prompt: Text(provider.defaultModel))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                Button(isSaving ? "Testing…" : "Save") {
                    save(provider)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || (keyInput.isEmpty && !settings.hasKey(for: provider)))

                if settings.hasKey(for: provider) {
                    Button("Remove Key", role: .destructive) {
                        settings.removeKey(for: provider)
                        keyInput = ""
                    }
                    .disabled(isSaving)
                }
                Spacer()
                Link("Get a key ↗", destination: provider.keyURL)
                    .font(.callout)
            }
            StatusLine(provider: provider, status: settings.connectionStatus(for: provider))
        }
    }

    private func loadFields() {
        keyInput = ""
        modelInput = selection.map { settings.storedModel(for: $0) } ?? ""
    }

    private func save(_ provider: Provider) {
        isSaving = true
        let key = keyInput
        let model = modelInput
        Task {
            await settings.save(provider: provider, newKey: key, model: model)
            keyInput = ""
            isSaving = false
        }
    }
}

private struct ProviderRow: View {
    let provider: Provider
    let isActive: Bool
    let hasKey: Bool

    var body: some View {
        HStack(spacing: 10) {
            ProviderGlyphView(provider: provider)
            Text(provider.displayName)
            Spacer()
            if hasKey {
                Image(systemName: "key.fill")
                    .foregroundStyle(.secondary)
                    .help("API key saved in Keychain")
            }
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .help("Active provider")
            }
        }
        .padding(.vertical, 3)
    }
}

private struct StatusLine: View {
    let provider: Provider
    let status: AppSettings.ConnectionStatus

    var body: some View {
        switch status {
        case .untested:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("\(provider.displayName) · Testing…")
            }
        case .connected:
            Text("\(provider.displayName) · ✓ Connected")
                .foregroundStyle(.green)
        case .failed(let message):
            Text("\(provider.displayName) · ✗ \(message)")
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
        }
    }
}
