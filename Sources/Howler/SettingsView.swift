import AppKit
import HowlerCore
import SwiftUI

/// The tabs of the Settings window, in toolbar order.
enum SettingsTab: String, CaseIterable {
    case general
    case prompt

    var title: String {
        switch self {
        case .general: return "General"
        case .prompt: return "Prompt"
        }
    }

    /// SF Symbols; the scroll is what the model is handed first.
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .prompt: return "scroll"
        }
    }

    @MainActor
    func pane(_ settings: AppSettings, updater: Updater) -> AnyView {
        switch self {
        case .general: return AnyView(GeneralPane(settings: settings, updater: updater))
        case .prompt: return AnyView(PromptPane(settings: settings))
        }
    }
}

/// One tab's page. General sits at its natural height, which sets the window's; a page that
/// `fills` stretches to that height instead, so switching tabs never resizes the window.
private struct SettingsPage<Content: View>: View {
    var fills = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        let page = VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(20)
        .frame(width: SettingsWindowController.width)
        if fills {
            page.frame(maxHeight: .infinity, alignment: .top)
        } else {
            page.fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The model that answers, the shortcut, launching at login, updates, and where what you
/// send goes.
struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: Updater

    var body: some View {
        SettingsPage {
            SettingsSection(nil) {
                ModelSettings(settings: settings)
            }
            SettingsSection(nil) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsRow("Keyboard shortcut", detail: "Opens \(AppInfo.name) from any app.") {
                        HotKeyRecorder(settings: settings)
                    }
                    if !settings.hotKeyRegistered { // kept while recording, so leaving the tab never changes the height
                        Text("\(settings.hotKey.display) is already used by another app. Choose a different shortcut, or open \(AppInfo.name) from the menu bar.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    SettingsRow("Launch at login", detail: nil) {
                        Toggle("Launch at login", isOn: Binding(
                            get: { settings.launchAtLogin == .on || settings.launchAtLogin == .needsApproval },
                            set: { settings.setLaunchAtLogin($0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    loginItemNote
                    if updater.isEnabled {
                        Divider()
                        UpdateRow(updater: updater)
                    }
                }
            }
            Text("Conversations are never saved. Text you paste and screen regions you capture are sent only to the model service above, with your next question — leave out passwords and other secrets.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var loginItemNote: some View {
        switch settings.launchAtLogin {
        case .needsApproval:
            HStack {
                Text("Allow \(AppInfo.name) in System Settings › General › Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Login Items") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        case .failed(let message):
            Text("Couldn't change the login item: \(message)")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case .on, .off:
            EmptyView()
        }
    }
}

/// What the model is told before the conversation; the editor takes the page's spare height.
struct PromptPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPage(fills: true) {
            SettingsSection("System Prompt") {
                SystemPromptSettings(settings: settings)
            } accessory: {
                SystemPromptReset(settings: settings)
            }
        }
    }
}

/// A group on a quiet card, like System Settings. A page whose window title already names
/// it needs no title; an accessory (e.g. Reset) follows the title.
private struct SettingsSection<Content: View, Accessory: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let accessory: () -> Accessory

    init(_ title: String?, @ViewBuilder content: @escaping () -> Content, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.content = content
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    accessory()
                }
            }
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
                )
        }
    }
}

extension SettingsSection where Accessory == EmptyView {
    init(_ title: String?, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, content: content, accessory: { EmptyView() })
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let control: () -> Control

    init(_ title: String, detail: String?, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control()
        }
    }
}

/// Automatic update checks, a manual check, and the gentle reminder when one is waiting.
private struct UpdateRow: View {
    @ObservedObject var updater: Updater

    var body: some View {
        SettingsRow("Check for updates automatically", detail: detail) {
            HStack(spacing: 10) {
                Group {
                    if updater.available != nil {
                        Button("Update…", action: updater.checkForUpdates)
                            .buttonStyle(.borderedProminent)
                            .tint(Wax.crimson.base)
                    } else {
                        Button("Check Now", action: updater.checkForUpdates)
                    }
                }
                .controlSize(.small)
                .disabled(!updater.canCheck) // a check or an install is already under way
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.checksAutomatically },
                    set: { updater.setChecksAutomatically($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
        }
    }

    private var detail: String {
        if let version = updater.available { return "\(AppInfo.name) \(version) is available." }
        let schedule = updater.checksAutomatically ? "asks GitHub once a day" : "automatic checks are off"
        return "\(AppInfo.name) \(AppInfo.version) · \(schedule)."
    }
}
