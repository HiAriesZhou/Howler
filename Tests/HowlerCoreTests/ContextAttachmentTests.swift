import XCTest
@testable import HowlerCore

final class ContextAttachmentTests: XCTestCase {
    func testBlankTextIsNotAnAttachment() {
        XCTAssertNil(ContextAttachment(source: .pasted, text: ""))
        XCTAssertNil(ContextAttachment(source: .pasted, text: "  \n\t "))
    }

    func testSummaryCountsCharacters() throws {
        let short = try XCTUnwrap(ContextAttachment(source: .pasted, text: "你好，世界"))
        XCTAssertEqual(short.characterCount, 5)
        XCTAssertEqual(short.summary, "Pasted text · 5 chars")

        let long = try XCTUnwrap(ContextAttachment(source: .pasted, text: String(repeating: "a", count: 1_284)))
        XCTAssertEqual(long.summary, "Pasted text · 1.3k chars")

        let pasted = try XCTUnwrap(ContextAttachment(source: .pasted, text: String(repeating: "b", count: 2_000)))
        XCTAssertEqual(pasted.summary, "Pasted text · 2k chars")
        XCTAssertTrue(pasted.prompt(for: "q").hasPrefix(#"<context source="pasted">"#))
    }

    func testLongTextIsTruncatedButCountKeepsOriginalLength() throws {
        let attachment = try XCTUnwrap(ContextAttachment(source: .pasted, text: String(repeating: "x", count: 50), limit: 10))
        XCTAssertTrue(attachment.isTruncated)
        XCTAssertEqual(attachment.text?.count, 10)
        XCTAssertEqual(attachment.characterCount, 50)
        XCTAssertTrue(attachment.prompt(for: "q").contains(#"truncated="true""#))
    }

    func testPromptWrapsContextBeforeQuestion() throws {
        let attachment = try XCTUnwrap(ContextAttachment(source: .pasted, text: "\nfunc f() {}\n"))
        XCTAssertEqual(
            attachment.prompt(for: "What does this do?"),
            """
            <context source="pasted">
            func f() {}
            </context>

            What does this do?
            """
        )
    }

    func testImageAttachment() {
        let image = ImageData(data: Data([1, 2, 3]), mediaType: "image/png", width: 1280, height: 720)
        let shot = ContextAttachment(source: .screenshot, image: image)
        XCTAssertEqual(shot.summary, "Screenshot · 1280×720")
        XCTAssertEqual(shot.title, "Screenshot")
        XCTAssertEqual(shot.image, image)
        XCTAssertNil(shot.text)
        XCTAssertEqual(ContextAttachment(source: .pasted, image: image).title, "Pasted image")

        // Images travel as their own content part, not inside the prompt text.
        let message = ChatMessage(role: .user, content: "What is this?", attachment: shot)
        XCTAssertEqual(message.wireContent, "What is this?")
        XCTAssertEqual(message.image, image)
    }

    func testPreviewKeepsFirstLines() throws {
        let attachment = try XCTUnwrap(ContextAttachment(source: .pasted, text: "1\n2\n3\n4"))
        XCTAssertEqual(attachment.preview(maxLines: 2), "1\n2\n…")
        XCTAssertEqual(attachment.preview(maxLines: 10), "1\n2\n3\n4")
    }

    func testMessageWireContentIncludesAttachment() throws {
        let attachment = try XCTUnwrap(ContextAttachment(source: .pasted, text: "ctx"))
        let message = ChatMessage(role: .user, content: "q", attachment: attachment)
        XCTAssertEqual(message.wireContent, attachment.prompt(for: "q"))
        XCTAssertEqual(ChatMessage(role: .user, content: "plain").wireContent, "plain")
    }

    func testNormalizeSendsWireContent() throws {
        let attachment = try XCTUnwrap(ContextAttachment(source: .pasted, text: "ctx"))
        let normalized = RequestBuilder.normalize([ChatMessage(role: .user, content: "q", attachment: attachment)])
        XCTAssertEqual(normalized.map(\.content), [attachment.prompt(for: "q")])
    }
}

final class HotKeyComboTests: XCTestCase {
    func testDefaultIsOptionH() {
        XCTAssertEqual(HotKeyCombo.standard.display, "⌥H")
        XCTAssertEqual(HotKeyCombo.standard.keyCode, 4) // kVK_ANSI_H
        XCTAssertTrue(HotKeyCombo.standard.isValid)
        XCTAssertEqual(HotKeyCombo.previousStandard.display, "⌥Space")
        XCTAssertNotEqual(HotKeyCombo.standard, HotKeyCombo.previousStandard)
    }

    func testOptionCommaIsKeptForSettings() {
        XCTAssertEqual(HotKeyCombo.settings.display, "⌥,")
        XCTAssertEqual(HotKeyCombo.settings.keyCode, 43) // kVK_ANSI_Comma
        // It can't also open the letter; a stored ⌥, (the default in 0.1.8–0.1.9) falls back to ⌥H.
        XCTAssertFalse(HotKeyCombo.settings.isValid)
        XCTAssertEqual(HotKeyCombo.effective(stored: .settings), .standard)
    }

    func testStoredShortcutResolution() {
        let custom = HotKeyCombo(keyCode: 40, modifiers: [.control, .option], keyLabel: "K")
        XCTAssertEqual(HotKeyCombo.effective(stored: nil), .standard)
        XCTAssertEqual(HotKeyCombo.effective(stored: custom), custom)
        XCTAssertEqual(HotKeyCombo.effective(stored: HotKeyCombo(keyCode: 40, modifiers: [], keyLabel: "K")), .standard)
        // Recorded on purpose after the upgrade, ⌥Space is kept.
        XCTAssertEqual(HotKeyCombo.effective(stored: .previousStandard), .previousStandard)
    }

    func testDefaultChangeDropsOnlyTheOldDefault() {
        // The old Reset stored ⌥Space; on the one-time upgrade it follows the default.
        XCTAssertNil(HotKeyCombo.storedAfterDefaultChange(.previousStandard))
        let custom = HotKeyCombo(keyCode: 40, modifiers: [.control, .option], keyLabel: "K")
        XCTAssertEqual(HotKeyCombo.storedAfterDefaultChange(custom), custom)
        XCTAssertNil(HotKeyCombo.storedAfterDefaultChange(nil))
    }

    func testDisplayUsesMacModifierOrder() {
        let combo = HotKeyCombo(keyCode: 40, modifiers: [.command, .shift, .option, .control], keyLabel: "K")
        XCTAssertEqual(combo.display, "⌃⌥⇧⌘K")
    }

    func testRequiresARealModifierUnlessFunctionKey() {
        XCTAssertFalse(HotKeyCombo(keyCode: 40, modifiers: [], keyLabel: "K").isValid)
        XCTAssertFalse(HotKeyCombo(keyCode: 40, modifiers: [.shift], keyLabel: "K").isValid)
        XCTAssertTrue(HotKeyCombo(keyCode: 40, modifiers: [.control], keyLabel: "K").isValid)
        XCTAssertTrue(HotKeyCombo(keyCode: 122, modifiers: [], keyLabel: "F1").isValid)
        XCTAssertFalse(HotKeyCombo(keyCode: 53, modifiers: [.command], keyLabel: "⎋").isValid)
    }

    func testStandardEditingShortcutsAreReserved() {
        for (code, label) in [(9, "V"), (8, "C"), (7, "X"), (6, "Z"), (0, "A"), (12, "Q"), (13, "W")] {
            XCTAssertFalse(HotKeyCombo(keyCode: UInt32(code), modifiers: [.command], keyLabel: label).isValid, label)
        }
        XCTAssertFalse(HotKeyCombo(keyCode: 49, modifiers: [.command], keyLabel: "Space").isValid)
        XCTAssertFalse(HotKeyCombo(keyCode: 48, modifiers: [.command], keyLabel: "⇥").isValid)
        // The same keys with another modifier are fine.
        XCTAssertTrue(HotKeyCombo(keyCode: 9, modifiers: [.command, .option], keyLabel: "V").isValid)
    }

    func testKeyLabels() {
        XCTAssertEqual(HotKeyCombo.label(keyCode: 49, characters: " "), "Space")
        XCTAssertEqual(HotKeyCombo.label(keyCode: 122, characters: nil), "F1")
        XCTAssertEqual(HotKeyCombo.label(keyCode: 36, characters: "\r"), "↩")
        XCTAssertEqual(HotKeyCombo.label(keyCode: 40, characters: "k"), "K")
        XCTAssertNil(HotKeyCombo.label(keyCode: 999, characters: nil))
    }

    func testRoundTripsThroughJSON() throws {
        let combo = HotKeyCombo(keyCode: 40, modifiers: [.command, .option], keyLabel: "K")
        let data = try JSONEncoder().encode(combo)
        XCTAssertEqual(try JSONDecoder().decode(HotKeyCombo.self, from: data), combo)
    }
}

final class QuillPacingTests: XCTestCase {
    func testNeverOvershootsTheTarget() {
        XCTAssertEqual(QuillPacing.advance(9.5, toward: 10, elapsed: 1), 10)
        XCTAssertEqual(QuillPacing.advance(10, toward: 10, elapsed: 1), 10)
    }

    func testSmallBacklogMovesAtMinimumSpeed() {
        let next = QuillPacing.advance(0, toward: 5, elapsed: 0.05)
        XCTAssertEqual(next, QuillPacing.minimumSpeed * 0.05, accuracy: 0.0001)
    }

    func testLargeBacklogCatchesUpQuickly() {
        var progress = 0.0
        var elapsed = 0.0
        while progress < 1_990 && elapsed < 5 {
            progress = QuillPacing.advance(progress, toward: 2_000, elapsed: 1.0 / 60)
            elapsed += 1.0 / 60
        }
        XCTAssertLessThan(elapsed, 2.5, "a 2,000-character burst should be written within a couple of seconds")
    }

    func testNegativeElapsedDoesNotMoveBackwards() {
        XCTAssertEqual(QuillPacing.advance(3, toward: 10, elapsed: -1), 3)
    }

    func testTargetBelowProgressSnapsBack() {
        XCTAssertEqual(QuillPacing.advance(8, toward: 2, elapsed: 0.1), 2)
    }
}
