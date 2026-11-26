import Foundation
import HowlerCore

/// The app's command line, for setting up the model service by hand or through an AI
/// assistant (Settings › Copy Setup Prompt). It shares `ServiceStore` with the app and never
/// prints the API key.
///
///     Howler config schema | show | stage field=value … | set field=value … | set api-key --stdin|--env NAME|--file PATH | reset
///     Howler check [--verbose]
enum CLI {
    private static let commands: Set<String> = ["config", "check", "help", "--help", "-h", "version", "--version"]

    /// Runs a command-line invocation and returns its exit status, or nil when the
    /// arguments are not a command and the app should launch as usual.
    static func run(_ arguments: [String], store makeStore: @autoclosure () -> ServiceStore = ServiceStore()) -> Int32? {
        let args = Array(arguments.dropFirst())
        guard let command = args.first, commands.contains(command) else { return nil }
        // Keep stdout and stderr in order when piped (an assistant reads both).
        setvbuf(stdout, nil, _IOLBF, 0)
        do {
            let operation = try parse(args)
            switch operation {
            case .help:
                print(usage)
                return 0
            case .version:
                print("\(AppInfo.name) \(AppInfo.version)")
                return 0
            case .schema:
                print(SetupGuide.schema(appName: name))
                return 0
            default:
                break
            }
            let store = makeStore()
            switch operation {
            case .reset:
                try store.reset()
                print("Removed the model service and its API key.")
            case .stage(let fields):
                let service = try ServiceConfig.apply(fields, to: store.pendingDirectService ?? store.directService)
                try store.stageDirectService(service)
                print("Prepared: \(service.summary)")
                print("Subscription stays active. Open Settings > General > API Key > Edit, then Save & Check.")
            case .set(let fields):
                // Validate against the direct configuration before migration can touch storage.
                _ = try ServiceConfig.apply(fields, to: store.directServiceForEditing)
                store.migrateLegacySetup()
                let service = try ServiceConfig.apply(fields, to: store.directService)
                try store.save(service)
                print("Saved: \(service.summary)")
                print(store.hasKey ? "Next: \(name) check" : "Next: open Settings > General, edit the model configuration, then Save & Check.")
            case .setKey(let key):
                guard store.service?.usesMagpie != true else { throw ConfigurationFailure.magpieKey }
                guard store.directServiceForEditing != nil else { throw ServiceConfigError.missing(["format", "base-url", "model"]) }
                store.migrateLegacySetup()
                try store.setAPIKey(key)
                print("API key saved in Keychain.")
                print("Next: \(name) check")
            case .show:
                store.migrateLegacySetup()
                show(store)
            case .check(let verbose):
                store.migrateLegacySetup()
                return check(verbose: verbose, store: store)
            case .help, .version, .schema:
                break
            }
            return 0
        } catch {
            printError(error.localizedDescription)
            return 1
        }
    }

    private static var name: String { AppInfo.name }

    private static var usage: String {
        """
        Usage:
          \(name) config schema                 Every field, with examples
          \(name) config show                   Current setup
          \(name) config set field=value …      Change the setup
          \(name) config stage field=value …    Prepare API key settings while a subscription stays active
          \(name) config set api-key --stdin    Save the API key (also --env NAME, --file PATH)
          \(name) config reset                  Remove the setup and the API key
          \(name) check [--verbose]             Send a tiny real request
        """
    }

    private struct UsageError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    // MARK: config

    private enum Operation {
        case help, version, schema, show, reset
        case set([String]), stage([String])
        case setKey(String)
        case check(Bool)
    }

