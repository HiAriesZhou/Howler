import QuickAskCore
import SwiftUI

/// Monochrome provider mark: an SF Symbol or a letter in a rounded square.
/// Deliberately not the providers' trademarked logos.
struct ProviderGlyphView: View {
    let provider: Provider
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .strokeBorder(.secondary, lineWidth: 1)
            switch provider.glyph {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.5, weight: .semibold))
            case .letters(let letters):
                Text(letters)
                    .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.primary)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
