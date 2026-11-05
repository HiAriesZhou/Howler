import XCTest
@testable import HowlerCore

final class ReplyLanguageTests: XCTestCase {
    func testSystemLanguageDoesNotTransmitRegion() {
        XCTAssertEqual(ReplyLanguage.resolve(preference: "system", preferredLanguages: ["en-GB", "fr-FR"]), "en")
        XCTAssertEqual(ReplyLanguage.resolve(preference: "system", preferredLanguages: ["zh-Hant-TW"]), "zh-Hant")
        XCTAssertEqual(ReplyLanguage.resolve(preference: "system", preferredLanguages: ["zh-CN"]), "zh-Hans")
        XCTAssertEqual(ReplyLanguage.resolve(preference: "system", preferredLanguages: ["zh-TW"]), "zh-Hant")
        XCTAssertEqual(ReplyLanguage.resolve(preference: "system", preferredLanguages: []), "en")
        XCTAssertEqual(ReplyLanguage.resolve(preference: "invalid text", preferredLanguages: []), "en")
    }

    func testPreferenceAndTaskInstructionsAcrossAllProtocolsWithoutSystem() throws {
        XCTAssertEqual(ReplyLanguage.resolve(preference: "ja", preferredLanguages: ["en-US"]), "ja")
        for format in WireFormat.allCases {
            let service = ModelService(format: format, baseURL: URL(string: "https://model.example/v1")!, model: "fixture")
            let image = ImageData(data: Data([1, 2, 3]), mediaType: "image/png", width: 1, height: 1)
            let turn = ChatMessage(role: .user, content: "Image introduction",
                                   attachment: ContextAttachment(source: .screenshot, image: image),
                                   taskInstructions: ReplyLanguage.instruction("zh-Hans") + "\n" + ReplyLanguage.screenshotIntroduction)
            let request = try RequestBuilder.streamingRequest(service: service, apiKey: "fixture", messages: [turn])
            let data = try XCTUnwrap(request.httpBody)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let encoded = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(encoded.contains("zh-Hans"))
            XCTAssertTrue(encoded.contains("base64") || encoded.contains("AQID"))
            XCTAssertNil(body["system"])
            XCTAssertNil(body["systemInstruction"])
            if let messages = body["messages"] as? [[String: Any]] {
                XCTAssertFalse(messages.contains { $0["role"] as? String == "system" })
            }
            XCTAssertEqual(turn.content, "Image introduction")
        }
    }
}
