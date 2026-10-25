import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating floating panel (Spotlight-style). It can become key so the
/// text field receives typing without pulling the previously active app to the back.
final class FloatingPanel: NSPanel {
    var onDismiss: (() -> Void)?

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
        hasShadow = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    /// Clicking anywhere else closes the panel, like Spotlight.
    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }
}

@MainActor
final class PanelController {
    static let width: CGFloat = 720
    static let compactHeight: CGFloat = 64
    static let setupHeight: CGFloat = 150
    static let expandedHeight: CGFloat = 520

    let viewModel: ChatViewModel
    private let settings: AppSettings
    private let panel: FloatingPanel
    private var escapeMonitor: Any?
    private var isHiding = false
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings, openSettings: @escaping () -> Void) {
        self.settings = settings
        viewModel = ChatViewModel(settings: settings)
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.compactHeight))

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: 14)

        let hosting = NSHostingView(
            rootView: ChatView(viewModel: viewModel, settings: settings, openSettings: openSettings)
        )
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        panel.onDismiss = { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }

        // Resize after the published change has been applied.
        viewModel.objectWillChange
            .merge(with: settings.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateHeight(animated: true) }
            }
            .store(in: &cancellables)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        updateHeight(animated: false)
        positionOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)
        viewModel.requestFocus()
        installEscapeMonitor()
    }

    /// Closing the panel ends the conversation: history is discarded.
    func hide() {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true
        defer { isHiding = false }
        removeEscapeMonitor()
        panel.orderOut(nil)
        viewModel.reset()
    }

    // MARK: Layout

    private var desiredHeight: CGFloat {
        if !settings.isConfigured { return Self.setupHeight }
        if viewModel.messages.isEmpty && viewModel.errorText == nil { return Self.compactHeight }
        return Self.expandedHeight
    }

    private func updateHeight(animated: Bool) {
        let height = desiredHeight
        var frame = panel.frame
        guard frame.height != height else { return }
        frame.origin.y += frame.height - height // keep the top edge fixed
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: animated && panel.isVisible)
        panel.invalidateShadow()
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let top = visible.maxY - visible.height * 0.2
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: top - size.height))
    }

    // MARK: Escape

    /// The focused text view swallows `cancelOperation:`, so catch Esc before it does.
    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // kVK_Escape
            let consumed: Bool = MainActor.assumeIsolated {
                guard let self, event.window === self.panel else { return false }
                // Let Esc cancel an in-progress input-method composition (e.g. Pinyin) first.
                if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() {
                    return false
                }
                self.hide()
                return true
            }
            return consumed ? nil : event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
