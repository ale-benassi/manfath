import AppKit
import SwiftUI
import Observation
import KeyboardShortcuts

@MainActor @Observable
final class PopoverVisibility {
    var isVisible = false
}

/// Owns the `NSStatusItem` in the menu bar and the `NSPopover` that
/// hosts the SwiftUI `RootView`. The badge updates reactively via
/// `withObservationTracking` — no polling.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {

    private let store: PortStore
    private let tunnelStore: TunnelStore
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let visibility = PopoverVisibility()

    init(store: PortStore, tunnelStore: TunnelStore) {
        self.store = store
        self.tunnelStore = tunnelStore
        self.statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        self.popover = NSPopover()
        super.init()

        configurePopover()
        configureStatusItem()
        trackBadge()
        registerGlobalHotkey()
    }

    // MARK: - Global hotkey

    private func registerGlobalHotkey() {
        KeyboardShortcuts.onKeyUp(for: .togglePopover) { [weak self] in
            self?.togglePopover(nil)
        }
    }

    // MARK: - Popover

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: RootView(store: store)
                .environment(tunnelStore)
                .environment(store.settings)
                .environment(visibility)
        )
    }

    func popoverWillShow(_ notification: Notification) {
        visibility.isVisible = true
    }

    func popoverDidClose(_ notification: Notification) {
        visibility.isVisible = false
    }

    func setAppearance(_ appearance: NSAppearance) {
        // Keep the popover material and its SwiftUI content in the same appearance.
        popover.appearance = appearance
    }

    // MARK: - Status item

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        // Custom mark sized for the menu bar — matches the brand
        // glyph from the website's nav. Renders monochrome and
        // auto-tints to whatever the menu bar appearance is.
        let icon = NSImage(named: "MenuBarIcon") ?? NSImage(
            systemSymbolName: "network",
            accessibilityDescription: "Manfath"
        )
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        button.image = icon
        button.imagePosition = .imageLeading
        // Receive both clicks; we discriminate in the handler.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleClick(_:))
        button.target = self
    }

    @objc private func handleClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) == true) {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let prefs = NSMenuItem(
            title: String(localized: "menu.preferences"),
            action: #selector(AppDelegate.openSettings(_:)),
            keyEquivalent: ","
        )
        prefs.target = nil   // route via responder chain
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: "menu.quitManfath"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        // Attach, pop, then detach so the next left-click still routes
        // to handleClick(_:) instead of auto-showing the menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button else { return }
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        // Popovers spawn in an unfocused window by default; bring it
        // forward so the search field can accept keystrokes immediately.
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Badge

    /// Re-arms `withObservationTracking` on every change. The body reads
    /// `filteredPorts`, which transitively subscribes to `ports`,
    /// `searchText`, `sortMode`, and settings. Whenever any of those
    /// change, `onChange` fires and we re-track.
    private func trackBadge() {
        withObservationTracking {
            let mode = store.settings.badgeMode
            let count = mode == .hidden ? 0 : store.filteredPorts.count
            updateBadge(count: count, mode: mode)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.trackBadge()
            }
        }
    }

    private func updateBadge(count: Int, mode: BadgeMode) {
        guard let button = statusItem.button else { return }
        let title: String
        switch mode {
        case .count:
            title = count > 0 ? " \(count)" : ""
        case .dot:
            title = count > 0 ? " •" : ""
        case .hidden:
            title = ""
        }
        if button.title != title { button.title = title }
    }
}
