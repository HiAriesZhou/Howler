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
        1. Run `\(appName) config show` first. Preserve an existing working setup. Ask which service and model I want only when missing or when I want a change.
        2. Run `\(appName) config schema` to learn every field, and check the service's official docs for the endpoint, request format and any parameters it needs. \(appName) is for quick everyday questions, so the answer should start fast: if the model can turn thinking off or down, set the lowest level in `body`, unless I ask for deeper reasoning.
        3. Apply only the required non-secret changes together with `\(appName) config set field=value …`. Use the installed executable above for every command.
        4. Never ask me to send you the API key, read it from my clipboard, or print or save it. If a key is needed, direct me to \(appName) Settings > General > API Key > Add Key (or Replace Key), where I paste it and choose Save & Check. Wait for me to finish. Reuse an existing working key.
        5. Read `\(appName) config show` again. Key record presence is not proof of readable credentials or a working connection; only a passed check for the current setup confirms success. Save & Check already sends one test request, so do not duplicate a successful check.
        6. On Keychain, authorization or permission errors, stop immediately and explain the error and the next user action in the app. Never repeatedly import keys, reset the configuration, delete Keychain items or weaken permissions to work around a failure.
        7. For a network, HTTP or model error, use the existing diagnostic first. Make at most one cause-based correction and one retry with `\(appName) check --verbose`; then stop and report any remaining blocker. Finish with `\(appName) config show`, distinguishing saved configuration from a passed connection.

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

        API KEY (prefer Settings > General > API Key > Save & Check)
          Enter the key directly in the app. It is stored in macOS Keychain and never shown.
          For deliberate terminal use only:
          pbpaste | \(appName) config set api-key --stdin
          \(appName) config set api-key --env NAME
          \(appName) config set api-key --file PATH
          The key is sent as Authorization: Bearer (chat-completions), x-api-key (anthropic-messages)
          or x-goog-api-key (gemini-generate-content).
          On Keychain access errors, stop and retry in the app. Do not reset or delete the old key.

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
