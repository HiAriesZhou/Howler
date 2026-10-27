import AppKit
import HowlerCore
import SwiftUI

/// Everything on one page: the model that answers, then the two general preferences.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Model") {
                ModelSettings(settings: settings)
            }

            SettingsSection("General") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsRow("Keyboard shortcut", detail: "Opens \(AppInfo.name) from any app.") {
                        HotKeyRecorder(settings: settings)
                    }
                    if !settings.hotKeyRegistered && !settings.isRecordingHotKey {
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
                }
            }

            Text("Conversations are never saved. Text you paste and screen regions you capture are sent only to the model service above, with your next question — leave out passwords and other secrets.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { settings.refreshLaunchAtLogin() }
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

/// A titled group on a quiet card, like System Settings.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
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
