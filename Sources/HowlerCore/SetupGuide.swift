import Foundation

/// Texts that hand the model setup to an AI assistant: the prompt copied from Settings and
/// the field reference printed by `config schema`.
public enum SetupGuide {
    /// The prompt behind "Copy Setup Prompt". `executable` is the app's command-line path.
    public static func prompt(appName: String, executable: String, current: ModelService?) -> String {
        let setup = current?.summary ?? "not set up yet"
        return """
        Help me set up the model service for \(appName), a macOS menu-bar app: I press a shortcut, write a quick question on a letter, and the answer is written beneath it.

        \(appName)'s command line: \(shellQuoted(executable))
        Current setup: \(setup)

        Please:
        1. Ask me which model service and model I want. If I haven't decided, recommend two or three and explain how they differ.
        2. Run `\(appName) config schema` to learn every field, and check the service's official docs for the endpoint, request format and any parameters it needs. \(appName) is for quick everyday questions, so the answer should start fast: if the model can turn thinking off or down, set the lowest level in `body`, unless I ask for deeper reasoning.
        3. Write everything at once with `\(appName) config set field=value …`.
        4. Never ask me to send you the API key, and never print it or write it to a file: ask me to copy the key first, then run `pbpaste | \(appName) config set api-key --stdin`. If the key is already in an environment variable or a file, use `--env` or `--file`.
        5. Run `\(appName) check`. If it fails, find the cause with `\(appName) check --verbose`, fix the setup, and repeat until it passes.
        6. Finish by showing me the result of `\(appName) config show`.

        If you can't run commands, write out each one for me; I'll paste them into Terminal and send you the output.
        """
    }

    /// The reference printed by `config schema`.
    public static func schema(appName: String) -> String {
        let presets = Provider.allCases
            .map { "             \($0.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0)) \($0.wireFormat.rawValue), \($0.baseURL.absoluteString), model \($0.defaultModel)" }
            .joined(separator: "\n")
        let formats = WireFormat.allCases
            .map { "             \($0.rawValue.padding(toLength: 24, withPad: " ", startingAt: 0)) \(formatDetail($0))" }
            .joined(separator: "\n")
        return """
        \(appName) talks to one model service. Set its fields with:
          \(appName) config set field=value [field=value …]
        Fields are applied in order, so preset=… followed by other fields refines the preset.

        FIELDS
          preset     Fill format, base-url and model from a known service; clears body and headers:
        \(presets)
          format     Request format:
        \(formats)
          base-url   Base of the API, without the endpoint path. https:// required; http:// only for localhost.
          model      Model name as the service spells it.
          body       JSON object merged into every request body at the top level, e.g. to turn
                     thinking off or set an output cap. Empty clears it. Fields written by \(appName)
                     (model, stream, messages; contents for Gemini) can't be set here.
                     Anthropic Messages sends max_tokens 64000 unless body sets it.
          headers    JSON object of extra HTTP headers (string values). Empty clears it.
                     Authorization, x-api-key and x-goog-api-key are not allowed: they carry the key.

        API KEY (stored in the macOS Keychain, never printed)
          pbpaste | \(appName) config set api-key --stdin
          \(appName) config set api-key --env NAME
          \(appName) config set api-key --file PATH
          The key is sent as Authorization: Bearer (chat-completions), x-api-key (anthropic-messages)
          or x-goog-api-key (gemini-generate-content).

        OTHER COMMANDS
          \(appName) config show        Current setup and whether it passed a check
          \(appName) config reset       Remove the setup and the API key
          \(appName) check [--verbose]  Send a tiny real request; --verbose shows the request and the error

        EXAMPLES
          \(appName) config set preset=deepseek model=deepseek-flash
          \(appName) config set format=chat-completions base-url=http://localhost:11434/v1 model=llama3.2
          \(appName) config set body='{"thinking": {"type": "disabled"}}'
        """
    }

    private static func formatDetail(_ format: WireFormat) -> String {
        switch format {
        case .openAICompatible: return "POST {base-url}/chat/completions (OpenAI and compatible APIs)"
        case .anthropic: return "POST {base-url}/messages (Anthropic Messages API)"
        case .gemini: return "POST {base-url}/models/{model}:streamGenerateContent (Google Gemini API)"
        }
    }

    /// Single-quotes a path for the shell when it needs it.
    static func shellQuoted(_ path: String) -> String {
        let safe = path.allSatisfy { $0.isLetter || $0.isNumber || "/._-+".contains($0) }
        return safe ? path : "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
