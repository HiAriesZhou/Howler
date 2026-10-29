#if DEBUG
import AppKit
import HowlerCore
import SwiftUI

/// `HOWLER_DEMO=1 swift run Howler` opens the letter with an attachment and writes a
/// scripted answer, without any network or API key. Used to check the look and motion.
///
/// Variants: `HOWLER_DEMO=setup` (no model yet), `long` (overflows an A4 page),
/// `multi` (a follow-up question), `burn` (dismissed once written), `image` (a captured screen region),
/// `settings` (the Settings window with the real setup; `HOWLER_DEMO_PROVIDER=anthropic` shows a demo one),
/// `appicon` (renders the app icon into the folder `HOWLER_DEMO_OUT`; see scripts/icon.sh);
/// `HOWLER_DEMO_DARK=1` forces Dark Mode.
extension PanelController {
    func runDemo() {
        let variant = ProcessInfo.processInfo.environment["HOWLER_DEMO"] ?? "1"
        panel.dismissesOnResignKey = false
        if variant == "setup" {
            show()
            return
        }
        if variant == "appicon" {
            AppIconArt.write(to: ProcessInfo.processInfo.environment["HOWLER_DEMO_OUT"] ?? "AppIcon")
            NSApp.terminate(nil)
            return
        }
        settings.useDemoService(.anthropic)
        let repeats = variant == "long" ? 4 : 1
        viewModel.demoStream = { Self.demoStream(repeats: repeats) }
        show()
        viewModel.attach(
            ContextAttachment(source: .pasted, text: """
            func fibonacci(_ n: Int) -> Int {
                n < 2 ? n : fibonacci(n - 1) + fibonacci(n - 2)
            }
            """)!
        )
        if variant == "image", let image = Self.demoImage() {
            viewModel.attach(ContextAttachment(source: .screenshot, image: image))
        }
        let question = ProcessInfo.processInfo.environment["HOWLER_DEMO_QUESTION"] ?? "What does this do, and how can it be faster?"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.viewModel.input = question
            self?.viewModel.send()
        }
        if variant == "burn" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.5) { [weak self] in self?.hide() }
        }
        if variant == "multi" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
                self?.viewModel.input = "再用一句话总结"
                self?.viewModel.send()
            }
        }
    }

    private static func demoStream(repeats: Int) -> AsyncThrowingStream<String, Error> {
        let section = """
        This computes the **n-th Fibonacci number** recursively: each call branches into two more, so the work grows roughly as *φⁿ* — about 1.6× per step.

        A faster version keeps only the last two values:

        ```swift
        func fibonacci(_ n: Int) -> Int {
            var (a, b) = (0, 1)
            for _ in 0..<n { (a, b) = (b, a + b) }
            return a
        }
        ```

        - Time: O(n) instead of exponential
        - Space: O(1), no recursion depth to worry about

        斐波那契数列的迭代写法只需常数空间，适合较大的 `n`。
        """
        let answer = Array(repeating: section, count: repeats).joined(separator: "\n\n")
        return AsyncThrowingStream { continuation in
            let task = Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000) // let the quill think a moment
                var index = answer.startIndex
                while index < answer.endIndex {
                    let end = answer.index(index, offsetBy: Int.random(in: 3...14), limitedBy: answer.endIndex) ?? answer.endIndex
                    continuation.yield(String(answer[index..<end]))
                    index = end
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 20_000_000...90_000_000))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A small stand-in for a screen capture.
    private static func demoImage() -> ImageData? {
        let picture = NSImage(size: NSSize(width: 640, height: 360), flipped: false) { rect in
            NSGradient(starting: .systemIndigo, ending: .systemTeal)?.draw(in: rect, angle: 30)
            let text = NSAttributedString(string: "let total = items.reduce(0, +)", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 26, weight: .medium),
                .foregroundColor: NSColor.white,
            ])
            text.draw(at: NSPoint(x: 40, y: 160))
            return true
        }
        guard let tiff = picture.tiffRepresentation else { return nil }
        return UploadImage.prepare(tiff)
    }
}
#endif
