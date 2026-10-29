import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import HowlerCore

final class SystemPromptTests: XCTestCase {
    private let conversation = [ChatMessage(role: .user, content: "Hi")]
    /// 23:30 UTC: already the next day east of UTC, so a local date would differ.
    private let lateEvening = ISO8601DateFormatter().date(from: "2026-10-29T23:30:00Z")!

    private func body(_ provider: Provider, systemPrompt: String?, service: ModelService? = nil) throws -> [String: Any] {
        let request = try RequestBuilder.streamingRequest(
            service: service ?? provider.service(), apiKey: "k",
            messages: conversation, options: RequestOptions(systemPrompt: systemPrompt)
        )
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    // MARK: Composing

    func testDateIsUTCAndComesFirst() {
        let prompt = SystemPrompt.compose(instructions: "Be brief.", date: lateEvening)
        XCTAssertEqual(prompt, "Current date: 2026-10-29 (UTC).\n\nBe brief.")
    }

    func testBlankInstructionsTurnThePromptOff() {
        // Some models reject any system prompt; emptying the instructions is the way out.
        XCTAssertNil(SystemPrompt.compose(instructions: " \n ", date: lateEvening))
    }

    func testSuggestedPromptCarriesNoDateOrPersonalDetails() {
        // The date is added per request; the editable text must not freeze one in.
        XCTAssertFalse(SystemPrompt.suggested.contains("2026"))
        XCTAssertFalse(SystemPrompt.suggested.isEmpty)
    }

    // MARK: Where each format puts it

    func testOpenAICompatibleSendsASystemMessageFirst() throws {
        let messages = try XCTUnwrap(body(.deepSeek, systemPrompt: "Be brief.")["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [
            ["role": "system", "content": "Be brief."],
            ["role": "user", "content": "Hi"],
        ])
    }

    func testAnthropicUsesTheSystemField() throws {
        let anthropic = try body(.anthropic, systemPrompt: "Be brief.")
        XCTAssertEqual(anthropic["system"] as? String, "Be brief.")
        let messages = try XCTUnwrap(anthropic["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["user"])
    }

    func testGeminiUsesSystemInstruction() throws {
        let gemini = try body(.gemini, systemPrompt: "Be brief.")
        let instruction = try XCTUnwrap(gemini["systemInstruction"] as? [String: Any])
        XCTAssertEqual(instruction["parts"] as? [[String: String]], [["text": "Be brief."]])
    }

    func testNoSystemPromptSendsNothingExtra() throws {
        for prompt in [nil, "", "  \n"] {
            let openAI = try XCTUnwrap(body(.openAI, systemPrompt: prompt)["messages"] as? [[String: String]])
            XCTAssertEqual(openAI.map { $0["role"] }, ["user"])
            XCTAssertNil(try body(.anthropic, systemPrompt: prompt)["system"])
            XCTAssertNil(try body(.gemini, systemPrompt: prompt)["systemInstruction"])
        }
    }

    func testGeminiSnakeCaseInstructionInBodyIsNotDoubled() throws {
        var service = Provider.gemini.service()
        service.body = ["system_instruction": .object(["parts": .array([.object(["text": .string("From the setup.")])])])]
        let gemini = try body(.gemini, systemPrompt: "Be brief.", service: service)
        XCTAssertNil(gemini["systemInstruction"])
        XCTAssertNotNil(gemini["system_instruction"])
    }

    func testServiceBodyStillOverridesTheSystemPrompt() throws {
        var service = Provider.anthropic.service()
        service.body = ["system": .string("From the setup.")]
        XCTAssertEqual(try body(.anthropic, systemPrompt: "Be brief.", service: service)["system"] as? String, "From the setup.")
    }
}
