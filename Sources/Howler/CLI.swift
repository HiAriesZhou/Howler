import Foundation
import HowlerCore

/// The app's command line, for setting up the model service by hand or through an AI
/// assistant (Settings › Copy Setup Prompt). It shares `ServiceStore` with the app and never
/// prints the API key.
///
///     Howler config schema | show | set field=value … | set api-key --stdin|--env NAME|--file PATH | reset
///     Howler check [--verbose]
enum CLI {
    private static let commands: Set<String> = ["config", "check", "help", "--help", "-h", "version", "--version"]

    /// Runs a command-line invocation and returns its exit status, or nil when the
    /// arguments are not a command and the app should launch as usual.
    static func run(_ arguments: [String]) -> Int32? {
        let args = Array(arguments.dropFirst())
        guard let command = args.first, commands.contains(command) else { return nil }
        // Keep stdout and stderr in order when piped (an assistant reads both).
        setvbuf(stdout, nil, _IOLBF, 0)
        let store = ServiceStore()
        store.migrateLegacySetup()
        do {
            switch command {
            case "config": try config(Array(args.dropFirst()), store: store)
            case "check": return check(verbose: args.contains("--verbose") || args.contains("-v"), store: store)
            case "version", "--version": print("\(AppInfo.name) \(AppInfo.version)")
            default: print(usage)
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

    private static func config(_ args: [String], store: ServiceStore) throws {
        switch args.first {
        case "schema":
            print(SetupGuide.schema(appName: name))
        case "show", nil:
            show(store)
        case "set":
            let fields = Array(args.dropFirst())
            if fields.first == "api-key" {
                try setKey(Array(fields.dropFirst()), store: store)
            } else {
                guard !fields.isEmpty else { throw UsageError("Nothing to set. See: \(name) config schema") }
                let service = try ServiceConfig.apply(fields, to: store.service)
                try store.save(service)
                print("Saved: \(service.summary)")
                print(store.hasKey ? "Next: \(name) check" : "Next: pbpaste | \(name) config set api-key --stdin")
            }
        case "reset":
            store.reset()
            print("Removed the model service and its API key.")
        default:
            throw UsageError(usage)
        }
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
            ("api-key", store.hasKey ? "saved in Keychain" : "not set"),
            ("check", checkSummary(store.lastCheck)),
        ]
        for (label, value) in rows {
            print(label.padding(toLength: 10, withPad: " ", startingAt: 0) + value)
        }
    }

    private static func checkSummary(_ record: ServiceStore.CheckRecord?) -> String {
        guard let record else { return "not checked since the last change" }
        let date = record.date.formatted(date: .abbreviated, time: .shortened)
        return record.passed ? "passed (\(date))" : "failed (\(date)): \(record.message ?? "unknown error")"
    }

    /// The key comes from a pipe, an environment variable or a file — never an argument,
    /// where it would end up in shell history and process listings.
    private static func setKey(_ args: [String], store: ServiceStore) throws {
        let raw: String
        switch args.first {
        case "--stdin":
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
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw UsageError("The API key is empty. Copy it again and retry.") }
        guard !key.contains(where: \.isWhitespace) else {
            throw UsageError("That doesn't look like a single API key (it contains spaces or line breaks).")
        }
        try store.setAPIKey(key)
        print("API key saved in Keychain.")
        if store.service != nil { print("Next: \(name) check") }
    }

    // MARK: check

    private static func check(verbose: Bool, store: ServiceStore) -> Int32 {
        guard let service = store.service else {
            printError("No model service yet. See: \(name) config schema")
            return 1
        }
        guard let key = store.apiKey(), !key.isEmpty else {
            printError("No API key saved. Copy it, then run: pbpaste | \(name) config set api-key --stdin")
            return 1
        }
        if verbose { describeRequest(service: service, apiKey: key) }
        print("Checking \(service.summary) …")

        let result = wait {
            try await ConnectionTester.test(client: ChatClient(), service: service, apiKey: key, appName: name)
        }
        switch result {
        case .success:
            store.recordCheck(passed: true, message: nil)
            print("✓ Passed: \(service.model) answered.")
            return 0
        case .failure(let error):
            store.recordCheck(passed: false, message: error.localizedDescription)
            if verbose, case ChatClientError.http(let status, _) = error {
                printError("HTTP \(status) from \(service.endpointDescription)")
            }
            printError("✗ Failed: \(error.localizedDescription)")
            if !verbose { printError("Details: \(name) check --verbose") }
            return 1
        }
    }

    /// Prints the probe request as it will be sent, with the key masked.
    private static func describeRequest(service: ModelService, apiKey: String) {
        do {
            let request = try RequestBuilder.streamingRequest(
                service: service, apiKey: apiKey,
                messages: ConnectionTester.probeMessages,
                options: ConnectionTester.probeOptions(appName: name)
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
