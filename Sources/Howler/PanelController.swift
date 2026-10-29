import AppKit
import Combine
import HowlerCore
import SwiftUI

/// Borderless, non-activating floating panel (Spotlight-style). It can become key so the
/// text field receives typing without pulling the previously active app to the back.
final class FloatingPanel: NSPanel {
    var onDismiss: (() -> Void)?
    /// Demo mode keeps the letter up while automation tools take focus.
    var dismissesOnResignKey = true

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // the letter casts its own, softer shadow
        // Paper is light in every appearance; keep caret, placeholder and selection colors
        // from following a dark desktop (the sheet itself is dimmed instead, see Parchment).
        appearance = NSAppearance(named: .aqua)
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    /// Clicking anywhere else closes the panel, like Spotlight.
    override func resignKey() {
        super.resignKey()
        if dismissesOnResignKey { onDismiss?() }
    }
}

/// Hosts the letter. The window is the sheet plus a transparent margin for its shadow and
/// the seals that overhang its edges; the sheet's height follows its content, from a
/// note-sized card up to an A4 page (or the screen, if smaller).
@MainActor
final class PanelController {
    static let paperWidth: CGFloat = 640
    static let minPaperHeight: CGFloat = 250
    static let setupPaperHeight: CGFloat = 230
    /// A4 is 1 : √2.
    static let a4Height = paperWidth * 1.414
    static let margins = NSEdgeInsets(top: 24, left: 36, bottom: 48, right: 36)

