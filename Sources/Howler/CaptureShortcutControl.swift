import SwiftUI

/// A small physical breaker sits beside the shortcut it powers.
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
            .toggleStyle(CaptureBreakerStyle())
        }
    }
}

private struct CaptureBreakerStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.16)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                    }
                    .frame(width: 24, height: 32)
                    .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                Capsule()
                    .fill(.black.opacity(0.4))
                    .frame(width: 5, height: 21)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.77, green: 0.63, blue: 0.39))
                        .frame(width: 10, height: 2)
                        .offset(y: side * 11)
                }
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.82), Color(white: 0.50)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 3, height: 12)
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [
                        Color(red: 0.72, green: 0.25, blue: 0.20),
                        Color(red: 0.45, green: 0.12, blue: 0.10)
                    ], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        Capsule().fill(.white.opacity(0.28))
                            .frame(width: 10, height: 1).offset(y: -1)
                    }
                    .frame(width: 17, height: 7)
                    .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                    .offset(y: configuration.isOn ? -6 : 6)
            }
            .frame(width: 32, height: 36)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .help(configuration.isOn ? "Turn off Capture and Explain" : "Turn on Capture and Explain")
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
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
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                ForEach(0..<5) { index in
                    Ellipse()
                        .fill(Color(white: colorScheme == .dark ? 0.22 : 0.55).opacity(0.44))
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
