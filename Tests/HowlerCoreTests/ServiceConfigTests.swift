import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import HowlerCore

final class ServiceConfigTests: XCTestCase {
    private func json(_ request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func request(_ service: ModelService) throws -> URLRequest {
        try RequestBuilder.streamingRequest(
            service: service, apiKey: "k", messages: [ChatMessage(role: .user, content: "hi")]
        )
    }

    // MARK: config set

    func testPresetFillsTheService() throws {
        let service = try ServiceConfig.apply(["preset=deepseek"], to: nil)
        XCTAssertEqual(service, Provider.deepSeek.service())
        XCTAssertEqual(service.summary, "deepseek-flash · api.deepseek.com · Chat Completions")
    }

    func testLaterFieldsRefineThePreset() throws {
        let service = try ServiceConfig.apply(
            ["preset=anthropic", "model=claude-haiku-5-5", #"body={"max_tokens": 1024}"#], to: nil
        )
        XCTAssertEqual(service.format, .anthropic)
        XCTAssertEqual(service.model, "claude-haiku-5-5")
        XCTAssertEqual(service.body, ["max_tokens": .int(1024)])
    }

    func testPresetClearsServiceSpecificFields() throws {
        let current = ModelService(
            format: .openAICompatible, baseURL: URL(string: "https://example.com/v1")!, model: "m",
            body: ["reasoning_effort": .string("low")], headers: ["X-Team": "a"]
        )
        let service = try ServiceConfig.apply(["preset=gemini"], to: current)
        XCTAssertEqual(service, Provider.gemini.service())
    }

    func testCustomServiceNeedsAllCoreFields() {
        XCTAssertThrowsError(try ServiceConfig.apply(["model=m"], to: nil)) {
            XCTAssertEqual($0 as? ServiceConfigError, .missing(["format", "base-url"]))
        }
        XCTAssertNoThrow(try ServiceConfig.apply(
            ["format=chat-completions", "base-url=https://api.example.com/v1/", "model=m"], to: nil
        ))
    }

    func testPartialUpdateKeepsTheRest() throws {
        let service = try ServiceConfig.apply(["model=deepseek-pro"], to: Provider.deepSeek.service())
        XCTAssertEqual(service.baseURL, Provider.deepSeek.baseURL)
        XCTAssertEqual(service.model, "deepseek-pro")
    }

    func testBaseURLRules() throws {
        let local = try ServiceConfig.apply(
            ["format=chat-completions", "base-url=http://localhost:11434/v1/", "model=llama"], to: nil
        )
        XCTAssertEqual(local.baseURL.absoluteString, "http://localhost:11434/v1")
        for bad in ["base-url=http://api.example.com", "base-url=not a url", "base-url=https://x.com/v1?key=1"] {
            XCTAssertThrowsError(try ServiceConfig.apply([bad], to: Provider.openAI.service()), bad)
        }
    }

    func testRejectsBadValues() {
        let current = Provider.openAI.service()
        let cases: [String] = [
            "format=responses",
            "preset=mistral",
            "model=two words",
            "body=[1, 2]",
            #"body={"messages": []}"#,
            #"headers={"Authorization": "Bearer x"}"#,
            #"headers={"X-Count": 3}"#,
            "colour=red",
            "model",
        ]
        for argument in cases {
            XCTAssertThrowsError(try ServiceConfig.apply([argument], to: current), argument)
        }
    }

    func testAPIKeyIsNeverAcceptedAsAField() {
        for argument in ["api-key=sk-123", "API-KEY=sk-123", "api-key"] {
            XCTAssertThrowsError(try ServiceConfig.apply([argument], to: nil)) {
                XCTAssertEqual($0 as? ServiceConfigError, .apiKeyOnCommandLine)
            }
        }
    }

    func testEmptyBodyAndHeadersClear() throws {
        let current = ModelService(
            format: .openAICompatible, baseURL: Provider.openAI.baseURL, model: "m",
            body: ["temperature": .double(0.2)], headers: ["X-Team": "a"]
        )
        let service = try ServiceConfig.apply(["body=", "headers={}"], to: current)
        XCTAssertEqual(service.body, [:])
        XCTAssertEqual(service.headers, [:])
    }

    // MARK: Storage

    func testServiceRoundTripsThroughJSON() throws {
        let service = ModelService(
            format: .anthropic, baseURL: Provider.anthropic.baseURL, model: "claude-haiku-5-5",
            body: ["thinking": .object(["type": .string("disabled")]), "max_tokens": .int(2048), "temperature": .double(0.5)],
            headers: ["anthropic-beta": "x"]
        )
        let decoded = try JSONDecoder().decode(ModelService.self, from: JSONEncoder().encode(service))
        XCTAssertEqual(decoded, service)
    }

    // MARK: Requests

    func testBodyFieldsAreMergedAndOverrideDefaults() throws {
        var service = Provider.anthropic.service()
        service.body = ["max_tokens": .int(1024), "thinking": .object(["type": .string("disabled")])]
        let body = try json(request(service))
        XCTAssertEqual(body["max_tokens"] as? Int, 1024)
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testExtraHeadersAreSentButNeverReplaceTheKey() throws {
        var service = Provider.openAI.service()
        service.headers = ["X-Team": "letters", "Authorization": "Bearer stolen"]
        let built = try request(service)
        XCTAssertEqual(built.value(forHTTPHeaderField: "X-Team"), "letters")
        XCTAssertEqual(built.value(forHTTPHeaderField: "Authorization"), "Bearer k")
    }

    func testCustomCompatibleService() throws {
        let service = try ServiceConfig.apply(
            ["format=chat-completions", "base-url=http://localhost:11434/v1", "model=llama3.2"], to: nil
        )
        let built = try request(service)
        XCTAssertEqual(built.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(built.value(forHTTPHeaderField: "X-Title")) // OpenRouter-only attribution
        XCTAssertEqual(service.glyph, .letters("L"))
        XCTAssertEqual(service.endpointDescription, "http://localhost:11434/v1/chat/completions")
    }

    func testAnthropicFallbacksOnlyForAnthropicItself() throws {
        var proxy = Provider.anthropic.service(model: "claude-opus-5-5")
        proxy.baseURL = URL(string: "https://gateway.example.com/anthropic/v1")!
        let built = try request(proxy)
        XCTAssertNil(built.value(forHTTPHeaderField: "anthropic-beta"))
        XCTAssertNil(try json(built)["fallbacks"])
        XCTAssertEqual(built.url?.absoluteString, "https://gateway.example.com/anthropic/v1/messages")
    }

    func testGlyphs() {
        XCTAssertEqual(Provider.deepSeek.service().glyph, .letters("D"))
        XCTAssertEqual(Provider.gemini.service().glyph, .symbol("sparkle"))
        let other = ModelService(format: .openAICompatible, baseURL: URL(string: "https://api.moonshot.cn/v1")!, model: "m")
        XCTAssertEqual(other.glyph, .letters("M"))
    }

    // MARK: Setup guide

    func testPromptNamesTheCommandAndCurrentSetup() {
        let prompt = SetupGuide.prompt(
            appName: "Howler",
            executable: "/Applications/Howler.app/Contents/MacOS/Howler",
            current: Provider.deepSeek.service()
        )
        XCTAssertTrue(prompt.contains("command line: /Applications/Howler.app/Contents/MacOS/Howler\n"))
        XCTAssertTrue(prompt.contains("Current setup: deepseek-flash · api.deepseek.com · Chat Completions"))
        XCTAssertTrue(prompt.contains("pbpaste | Howler config set api-key --stdin"))
        XCTAssertTrue(SetupGuide.prompt(appName: "Howler", executable: "/x", current: nil).contains("not set up yet"))
    }

    func testPromptQuotesPathsWithSpaces() {
        XCTAssertEqual(SetupGuide.shellQuoted("/Users/me/My Apps/Howler"), "'/Users/me/My Apps/Howler'")
        XCTAssertEqual(SetupGuide.shellQuoted("/Applications/Howler.app"), "/Applications/Howler.app")
    }

    func testSchemaListsEveryFieldAndPreset() {
        let schema = SetupGuide.schema(appName: "Howler")
        for field in ServiceConfig.Field.allCases {
            XCTAssertTrue(schema.contains("  \(field.rawValue) "), field.rawValue)
        }
        for provider in Provider.allCases {
            XCTAssertTrue(schema.contains(provider.baseURL.absoluteString), provider.rawValue)
        }
    }
}