    let viewModel: ChatViewModel
    let settings: AppSettings
    let panel: FloatingPanel
    private let openSettings: () -> Void
    private var desiredPaperHeight = minPaperHeight
    private var maxPaperHeight = a4Height
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var isHiding = false
    private var burnCompletion: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.openSettings = openSettings
        viewModel = ChatViewModel(settings: settings)
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: Self.windowSize(paperHeight: Self.minPaperHeight)))

        let margins = Self.margins
        let hosting = NSHostingView(
            rootView: HowlerView(
                viewModel: viewModel,
                settings: settings,
                margins: EdgeInsets(top: margins.top, leading: margins.left, bottom: margins.bottom, trailing: margins.right),
                openSettings: openSettings,
                showProviderMenu: { [weak self] in self?.showServiceMenu() },
                showAttachMenu: { [weak self] in self?.showAttachMenu() },
                onDesiredHeight: { [weak self] height in self?.setDesiredPaperHeight(height) }
            )
        )
        hosting.sizingOptions = []
        panel.contentView = hosting
        viewModel.captureScreenRegion = { [weak self] completion in
            guard let self else { return completion(nil) }
            self.stepAsideForCapture(completion)
        }
        viewModel.keepingOpen = { [weak self] work in
            guard let self else { return work() }
            let dismisses = self.panel.dismissesOnResignKey
            self.panel.dismissesOnResignKey = false
            work()
            self.panel.dismissesOnResignKey = dismisses
            self.panel.makeKeyAndOrderFront(nil)
        }
        panel.onDismiss = { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.applyHeight() } }
            .store(in: &cancellables)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible && !isHiding { hide() } else { show() }
    }

    func show() {
        if isHiding { finishHiding() } // summoned again mid-burn: a fresh letter
        settings.reload()
        positionOnActiveScreen()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        viewModel.panelDidOpen(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            candlelit: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        installMonitors()
    }

    /// Closing the panel ends the conversation: history is discarded. Like a Howler, the
    /// letter goes up in flames on the way out, unless `burning` is false (opening
    /// Settings) or Reduce Motion is on.
    func hide(burning: Bool = true) {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true
        removeMonitors()
        guard burning, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finishHiding()
            return
        }
        viewModel.burn()
        let completion = DispatchWorkItem { [weak self] in self?.finishHiding() }
        burnCompletion = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + BurnField.duration, execute: completion)
    }

    private func finishHiding() {
        burnCompletion?.cancel()
        burnCompletion = nil
        panel.orderOut(nil)
        viewModel.reset()
        isHiding = false
    }

    // MARK: Layout

    private static func windowSize(paperHeight: CGFloat) -> NSSize {
        NSSize(
            width: paperWidth + margins.left + margins.right,
            height: paperHeight + margins.top + margins.bottom
        )
    }

    private var paperHeight: CGFloat {
        if !settings.isConfigured { return Self.setupPaperHeight }
        return min(max(desiredPaperHeight, Self.minPaperHeight), maxPaperHeight)
    }

    private func setDesiredPaperHeight(_ height: CGFloat) {
        guard abs(height - desiredPaperHeight) > 0.5 else { return }
        desiredPaperHeight = height
        applyHeight()
    }

    /// Grows or shrinks the sheet downward, keeping its top edge where it is. Not animated:
    /// the quill writes a line at a time, so the sheet already grows in small steps, and a
    /// window animation would trail the ink and push the top of the page out of view.
    private func applyHeight() {
        let size = Self.windowSize(paperHeight: paperHeight)
        var frame = panel.frame
        guard abs(frame.height - size.height) > 0.5 else { return }
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let paperTop = visible.maxY - visible.height * 0.16
        maxPaperHeight = max(Self.minPaperHeight, min(Self.a4Height, paperTop - visible.minY - 16))
        desiredPaperHeight = Self.minPaperHeight
        let size = Self.windowSize(paperHeight: paperHeight)
        panel.setFrame(
            NSRect(
                x: visible.midX - size.width / 2,
                y: paperTop + Self.margins.top - size.height,
                width: size.width,
                height: size.height
            ),
            display: false
        )
    }

    /// The sheet's rectangle in window coordinates.
    private var paperRect: NSRect {
        let bounds = panel.contentView?.bounds ?? .zero
        return NSRect(
            x: Self.margins.left,
            y: Self.margins.bottom,
            width: bounds.width - Self.margins.left - Self.margins.right,
            height: bounds.height - Self.margins.top - Self.margins.bottom
        )
    }

    // MARK: Service menu

    /// Pressing the stamp names the model writing the letter and offers Settings.
    private func showServiceMenu() {
        let menu = NSMenu()
        if let service = settings.service {
            let header = NSMenuItem(title: "Written by \(service.model)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            header.toolTip = service.summary
            menu.addItem(header)
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem(title: "Settings…") { [weak self] in self?.openSettings() })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: Attachments

    private func showAttachMenu() {
        let menu = NSMenu()
        let paste = ClosureMenuItem(title: "Paste from Clipboard") { [weak self] in self?.viewModel.pasteFromClipboard() }
        paste.keyEquivalent = "v"
        paste.keyEquivalentModifierMask = .command
        menu.addItem(paste)
        menu.addItem(ClosureMenuItem(title: "Capture Screen Region…") { [weak self] in self?.viewModel.captureScreen() })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// The letter gets out of the way while the user drags out a region, then comes back
    /// exactly as it was — conversation, size and all.
    private func stepAsideForCapture(_ completion: @escaping (Result<ImageData, Error>?) -> Void) {
        guard ScreenCapture.isAllowed else {
            viewModel.keepingOpen { ScreenCapture.requestPermission() }
            completion(.failure(ScreenCaptureError.permissionNeeded))
            return
        }
        guard panel.isVisible, !isHiding else { return completion(nil) }
        let dismisses = panel.dismissesOnResignKey
        panel.dismissesOnResignKey = false // ordering out resigns key; that isn't "clicked elsewhere"
        removeMonitors()
        panel.orderOut(nil)
        ScreenCapture.captureRegion { [weak self] result in
            guard let self else { return }
            self.panel.dismissesOnResignKey = dismisses
            self.panel.makeKeyAndOrderFront(nil)
            self.installMonitors()
            completion(result)
        }
    }

    // MARK: Event monitors

    private func installMonitors() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed: Bool = MainActor.assumeIsolated {
                    switch event.keyCode {
                    case 53: return self?.handleEscape(event) ?? false // kVK_Escape
                    case 9: return self?.handlePasteImage(event) ?? false // kVK_ANSI_V
                    case 8: return self?.handleCopyAnswer(event) ?? false // kVK_ANSI_C
                    default: return false
                    }
                }
                return consumed ? nil : event
            }
        }
        if mouseMonitor == nil {
            // The margin around the sheet is part of the window but not of the letter.
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                let outside: Bool = MainActor.assumeIsolated {
                    guard let self, event.window === self.panel else { return false }
                    return !self.paperRect.contains(event.locationInWindow)
                }
                guard outside else { return event }
                MainActor.assumeIsolated { self?.hide() }
                return nil
            }
        }
    }

    /// The focused text view swallows `cancelOperation:`, so catch Esc before it does.
    private func handleEscape(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        // Let Esc cancel an in-progress input-method composition (e.g. Pinyin) first.
        // SwiftUI's text field may not leave its editor as first responder, so also ask
        // the window's shared field editor.
        if let editor = panel.firstResponder as? NSTextInputClient, editor.hasMarkedText() {
            return false
        }
        if let editor = panel.fieldEditor(false, for: nil) as? NSTextView, editor.hasMarkedText() {
            return false
        }
        hide()
        return true
    }

    /// ⌘V with only a picture on the clipboard: seal it in, since the field can't hold it.
    private func handlePasteImage(_ event: NSEvent) -> Bool {
        guard event.window === panel,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              Clipboard.holdsOnlyImage,
              let image = Clipboard.image()
        else { return false }
        viewModel.pasteImage(image)
        return true
    }

    /// ⌘C with nothing selected copies the latest answer; with a selection it copies that,
    /// as everywhere else.
    private func handleCopyAnswer(_ event: NSEvent) -> Bool {
        guard event.window === panel,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              !viewModel.isStreaming,
              let answer = viewModel.lastAnswer,
              !hasSelectionToCopy()
        else { return false }
        viewModel.copy(answer)
        return true
    }

    /// Whether whatever would take a plain ⌘C (the question field, or answer text the user
    /// selected) has something selected.
    private func hasSelectionToCopy() -> Bool {
        let copy = #selector(NSText.copy(_:))
        guard let target = NSApp.target(forAction: copy, to: nil, from: nil) else { return false }
        if let textView = target as? NSTextView { return textView.selectedRange().length > 0 }
        guard let validator = target as? NSMenuItemValidation else { return true }
        return validator.validateMenuItem(NSMenuItem(title: "", action: copy, keyEquivalent: ""))
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil
    }
}

/// An `NSMenuItem` that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}
