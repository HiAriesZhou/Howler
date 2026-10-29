import AppKit
import Combine
import SwiftUI

/// Which Settings tab is showing, shared by the toolbar and the pages.
@MainActor
final class SettingsTabState: ObservableObject {
    @Published var selected: SettingsTab = .model
    /// The page fading out, which stays enabled until it has gone; every other hidden page
    /// is disabled so it leaves the keyboard focus order.
    @Published var leaving: SettingsTab?
    /// The natural height of each page, measured by SwiftUI.
    @Published var heights: [SettingsTab: CGFloat] = [:]
}

/// The Settings window: toolbar tabs, like System Settings' older panes. All pages stay
/// mounted, so a switch never rebuilds one: the pages crossfade while the window eases to
/// the new page's height, its top edge fixed. A page that grows on its own (e.g. a failed
/// check) is followed the same way. Reduce Motion switches at once.
@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate {
    static let switchDuration: TimeInterval = 0.22
    /// Every page's width (see `SettingsPage`).
    static let width: CGFloat = 460

    private let settings: AppSettings
    private let state = SettingsTabState()
    private var window: NSWindow?
    private var observers: Set<AnyCancellable> = []
    /// False until the window has its first real size; that one is set without animation
    /// and the window centered on it, so it never grows into place on first open.
    private var fitted = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show(tab: SettingsTab? = nil) {
        settings.reload()
        settings.refreshLaunchAtLogin()
        if window == nil { makeWindow() }
        // Without a model, the Model tab is the only one that matters.
        let target = settings.isConfigured ? tab : .model
        if let target { select(target, animated: false) }
        // Accessory apps must activate explicitly for a regular window to take focus.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() {
        let host = NSHostingController(rootView: SettingsTabsView(settings: settings, state: state))
        host.sizingOptions = [] // the window's height follows the selected page, below
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: "settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        self.window = window

        state.$heights
            .sink { [weak self] _ in
                // Published before the change lands; read it on the next turn.
                DispatchQueue.main.async { self?.fitWindow(animated: true) }
            }
            .store(in: &observers)
        select(state.selected, animated: false)
        host.view.layoutSubtreeIfNeeded()
        fitWindow(animated: false)
        if !fitted { window.center() }
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func select(_ tab: SettingsTab, animated: Bool) {
        window?.toolbar?.selectedItemIdentifier = tab.toolbarIdentifier
        window?.title = tab.title
        guard tab != state.selected else { return }
        // Typing must not reach a page that is going away, nor a shortcut be recorded on it.
        window?.makeFirstResponder(nil)
        if settings.isRecordingHotKey { settings.isRecordingHotKey = false }
        let previous = state.selected
        if animated && !reduceMotion {
            state.leaving = previous
            withAnimation(.easeInOut(duration: Self.switchDuration), completionCriteria: .logicallyComplete) {
                state.selected = tab
            } completion: { [state] in
                if state.leaving == previous { state.leaving = nil }
            }
        } else {
            state.leaving = nil
            state.selected = tab
        }
        fitWindow(animated: animated)
    }

    @objc private func toolbarItemClicked(_ item: NSToolbarItem) {
        guard let tab = SettingsTab.allCases.first(where: { $0.toolbarIdentifier == item.itemIdentifier }) else { return }
        select(tab, animated: true)
    }

    /// Sizes the window to the selected page, keeping its top edge where it is.
    private func fitWindow(animated: Bool) {
        guard let window, let height = state.heights[state.selected], height > 0 else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        guard abs(content.height - height) > 0.5 || content.width != Self.width else { return }
        var frame = window.frameRect(forContentRect: NSRect(x: content.minX, y: content.minY, width: Self.width, height: height))
        frame.origin.y = window.frame.maxY - frame.height
        guard animated, fitted, !reduceMotion, window.isVisible else {
            window.setFrame(frame, display: true)
            if !fitted {
                fitted = true
                window.center()
            }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.switchDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    #if DEBUG
    /// Demo: steps through the tabs to watch the switch.
    func cycleTabs() {
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let tabs = SettingsTab.allCases
                let next = tabs[(tabs.firstIndex(of: self.state.selected)! + 1) % tabs.count]
                self.select(next, animated: true)
            }
        }
    }
    #endif

    // MARK: NSToolbarDelegate

    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + SettingsTab.allCases.map(\.toolbarIdentifier) + [.flexibleSpace]
    }

    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    nonisolated func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    nonisolated func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        MainActor.assumeIsolated {
            guard let tab = SettingsTab.allCases.first(where: { $0.toolbarIdentifier == identifier }) else { return nil }
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.target = self
            item.action = #selector(toolbarItemClicked(_:))
            return item
        }
    }
}

extension SettingsTab {
    nonisolated var toolbarIdentifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier("settings." + rawValue) }
}

/// Every page at once, stacked from the top; only the selected one is visible and takes
/// input. Each reports its natural height so the window can fit the selected one.
private struct SettingsTabsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: SettingsTabState

    var body: some View {
        // The stack is as tall as the tallest page; pinning it to the window's height from
        // the top keeps a shorter page from being centered up under the toolbar.
        GeometryReader { window in
            ZStack(alignment: .top) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    let shown = tab == state.selected
                    tab.pane(settings)
                        .background(GeometryReader { page in
                            Color.clear.preference(key: PageHeights.self, value: [tab: page.size.height])
                        })
                        .opacity(shown ? 1 : 0)
                        .zIndex(shown ? 1 : 0) // clicks land on the page you see
                        .allowsHitTesting(shown)
                        .disabled(!shown && tab != state.leaving)
                        .accessibilityHidden(!shown)
                }
            }
            .frame(width: window.size.width, height: window.size.height, alignment: .top)
            .clipped()
        }
        .onPreferenceChange(PageHeights.self) { heights in
            if heights != state.heights { state.heights = heights }
        }
    }
}

private struct PageHeights: PreferenceKey {
    static let defaultValue: [SettingsTab: CGFloat] = [:]
    static func reduce(value: inout [SettingsTab: CGFloat], nextValue: () -> [SettingsTab: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}
