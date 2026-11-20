import HowlerCore
import SwiftUI

struct DirectServiceEditor: View {
    let settings: AppSettings
    let onClose: () -> Void
    let copySetupPrompt: () -> Void
    let copied: Bool
    @State private var current: ModelService?
    @State private var revision: String
    @State private var hasSavedKey: Bool
    @State private var provider: Provider?
    @State private var format: WireFormat
    @State private var baseURL: String
    @State private var model: String
    @State private var key = ""
    @State private var saving = false
    @State private var error: String?

    @MainActor
    init(settings: AppSettings, onClose: @escaping () -> Void, copySetupPrompt: @escaping () -> Void, copied: Bool) {
        self.settings = settings
        self.onClose = onClose
        self.copySetupPrompt = copySetupPrompt
        self.copied = copied
        let current = settings.service.flatMap { $0.usesMagpie ? nil : $0 }
        _current = State(initialValue: current)
        _revision = State(initialValue: settings.serviceRevision)
        _hasSavedKey = State(initialValue: settings.hasKey)
        let initial = current ?? Provider.openAI.service()
        let preset = initial.knownProvider.flatMap {
            $0.baseURL == initial.baseURL && $0.wireFormat == initial.format ? $0 : nil
        }
        _provider = State(initialValue: preset)
        _format = State(initialValue: initial.format)
        _baseURL = State(initialValue: initial.baseURL.absoluteString)
        _model = State(initialValue: initial.model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 8) {
                field("Provider") {
                    Picker("Provider", selection: $provider) {
                        ForEach(Provider.allCases) { Text($0.displayName).tag(Optional($0)) }
                        Text("Custom").tag(nil as Provider?)
                    }
                    .labelsHidden()
                    .accessibilityLabel("Provider")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if provider == nil {
                    field("Request format") {
                        Picker("Request format", selection: $format) {
                            ForEach(WireFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Request format")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    field("Base URL") {
                        TextField("Base URL", text: $baseURL, prompt: Text("https://example.com/v1"))
                            .labelsHidden().accessibilityLabel("Base URL")
                    }
                }
                field("Model") { TextField("Model", text: $model).labelsHidden().accessibilityLabel("Model") }
                field("API key") {
                    SecureField("API key", text: $key, prompt: Text(canKeepKey ? "Saved · leave blank to keep" : "Paste your API key"))
                        .labelsHidden().accessibilityLabel("API key")
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(saving)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(copied ? "Copied" : "Copy Setup Prompt", action: copySetupPrompt)
                    .buttonStyle(.link)
                    .font(.caption)
                    .disabled(saving)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                if current != nil { Button("Cancel", action: onClose).disabled(saving) }
                Button("Save & Check", action: save)
                    .disabled(saving || (key.isEmpty && !canKeepKey) || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Save the key to macOS Keychain and send a short test request")
            }
        }
        .onChange(of: provider) { _, preset in
            guard let preset else { return }
            format = preset.wireFormat
            baseURL = preset.baseURL.absoluteString
            model = preset.defaultModel
        }
        .onDisappear { key = "" }
    }

    private var canKeepKey: Bool {
        hasSavedKey && current?.format == format && current?.baseURL.absoluteString == baseURL
    }

    private func field<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(name)
            Spacer(minLength: 12)
            content().frame(width: 245)
        }
    }

    private func save() {
        do {
            let candidate = try ServiceConfig.apply([
                "format=\(format.rawValue)", "base-url=\(baseURL)", "model=\(model)",
            ], to: nil)
            var service = candidate
            if let current, current.baseURL == candidate.baseURL, current.format == candidate.format {
                service = try ServiceConfig.apply(["model=\(model)"], to: current)
            }
            let secret = key
            key = ""
            saving = true
            error = nil
            Task {
                defer { saving = false }
                do {
                    try await settings.saveDirectService(service, key: secret, for: revision)
                    onClose()
                    await settings.check(for: service)
                } catch {
                    self.error = APIKeyEditor.saveErrorMessage(for: error)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
