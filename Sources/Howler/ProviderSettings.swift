import HowlerCore
import SwiftUI

/// Choosing a provider in two steps. First every provider is a capsule (mark and name);
/// picking one sends the others away and its capsule becomes the header of a small form:
/// API key, model, Save & Test, and a status badge. The back arrow returns to the list.
struct ProviderSettings: View {
    @ObservedObject var settings: AppSettings

    @State private var selected: Provider? = Self.initialSelection
    @Namespace private var space

    var body: some View {
        Group {
            if let provider = selected {
                ProviderDetail(settings: settings, provider: provider, space: space) {
                    withAnimation(Self.morph) { selected = nil }
                }
            } else {
                ProviderChips(settings: settings, space: space) { provider in
                    withAnimation(Self.morph) { selected = provider }
                }
            }
        }
    }

    private static let morph = Animation.spring(response: 0.42, dampingFraction: 0.86)

    private static var initialSelection: Provider? {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["HOWLER_DEMO_PROVIDER"] { return Provider(rawValue: raw) }
        #endif
        return nil
    }
}

// MARK: Step 1: capsules

private struct ProviderChips: View {
    @ObservedObject var settings: AppSettings
    let space: Namespace.ID
    let select: (Provider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8) {
                ForEach(Provider.allCases) { provider in
                    chip(provider)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    private var hint: String {
        guard let active = settings.activeProvider, settings.hasKey(for: active) else {
            return "Choose the AI that answers your letters."
        }
        return "In use: \(active.displayName) · \(settings.model(for: active))"
    }

    private func chip(_ provider: Provider) -> some View {
        let isActive = settings.activeProvider == provider && settings.hasKey(for: provider)
        return Button {
            select(provider)
        } label: {
            HStack(spacing: 7) {
                ProviderGlyphView(provider: provider, size: 18)
                    .matchedGeometryEffect(id: "glyph-\(provider.rawValue)", in: space)
                Text(provider.displayName)
                    .matchedGeometryEffect(id: "name-\(provider.rawValue)", in: space)
                if settings.hasKey(for: provider) {
                    Circle()
                        .fill(isActive ? Color.green : Color.secondary.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .help(isActive ? "In use" : "API key saved")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule().strokeBorder(isActive ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Step 2: the chosen provider

private struct ProviderDetail: View {
    @ObservedObject var settings: AppSettings
    let provider: Provider
    let space: Namespace.ID
    let back: () -> Void

    @State private var keyInput = ""
    @State private var modelInput = ""
    @State private var isSaving = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("All providers")
                .keyboardShortcut(.cancelAction)

                ProviderGlyphView(provider: provider, size: 28)
                    .matchedGeometryEffect(id: "glyph-\(provider.rawValue)", in: space)
                Text(provider.displayName)
                    .font(.title3.weight(.semibold))
                    .matchedGeometryEffect(id: "name-\(provider.rawValue)", in: space)
                StatusBadge(status: badgeStatus)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("API key").foregroundStyle(.secondary)
                        SecureField(
                            "API key",
                            text: $keyInput,
                            prompt: Text(settings.hasKey(for: provider)
                                ? "Saved in Keychain — leave blank to keep"
                                : "Paste your \(provider.displayName) API key")
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .focused($keyFocused)
                    }
                    GridRow {
                        Text("Model").foregroundStyle(.secondary)
                        TextField("Model", text: $modelInput, prompt: Text("Default: \(provider.defaultModel)"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .onSubmit(save)

                HStack(spacing: 12) {
                    Link("Get an API key ↗", destination: provider.keyURL)
                        .font(.callout)
                    Spacer()
                    if settings.hasKey(for: provider) {
                        Button("Remove Key", role: .destructive) {
                            settings.removeKey(for: provider)
                            keyInput = ""
                        }
                        .buttonStyle(.borderless)
                        .disabled(isSaving)
                    }
                    Button(isSaving ? "Testing…" : "Save & Test", action: save)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSaving || (keyInput.isEmpty && !settings.hasKey(for: provider)))
                }

                if case .failed(let message) = settings.connectionStatus(for: provider) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .onAppear {
            keyInput = ""
            modelInput = settings.storedModel(for: provider)
            if !settings.hasKey(for: provider) {
                DispatchQueue.main.async { keyFocused = true }
            }
        }
    }

    private var badgeStatus: StatusBadge.Status {
        switch settings.connectionStatus(for: provider) {
        case .testing: return .testing
        case .connected: return .connected
        case .failed: return .failed
        case .untested: return settings.hasKey(for: provider) ? .saved : .none
        }
    }

    private func save() {
        guard !isSaving, !keyInput.isEmpty || settings.hasKey(for: provider) else { return }
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

/// The small mark next to the provider's name.
private struct StatusBadge: View {
    enum Status {
        case none, saved, testing, connected, failed
    }

    let status: Status

    var body: some View {
        switch status {
        case .none:
            EmptyView()
        case .testing:
            badge(color: .secondary) {
                ProgressView().controlSize(.mini)
                Text("Testing")
            }
        case .saved:
            badge(color: .secondary) { dot(.secondary); Text("Key saved") }
        case .connected:
            badge(color: .green) { dot(.green); Text("Connected") }
        case .failed:
            badge(color: .red) { dot(.red); Text("Failed") }
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 6, height: 6)
    }

    private func badge<Content: View>(color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 5, content: content)
            .font(.caption.weight(.medium))
            .foregroundStyle(color == .secondary ? Color.secondary : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .transition(.opacity)
    }
}

/// Lays children out left to right, wrapping onto new lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
