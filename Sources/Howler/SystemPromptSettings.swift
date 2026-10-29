import HowlerCore
import SwiftUI

/// The system prompt section of Settings: the date line Howler adds, then the instructions,
/// which start as the suggestion and can be edited. Empty instructions turn the whole prompt
/// off, for models that reject one. Reset sits in the section title (`SystemPromptReset`).
struct SystemPromptSettings: View {
    @ObservedObject var settings: AppSettings

    private var isOff: Bool {
        settings.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var footnote: String {
        if settings.instructionsAreSuggested { return "Suggested for the letter: short answers, and no tables, which it can't show. The date is today's in UTC, never your time zone." }
        if isOff { return "Type instructions or press Reset to send the prompt again." }
        return "Edited. Leave it empty to turn the system prompt off, for models that reject one."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if isOff {
                        Label("Off: nothing is sent, not even the date.", systemImage: "minus.circle")
                    } else {
                        // Ticks so an open window crosses UTC midnight with the right date.
                        TimelineView(.everyMinute) { context in
                            Label(SystemPrompt.dateLine(context.date), systemImage: "lock")
                        }
                        .help("Today's date in UTC, filled in on every request; not editable")
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
                .frame(minHeight: 96, maxHeight: .infinity)
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

/// Restores the suggested instructions; shown beside the section title.
struct SystemPromptReset: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Button {
            settings.resetInstructions()
        } label: {
            Label("Reset", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        // Borderless draws in gray either way; the accent color says it can be clicked.
        .foregroundStyle(settings.instructionsAreSuggested ? Color.secondary : Color.accentColor)
        .disabled(settings.instructionsAreSuggested)
        .help("Restore the suggested system prompt")
    }
}
