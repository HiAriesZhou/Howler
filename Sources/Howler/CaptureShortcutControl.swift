import SwiftUI

/// The native switch shares the recorder row; a faint haze marks its disabled state.
struct CaptureShortcutControl: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            HotKeyRecorder(settings: settings, screenshot: true)
                .disabled(!settings.captureAndExplainEnabled)
                .overlay {
                    if !settings.captureAndExplainEnabled {
                        ShortcutCloud()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            Toggle("Capture and Explain", isOn: Binding(
                get: { settings.captureAndExplainEnabled },
                set: { settings.setCaptureAndExplainEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help(settings.captureAndExplainEnabled ? "Turn off Capture and Explain" : "Turn on Capture and Explain")
        }
    }
}

/// Static haze marks an unpowered shortcut without creating a moving distraction.
private struct ShortcutCloud: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.12))
                ForEach(0..<5) { index in
                    Ellipse()
                        .fill(Color(white: colorScheme == .dark ? 0.45 : 0.55).opacity(0.12))
                        .frame(width: geometry.size.width * 0.55, height: geometry.size.height * 0.9)
                        .blur(radius: 3)
                        .position(x: geometry.size.width * (0.12 + Double(index) * 0.19),
                                  y: geometry.size.height * (index.isMultiple(of: 2) ? 0.35 : 0.7))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
