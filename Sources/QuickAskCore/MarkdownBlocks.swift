import Foundation

/// Splits Markdown into prose and fenced code blocks so the UI can render prose with
/// `AttributedString(markdown:)` (inline syntax) and code in a monospaced box.
/// Tolerates an unterminated fence, which is the normal state mid-stream.
public enum MarkdownBlock: Equatable, Sendable {
    case prose(String)
    case code(language: String?, code: String)
}

public enum MarkdownBlocks {
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var prose: [String] = []
        var code: [String] = []
        var fence: String?
        var language: String?

        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.isEmpty { blocks.append(.prose(text)) }
            prose.removeAll()
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open), trimmed.drop(while: { $0 == open.first }).isEmpty {
                    blocks.append(.code(language: language, code: code.joined(separator: "\n")))
                    code.removeAll()
                    fence = nil
                    language = nil
                } else {
                    code.append(line)
                }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushProse()
                let marker = trimmed.first!
                let run = trimmed.prefix { $0 == marker }
                fence = String(run)
                let info = trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespaces)
                language = info.isEmpty ? nil : String(info.split(separator: " ").first ?? "")
            } else {
                prose.append(proseLine(line))
            }
        }

        if fence != nil {
            blocks.append(.code(language: language, code: code.joined(separator: "\n")))
        }
        flushProse()
        return blocks
    }

    /// Rewrites block-level syntax that inline-only Markdown parsing would show literally:
    /// headings become bold, list bullets become "•", horizontal rules become a line.
    static func proseLine(_ line: String) -> String {
        let indent = line.prefix { $0 == " " }
        let body = line.dropFirst(indent.count)

        let hashes = body.prefix { $0 == "#" }
        if (1...6).contains(hashes.count), body.dropFirst(hashes.count).first == " " {
            let title = body.dropFirst(hashes.count + 1).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? "" : "**\(title)**"
        }
        if body == "---" || body == "***" || body == "___" {
            return "──────────"
        }
        for bullet in ["- ", "* ", "+ "] where body.hasPrefix(bullet) {
            return String(indent) + "• " + String(body.dropFirst(2))
        }
        return line
    }
}
