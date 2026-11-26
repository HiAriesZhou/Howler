import AppKit
import HowlerCore
import SwiftUI

struct ModelSettings: View {
    @ObservedObject var settings: AppSettings

    @State private var copied = false
    @State private var showsServiceEditor = false
    @State private var models: [Magpie.Model] = []
    @State private var port: UInt16 = 3425
    @State private var refresh = UUID()
    @State private var discoveryStatus = "Looking for models on this machine…"
    @State private var discovering = false
    @State private var choosingMagpie = false
    @State private var choosingAPIKey = false
    @State private var selectionError: String?

    private var activeMagpie: MagpieSelection? {
        settings.service?.usesMagpie == true ? settings.service?.magpie : nil
    }

    private var showsMagpie: Bool { !choosingAPIKey && (choosingMagpie || activeMagpie != nil) }
    private var canChooseSource: Bool { !models.isEmpty || activeMagpie != nil }
    private var busy: Bool { settings.isSavingAPIKey || settings.checkState == .checking }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Model Source").font(.headline)
                Spacer()
                if canChooseSource {
                    Picker("Model Source", selection: Binding(get: { showsMagpie }, set: chooseSource)) {
                        Text("Subscription").tag(true)
                        Text("API Key").tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(busy)
                }
            }
            if showsMagpie {
                magpieSettings
            } else {
                apiKeySettings
            }
            if let selectionError {
                Text(selectionError).font(.caption).foregroundStyle(.red)
            } else if !choosingMagpie, case .failed(let message) = settings.checkState {
                Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled).lineLimit(4)
            }
        }
        .onAppear { settings.reload() }
        .onChange(of: settings.pendingDirectService) { _, _ in showsServiceEditor = false }
        .task(id: refresh) { await discoverModels() }
    }

    private var magpieSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Use models you’ve already set up on this machine.")
                .font(.callout).foregroundStyle(.secondary)
            if !models.isEmpty || activeMagpie != nil {
                HStack(spacing: 8) {
                    Text("Model")
                        .fixedSize()
                    if models.isEmpty {
                        Text(activeMagpie?.model ?? "").lineLimit(1).truncationMode(.middle)
                    } else {
                        Menu {
                            ForEach(models) { model in
                                Button {
                                    select(MagpieSelection(port: port, model: model.id))
                                } label: {
                                    let name = model.id + (model.modalities?.input?.contains("image") == true ? " · Images" : "")
                                    if activeMagpie?.model == model.id { Label(name, systemImage: "checkmark") }
                                    else { Text(name) }
                                }
                            }
                        } label: {
                            Text(activeMagpie?.model ?? "Choose a model").lineLimit(1).truncationMode(.middle)
                        }
                        .accessibilityLabel("Existing model")
                        .frame(maxWidth: 250)
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(busy)
                    }
                    if activeMagpie != nil, !models.isEmpty { status }
                    Spacer(minLength: 8)
                    if activeMagpie != nil, !models.isEmpty { checkButton }
                }
            }
            if models.isEmpty {
                HStack(spacing: 8) {
                    Text(discoveryStatus).font(.caption).foregroundStyle(.secondary)
                    if !discovering {
                        Button("Retry") { refresh = UUID() }.controlSize(.small)
                    }
                }
            } else if activeMagpie == nil, settings.isConfigured {
                Text("Your API key stays active until you choose a model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var apiKeySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsServiceEditor {
                DirectServiceEditor(settings: settings, onClose: {
                    showsServiceEditor = false
                },
                                    copySetupPrompt: copySetupPrompt, copied: copied)
            } else if let service = settings.service, !service.usesMagpie {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(service.model).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            status
                        }
                        Text(service.host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button("Edit") { showsServiceEditor = true }
                        .accessibilityLabel("Edit API configuration")
                        .disabled(busy)
                    if settings.hasKey { checkButton }
                }
            } else if activeMagpie != nil, let pending = settings.pendingDirectService ?? settings.savedDirectService {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pending.model).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                        Text("Subscription stays active until this model passes its check.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Edit") { showsServiceEditor = true }
                        .accessibilityLabel("Edit API configuration")
                        .disabled(busy)
                }
            } else {
                Text("Copy the prompt and paste it into your AI assistant.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(copied ? "Copied" : "Copy Setup Prompt", action: copySetupPrompt)
                        .buttonStyle(.borderedProminent)
                    Text("/")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Button("Configure Manually") { showsServiceEditor = true }
                }
            }
        }
    }

    private var checkButton: some View {
        Button("Check") {
            Task { await settings.check() }
        }
        .disabled(busy)
        .help("Send a short request to test this model")
    }

    private var status: some View {
        let message: String = switch settings.checkState {
        case .unchecked: settings.isConfigured ? "Not checked yet" : "No API key"
        case .checking: "Checking…"
        case .passed: "Ready"
        case .failed: "Check failed"
        }
        return Label(message, systemImage: settings.checkState == .unchecked ? "circle" : "circle.fill")
            .font(.caption)
            .foregroundStyle(statusColor)
            .fixedSize()
    }

    private var statusColor: Color {
        switch settings.checkState {
        case .unchecked, .checking: .secondary
        case .passed: .green
        case .failed: .red
        }
    }

    private func chooseSource(_ useMagpie: Bool) {
        selectionError = nil
        showsServiceEditor = false
        if useMagpie {
            choosingAPIKey = false
            choosingMagpie = activeMagpie == nil
            if choosingMagpie, let last = settings.lastMagpieSelection, models.contains(where: { $0.id == last.model }) {
                select(MagpieSelection(port: port, model: last.model))
            }
        } else {
            choosingMagpie = false
            choosingAPIKey = activeMagpie != nil
        }
    }

    private func select(_ selection: MagpieSelection?) {
        do {
            try settings.selectMagpie(selection)
            choosingMagpie = false
            selectionError = nil
        } catch {
            selectionError = error.localizedDescription
        }
    }

    private func discoverModels() async {
        discovering = true
        discoveryStatus = "Looking for models on this machine…"
        defer { if !Task.isCancelled { discovering = false } }
        struct PortSetting: Decodable { let port: UInt16 }
        let config = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        let file = config.appendingPathComponent("magpie/settings.json")
        let detected = (try? JSONDecoder().decode(PortSetting.self, from: Data(contentsOf: file)).port) ?? 3425
        do {
            let catalog = try await Magpie.models(port: detected)
            try Task.checkCancellation()
            port = detected
            models = catalog
            discoveryStatus = "No configured models are available."
            if choosingMagpie, !busy, let last = settings.lastMagpieSelection,
               catalog.contains(where: { $0.id == last.model }) {
                select(MagpieSelection(port: detected, model: last.model))
            }
        } catch {
            guard !Task.isCancelled else { return }
            models = []
            choosingMagpie = false
            discoveryStatus = "Your saved connection is unavailable."
        }
    }

    private func copySetupPrompt() {
        let executable = Bundle.main.executablePath ?? "/Applications/\(AppInfo.name).app/Contents/MacOS/\(AppInfo.name)"
        let current = settings.pendingDirectService ?? settings.savedDirectService
        let prompt = SetupGuide.prompt(appName: AppInfo.name, executable: executable, current: current)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copied = false }
    }
}