    private static func parse(_ args: [String]) throws -> Operation {
        let tail = Array(args.dropFirst())
        switch args.first {
        case "help", "--help", "-h":
            guard tail.isEmpty else { throw UsageError(usage) }
            return .help
        case "version", "--version":
            guard tail.isEmpty else { throw UsageError(usage) }
            return .version
        case "check":
            guard tail.allSatisfy({ ["--verbose", "-v", "--help", "-h"].contains($0) }) else {
                throw UsageError(usage)
            }
            return tail.contains(where: isHelp) ? .help : .check(!tail.isEmpty)
        case "config":
            guard let action = tail.first else { return .show }
            let fields = Array(tail.dropFirst())
            if isHelp(action) {
                guard fields.isEmpty else { throw UsageError(usage) }
                return .help
            }
            switch action {
            case "schema", "show", "reset":
                guard fields.isEmpty || (fields.count == 1 && isHelp(fields[0])) else {
                    throw UsageError(usage)
                }
                if !fields.isEmpty { return .help }
                switch action {
                case "schema": return .schema
                case "show": return .show
                default: return .reset
                }
            case "set", "stage":
                guard !fields.isEmpty else { throw UsageError("Nothing to \(action). See: \(name) config schema") }
                if fields.count == 1 && isHelp(fields[0]) { return .help }
                if action == "set", fields.first == "api-key" {
                    if fields.count == 2 && isHelp(fields[1]) { return .help }
                    return .setKey(try ServiceStore.validatedAPIKey(readKey(Array(fields.dropFirst()))))
                }
                do {
                    _ = try ServiceConfig.apply(fields, to: nil)
                } catch ServiceConfigError.missing {
                }
                return action == "set" ? .set(fields) : .stage(fields)
            default:
                throw UsageError(usage)
            }
        default:
            throw UsageError(usage)
        }
    }

    private static func isHelp(_ argument: String) -> Bool {
        argument == "--help" || argument == "-h"
    }

    private static func show(_ store: ServiceStore) {
        guard let service = store.service else {
            print("No model service yet. See the fields with: \(name) config schema")
            return
        }
        let rows: [(String, String)] = [
            ("model", service.model),
            ("format", "\(service.format.rawValue) (\(service.format.displayName))"),
            ("base-url", service.baseURL.absoluteString),
            ("endpoint", service.endpointDescription),
            ("body", service.body.isEmpty ? "—" : JSONValue.compact(service.body)),
            ("headers", service.headers.isEmpty ? "—" : JSONValue.compact(service.headers.mapValues(JSONValue.string))),
            ("api-key", service.usesMagpie ? "managed by Magpie" : store.hasKey ? "record present; access not verified" : "no record detected"),
            ("prompt", promptSummary(store)),
            ("check", checkSummary(store.lastCheck)),
        ]
        for (label, value) in rows {
            print(label.padding(toLength: 10, withPad: " ", startingAt: 0) + value)
        }
        if service.usesMagpie, let pending = store.pendingDirectService {
            print("pending   \(pending.summary) (verify in Settings > General > API Key)")
        }
    }

    private static func promptSummary(_ store: ServiceStore) -> String {
        if store.instructionsAreSuggested { return "date (UTC) + suggested instructions; edit in Settings" }
        if store.systemPrompt == nil { return "off (instructions are empty); edit in Settings" }
        return "date (UTC) + your instructions; edit in Settings"
    }

    private static func checkSummary(_ record: ServiceStore.CheckRecord?) -> String {
        guard let record else { return "not checked since the last change" }
        let date = record.date.formatted(date: .abbreviated, time: .shortened)
        return record.passed ? "passed (\(date))" : "failed (\(date)): \(record.message ?? "unknown error")"
    }

    /// The key comes from a pipe, an environment variable or a file — never an argument,
    /// where it would end up in shell history and process listings.
    private static func readKey(_ args: [String]) throws -> String {
        let raw: String
        switch args.first {
        case "--stdin":
            guard args.count == 1 else { throw UsageError("Usage: \(name) config set api-key --stdin") }
            guard isatty(FileHandle.standardInput.fileDescriptor) == 0 else {
                throw UsageError("--stdin reads a pipe. Copy the key, then run: pbpaste | \(name) config set api-key --stdin")
            }
            raw = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        case "--env":
            guard args.count == 2 else { throw UsageError("Usage: \(name) config set api-key --env NAME") }
            guard let value = ProcessInfo.processInfo.environment[args[1]] else {
                throw UsageError("Environment variable \(args[1]) is not set.")
            }
            raw = value
        case "--file":
            guard args.count == 2 else { throw UsageError("Usage: \(name) config set api-key --file PATH") }
            let path = (args[1] as NSString).expandingTildeInPath
            guard let data = FileManager.default.contents(atPath: path) else {
                throw UsageError("Can't read \(args[1]).")
            }
            raw = String(decoding: data, as: UTF8.self)
        default:
            throw ServiceConfigError.apiKeyOnCommandLine
        }
        return raw
    }

