import HowlerCore
import SwiftUI

/// The system prompt section of Settings: the date line Howler adds, then the instructions,
/// which start as the suggestion and can be edited or reset. Empty instructions turn the
/// whole prompt off, for models that reject one.
struct SystemPromptSettings: View {
    @ObservedObject var settings: AppSettings

    private var isOff: Bool {
        settings.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var footnote: String {
        if settings.instructionsAreSuggested { return "Suggested for the letter: short answers, and no tables, which it can't show." }
        if isOff { return "Type instructions or press Reset to send the prompt again." }
        return "Edited. Leave it empty to turn the system prompt off, for models that reject one."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sent before every conversation")
                    Text("The date goes first, in UTC, never your time zone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button {
                    settings.resetInstructions()
                } label: {
                    Label("Reset", systemImage: "arrow.uturn.backward")
                }
                .disabled(settings.instructionsAreSuggested)
                .help("Restore the suggested prompt")
            }

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if isOff {
                        Label("Off: nothing is sent, not even the date.", systemImage: "minus.circle")
                    } else {
                        Label(SystemPrompt.dateLine(), systemImage: "lock")
                            .help("Added by \(AppInfo.name); not editable")
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
                TextEditor(text: Binding(
                    get: { settings.instructions },
                    set: { settings.setInstructions($0) }
                ))
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 5)
                .padding(.vertical, 6)
                .frame(height: 168)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
