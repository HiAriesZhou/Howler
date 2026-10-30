import AppKit
import SwiftUI
import XCTest
@testable import Howler

final class ReducedMotionTests: XCTestCase {
    @MainActor
    private func render<V: View>(_ view: V, name: String) throws -> Data {
        _ = NSApplication.shared
        let renderer = ImageRenderer(content: view.frame(width: 500, height: 260).padding(20).background(.white))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        if let folder = ProcessInfo.processInfo.environment["HOWLER_TEST_SNAPSHOTS"] {
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
        return try XCTUnwrap(image.dataProvider?.data) as Data
    }

    @MainActor
    func testReducedMotionUsesStaticInkWhileOrdinaryWritingStillMoves() async throws {
        func letter(_ time: Double, reduced: Bool) -> some View {
            InkMarkdown(markdown: "A **synthetic answer** written in ink.",
                        writing: WritingState(gap: 0.5, time: time), reduceMotion: reduced)
        }
        let reducedA = try render(letter(1, reduced: true), name: "reduced-writing-1")
        let reducedB = try render(letter(2, reduced: true), name: "reduced-writing-2")
        XCTAssertTrue(reducedA == reducedB, "Reduced-motion frames must be identical")
        let animatedA = try render(letter(1, reduced: false), name: "ordinary-writing-1")
        let animatedB = try render(letter(2, reduced: false), name: "ordinary-writing-2")
        XCTAssertFalse(animatedA == animatedB, "Ordinary writing must still animate")
    }

    @MainActor
    func testReducedMotionKeepsTheThinkingQuillStill() async throws {
        func quill(_ time: Double, reduced: Bool) -> some View {
            QuillView(motion: .thinking, time: time, reduceMotion: reduced)
        }
        let reducedA = try render(quill(1, reduced: true), name: "reduced-thinking-1")
        let reducedB = try render(quill(2, reduced: true), name: "reduced-thinking-2")
        XCTAssertTrue(reducedA == reducedB, "Reduced-motion thinking must be static")
        let animatedA = try render(quill(1, reduced: false), name: "ordinary-thinking-1")
        let animatedB = try render(quill(2, reduced: false), name: "ordinary-thinking-2")
        XCTAssertFalse(animatedA == animatedB, "Ordinary thinking must still animate")
    }

    @MainActor
    func testReducedMotionPreservesStreamingMarkdownStabilization() async throws {
        let writing = WritingState(gap: 0.5, time: 1)
        let partial = try render(InkMarkdown(markdown: "A **synthetic answer", writing: writing, reduceMotion: true),
                                 name: "reduced-partial-markdown")
        let closed = try render(InkMarkdown(markdown: "A **synthetic answer**", writing: writing, reduceMotion: true),
                                name: "reduced-closed-markdown")
        XCTAssertTrue(partial == closed, "Partial emphasis must stay formatted while streaming without animation")
    }
}
