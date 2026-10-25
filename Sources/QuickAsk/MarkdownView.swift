import AppKit
import QuickAskCore
import SwiftUI

/// Renders a reply: prose via `AttributedString(markdown:)` (inline syntax, whitespace kept),
/// fenced code in a monospaced, horizontally scrollable box with a copy button.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlocks.parse(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let text):
                    Text(Self.attributed(text))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                }
            }
        }
        .textSelection(.enabled)
    }

    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
            }
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
