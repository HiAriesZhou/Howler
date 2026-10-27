import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import HowlerCore

final class RequestBuilderTests: XCTestCase {
    private let conversation = [
        ChatMessage(role: .user, content: "Hi"),
        ChatMessage(role: .assistant, content: "Hello!"),
        ChatMessage(role: .user, content: "What is 2+2?"),
    ]

    private func json(_ request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func build(_ provider: Provider, model: String = "", options: RequestOptions = RequestOptions()) throws -> URLRequest {
        try RequestBuilder.streamingRequest(
            service: provider.service(model: model), apiKey: " sk-test ",
            messages: conversation, options: options
        )
    }

    // MARK: OpenAI-compatible

    func testOpenAICompatibleEndpoints() throws {
        let expected: [Provider: String] = [
            .openAI: "https://api.openai.com/v1/chat/completions",
            .xAI: "https://api.x.ai/v1/chat/completions",
            .deepSeek: "https://api.deepseek.com/chat/completions",
            .openRouter: "https://openrouter.ai/api/v1/chat/completions",
        ]
        for (provider, url) in expected {
            let request = try build(provider)
            XCTAssertEqual(request.url?.absoluteString, url, provider.rawValue)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
            XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
        }
    }

    func testOpenAIBody() throws {
        let body = try json(build(.openAI, model: "gpt-test"))
        XCTAssertEqual(body["model"] as? String, "gpt-test")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNil(body["max_tokens"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [
            ["role": "user", "content": "Hi"],
            ["role": "assistant", "content": "Hello!"],
            ["role": "user", "content": "What is 2+2?"],
        ])
    }

    func testBlankModelUsesProviderDefault() throws {
        for provider in [Provider.openAI, .xAI, .deepSeek, .openRouter, .anthropic] {
            let body = try json(build(provider, model: "   "))
            XCTAssertEqual(body["model"] as? String, provider.defaultModel)
        }
        XCTAssertTrue(try build(.gemini).url!.path.hasSuffix("/models/\(Provider.gemini.defaultModel):streamGenerateContent"))
    }

    func testDeepSeekDefaultIsNotARetiredModel() throws {
        // deepseek-chat / deepseek-reasoner were removed on 2026-07-24.
        XCTAssertEqual(Provider.deepSeek.defaultModel, "deepseek-flash")
        let body = try json(build(.deepSeek, model: ""))
        XCTAssertEqual(body["model"] as? String, "deepseek-flash")
    }

    func testOpenRouterAttributionHeaders() throws {
        let request = try build(.openRouter, options: RequestOptions(appName: "Renamed"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "Renamed")
        XCTAssertEqual(request.value(forHTTPHeaderField: "HTTP-Referer"), RequestBuilder.projectURL)
        XCTAssertNil(try build(.openAI).value(forHTTPHeaderField: "X-Title"))
    }

    // MARK: Anthropic

    func testAnthropicRequest() throws {
        let request = try build(.anthropic, model: "claude-haiku-5-5")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-beta"))

        let body = try json(request)
        XCTAssertEqual(body["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["max_tokens"] as? Int, RequestBuilder.anthropicDefaultMaxTokens)
        XCTAssertNil(body["fallbacks"])
        XCTAssertNil(body["temperature"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["user", "assistant", "user"])
    }

    func testAnthropicFallbacksForSupportedModels() throws {
        let request = try build(.anthropic, model: "claude-opus-5-5", options: RequestOptions(maxTokens: 100))
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        let body = try json(request)
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertEqual(body["max_tokens"] as? Int, 100)
    }

    // MARK: Gemini

    func testGeminiRequest() throws {
        let request = try build(.gemini, model: "gemini-test-flash", options: RequestOptions(maxTokens: 50))
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(
            url.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-test-flash:streamGenerateContent?alt=sse"
        )
        XCTAssertFalse(url.absoluteString.contains("sk-test"), "API key must not be in the URL")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "sk-test")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let body = try json(request)
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.map { $0["role"] as? String }, ["user", "model", "user"])
        let parts = try XCTUnwrap(contents.last?["parts"] as? [[String: String]])
        XCTAssertEqual(parts, [["text": "What is 2+2?"]])
        let config = try XCTUnwrap(body["generationConfig"] as? [String: Int])
        XCTAssertEqual(config["maxOutputTokens"], 50)
    }

    func testGeminiAcceptsModelsPrefixAndRejectsPaths() throws {
        let request = try build(.gemini, model: "models/gemini-x")
        XCTAssertEqual(request.url?.path, "/v1beta/models/gemini-x:streamGenerateContent")
        XCTAssertThrowsError(try build(.gemini, model: "../../evil")) { error in
            XCTAssertEqual(error as? RequestBuilderError, .invalidModel("../../evil"))
        }
    }

    // MARK: Validation & normalisation

    func testMissingKeyThrows() {
        XCTAssertThrowsError(
            try RequestBuilder.streamingRequest(service: Provider.openAI.service(), apiKey: "  ", messages: conversation)
        ) { XCTAssertEqual($0 as? RequestBuilderError, .missingAPIKey) }
    }

    func testEmptyConversationThrows() {
        XCTAssertThrowsError(
            try RequestBuilder.streamingRequest(service: Provider.openAI.service(), apiKey: "k", messages: [])
        ) { XCTAssertEqual($0 as? RequestBuilderError, .noMessages) }
    }

    // MARK: Images

    private let screenshot = ContextAttachment(
        source: .screenshot,
        image: ImageData(data: Data("PNG".utf8), mediaType: "image/png", width: 2, height: 1)
    )

    private func buildWithImage(_ provider: Provider) throws -> [String: Any] {
        try json(RequestBuilder.streamingRequest(
            service: provider.service(), apiKey: "k",
            messages: [ChatMessage(role: .user, content: "Read this", attachment: screenshot)]
        ))
    }

    func testOpenAICompatibleImagePart() throws {
        let messages = try XCTUnwrap(buildWithImage(.openAI)["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["type"] as? String, "text")
        XCTAssertEqual(parts.first?["text"] as? String, "Read this")
        let imageURL = try XCTUnwrap((parts.last?["image_url"] as? [String: Any])?["url"] as? String)
        XCTAssertEqual(imageURL, "data:image/png;base64,UE5H")
    }

    func testAnthropicImageBlock() throws {
        let messages = try XCTUnwrap(buildWithImage(.anthropic)["messages"] as? [[String: Any]])
        let blocks = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.first?["type"] as? String, "image")
        let source = try XCTUnwrap(blocks.first?["source"] as? [String: String])
        XCTAssertEqual(source, ["type": "base64", "media_type": "image/png", "data": "UE5H"])
        XCTAssertEqual(blocks.last?["text"] as? String, "Read this")
    }

    func testGeminiInlineImage() throws {
        let contents = try XCTUnwrap(buildWithImage(.gemini)["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        let inline = try XCTUnwrap(parts.first?["inline_data"] as? [String: String])
        XCTAssertEqual(inline, ["mime_type": "image/png", "data": "UE5H"])
        XCTAssertEqual(parts.last?["text"] as? String, "Read this")
    }

    func testImagesAreLeftToTheService() throws {
        // DeepSeek's chat API takes image_url parts; whether a model reads them is its call.
        let messages = try XCTUnwrap(buildWithImage(.deepSeek)["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.last?["type"] as? String, "image_url")
    }

    func testNormalizeKeepsImagesWhenMerging() {
        let normalized = RequestBuilder.normalize([
            ChatMessage(role: .user, content: "first", attachment: screenshot),
            ChatMessage(role: .user, content: "second"),
        ])
        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized.first?.content, "first\n\nsecond")
        XCTAssertEqual(normalized.first?.image, screenshot.image)
    }

    func testNormalizeDropsEmptyAndMergesSameRole() {
        let messages = [
            ChatMessage(role: .assistant, content: "stray"),
            ChatMessage(role: .user, content: "first"),
            ChatMessage(role: .assistant, content: ""), // failed reply
            ChatMessage(role: .user, content: "retry"),
            ChatMessage(role: .assistant, content: "answer"),
        ]
        let normalized = RequestBuilder.normalize(messages)
        XCTAssertEqual(normalized.map(\.role), [.user, .assistant])
        XCTAssertEqual(normalized.map(\.content), ["first\n\nretry", "answer"])
    }
}
