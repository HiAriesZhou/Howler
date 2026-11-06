import SwiftUI
import HowlerCore

/// A new secret is held only while this editor's save operation is active.
/// The existing Keychain value is never loaded into the field.
struct APIKeyEditor: View {
    @ObservedObject var settings: AppSettings
    let service: ModelService
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var saving = false
    @State private var error: String?
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key").font(.title3.weight(.semibold))
                Text(service.host)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            SecureField("Paste your API key", text: $draft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("New API key")
                .focused($keyFocused)
                .disabled(saving)
                .onSubmit(save)
            Text("Stored in macOS Keychain. Save & Check sends one test request.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Could not save API key: \(error)")
            }
            HStack {
                if saving {
                    ProgressView().controlSize(.small)
                    Text("Saving…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { draft = ""; dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(saving)
                Button("Save & Check", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled(saving)
        .onAppear { keyFocused = true }
        .onDisappear { draft = "" }
    }

    private func save() {
        guard !saving, !draft.isEmpty else { return }
        let value = draft
        draft = ""
        saving = true
        error = nil
        Task {
            do {
                try await settings.saveAPIKey(value, for: service)
                saving = false
                dismiss()
                await settings.check(for: service)
            } catch {
                self.error = error.localizedDescription
                saving = false
                keyFocused = true
            }
        }
    }
}
