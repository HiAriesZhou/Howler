#if DEBUG
import AppKit
import HowlerCore
import SwiftUI

/// `HOWLER_DEMO=1 swift run Howler` opens the letter with an attachment and writes a
/// scripted answer, without any network or API key. Used to check the look and motion.
///
/// Variants: `HOWLER_DEMO=setup` (no model yet), `empty` (configured blank letter), `long` (overflows an A4 page),
/// `multi` (a follow-up question), `queue` (screenshot with two waiting questions), `burn` (dismissed once written), `image` (a captured screen region),
/// `settings` (the Settings window with a synthetic setup; `HOWLER_DEMO_PROVIDER=anthropic` shows a demo one,
/// `HOWLER_DEMO_TAB=general|prompt|shortcut` opens that tab, `cycle` switches tabs every 1.5 s; without a
/// model Settings always opens on General; `HOWLER_DEMO_UPDATE=1` shows the update row, `=0.1.9` a
/// waiting update, `HOWLER_DEMO_SNAPSHOT=out.png` saves the window as a PNG and quits),
/// `appicon` (renders the app icon into the folder `HOWLER_DEMO_OUT`; see scripts/icon.sh);
/// `menu` opens the status menu, captures only its window to `HOWLER_DEMO_SNAPSHOT`, then quits;
/// `HOWLER_DEMO_DARK=1` forces Dark Mode.
/// `HOWLER_DEMO_NATIVE_SNAPSHOT=1` uses a window-only OS Settings capture (screen permission required).
/// A demo never reads the installed app's preferences or writes a synthetic setup to disk.
final class DemoDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

@MainActor
enum MenuDemo {
    static func present(_ menu: NSMenu) {
        let timer = Timer(timeInterval: 0.5, repeats: false) { _ in
            if let path = ProcessInfo.processInfo.environment["HOWLER_DEMO_SNAPSHOT"] {
                let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
                if let own = windows.first(where: {
                    ($0[kCGWindowOwnerPID as String] as? Int32) == getpid()
                    && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0
                }), let number = own[kCGWindowNumber as String] as? Int {
                    let capture = Process()
                    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    capture.arguments = ["-x", "-o", "-l", String(number), path]
                    try? capture.run()
                    capture.waitUntilExit()
                }
            }
            menu.cancelTracking()
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        menu.popUp(positioning: nil, at: NSPoint(x: 400, y: 400), in: nil)
        NSApp.terminate(nil)
    }
}

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
        if variant == "empty" {
            show()
            scheduleLetterSnapshot()
            return
        }
        if variant == "queue" {
            settings.setReplyLanguage("zh-Hans")
            var turn = 0
            let replies = [
                "这张截图展示了一行 Swift 代码：`items.reduce(0, +)`。它从 0 开始，把数组中的元素依次相加，得到总和。",
                "例如，`items` 是 `[2, 3, 5]` 时，结果是 **10**。这里的 `+` 就是每一步使用的合并操作。",
                "空数组没有元素需要合并，因此返回初始值 **0**。"
            ]
            viewModel.demoStream = {
                let answer = replies[min(turn, replies.count - 1)]
                turn += 1
                return Self.demoStream(repeats: 1, text: answer)
            }
            show()
            if let picture = Self.demoImage() { viewModel.introduceScreenshot(picture) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.viewModel.input = "这段代码会产生什么结果？"
                self?.viewModel.send()
                self?.viewModel.input = "空数组时会怎样？"
                self?.viewModel.send()
            }
            scheduleLetterSnapshot()
            return
        }
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
        scheduleLetterSnapshot()
        if variant == "multi" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
                self?.viewModel.input = "再用一句话总结"
                self?.viewModel.send()
            }
        }
    }

    private func scheduleLetterSnapshot() {
        guard let path = ProcessInfo.processInfo.environment["HOWLER_DEMO_SNAPSHOT"] else { return }
        let delay = Double(ProcessInfo.processInfo.environment["HOWLER_DEMO_DELAY"] ?? "2.5") ?? 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            if let view = self?.panel.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
            }
            NSApp.terminate(nil)
        }
    }

    private static func demoStream(repeats: Int, text: String? = nil) -> AsyncThrowingStream<String, Error> {
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
        let answer = Array(repeating: text ?? section, count: repeats).joined(separator: "\n\n")
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