    // MARK: check

    private static func check(verbose: Bool, store: ServiceStore) -> Int32 {
        let revision = store.revision
        guard let service = store.service else {
            printError("No model service yet. See: \(name) config schema")
            return 1
        }
        let key: String
        do {
            guard let saved = service.usesMagpie ? "" : try store.readAPIKey(for: service) else {
                throw ConfigurationFailure.missingKey
            }
            key = saved
        } catch {
            store.recordCheck(passed: false, message: error.localizedDescription, for: revision)
            printError(error.localizedDescription)
            printError("No model request was sent. Stop here; do not repeatedly import or reset the key.")
            return 1
        }
        guard store.revision == revision else {
            printError("The setup changed. Run check again for the current setup.")
            return 1
        }
        if verbose { describeRequest(service: service, apiKey: key, systemPrompt: store.systemPrompt, replyLanguage: store.resolvedReplyLanguage) }
        print("Checking \(service.summary) …")

        let result = wait {
            try await ConnectionTester.test(
                client: ChatClient(), service: service, apiKey: key, appName: name, systemPrompt: store.systemPrompt, replyLanguage: store.resolvedReplyLanguage
            )
        }
        switch result {
        case .success:
            guard store.recordCheck(passed: true, message: nil, for: revision) else {
                printError("The setup changed during the check. Run check again.")
                return 1
            }
            print("✓ Passed: \(service.model) answered.")
            return 0
        case .failure(let error):
            guard store.recordCheck(passed: false, message: error.localizedDescription, for: revision) else {
                printError("The setup changed during the check. Run check again.")
                return 1
            }
            if verbose, case ChatClientError.http(let status, _) = error {
                printError("HTTP \(status) from \(service.endpointDescription)")
            }
            printError("✗ Failed: \(error.localizedDescription)")
            if !verbose { printError("Details: \(name) check --verbose") }
            return 1
        }
    }

    /// Prints the probe request as it will be sent, with the key masked.
    private static func describeRequest(service: ModelService, apiKey: String, systemPrompt: String?, replyLanguage: String) {
        do {
            let request = try RequestBuilder.streamingRequest(
                service: service, apiKey: apiKey,
                messages: [ChatMessage(role: .user, content: ConnectionTester.probePrompt,
                                       taskInstructions: ReplyLanguage.instruction(replyLanguage))],
                options: ConnectionTester.probeOptions(appName: name, systemPrompt: systemPrompt)
            )
            print("\(request.httpMethod ?? "POST") \(request.url?.absoluteString ?? "?")")
            for (field, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
                print("\(field): \(masked(field: field, value: value))")
            }
            if let body = request.httpBody,
               let object = try? JSONSerialization.jsonObject(with: body),
               let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: pretty, as: UTF8.self))
            }
            print("")
        } catch {
            printError("Can't build the request: \(error.localizedDescription)")
        }
    }

    private static func masked(field: String, value: String) -> String {
        switch field.lowercased() {
        case "authorization": return value.hasPrefix("Bearer ") ? "Bearer ••••" : "••••"
        case "x-api-key", "x-goog-api-key": return "••••"
        default: return value
        }
    }

    // MARK: Helpers

    private final class ResultBox<T>: @unchecked Sendable {
        var result: Result<T, Error>?
    }

    /// Runs async work to completion from the synchronous command line.
    private static func wait<T>(_ operation: @escaping @Sendable () async throws -> T) -> Result<T, Error> {
        let box = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do { box.result = .success(try await operation()) } catch { box.result = .failure(error) }
            done.signal()
        }
        done.wait()
        return box.result ?? .failure(CancellationError())
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
