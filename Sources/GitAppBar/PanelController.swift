import AppKit
import SwiftUI

/// Borderless panels refuse key status by default; the commit box needs typing.
private final class KeyablePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Esc reaches here through the responder chain when nothing inside
    /// (a text field, a popover) handled it first.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class PanelController {
    private let panel: KeyablePanel
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?

    private let sideInset: CGFloat = 8
    private let topGap: CGFloat = 4
    private let maxHeight: CGFloat = 860

    private let store: RepoStore

    init(preferences: Preferences, store: RepoStore) {
        self.store = store
        panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        // A non-activating panel can take keyboard focus without pulling our
        // app to the front; make sure it always does when shown.
        panel.becomesKeyOnlyIfNeeded = false

        let host = NSHostingView(rootView: PanelRootView().environment(preferences).environment(store))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host

        panel.onCancel = { [weak self] in self?.hide() }

        NotificationCenter.default.addObserver(forName: .gabHidePanel, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        // Step below system modals (folder chooser) while they run, then come back.
        NotificationCenter.default.addObserver(forName: .gabModalWillBegin, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.level = .normal }
        }
        NotificationCenter.default.addObserver(forName: .gabModalDidEnd, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.level = .statusBar
                if self.panel.isVisible { self.panel.makeKey() }
            }
        }
    }

    var isVisible: Bool { panel.isVisible }
    var windowNumber: Int { panel.windowNumber }
    var level: NSWindow.Level { panel.level }
    var isKey: Bool { panel.isKeyWindow }

    func toggle(on screen: NSScreen?) {
        isVisible ? hide() : show(on: screen)
    }

    func show(on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let height = min(visible.height - topGap - sideInset, maxHeight)
        let frame = NSRect(
            x: visible.minX + sideInset,
            y: visible.maxY - topGap - height,
            width: visible.width - sideInset * 2,
            height: height
        )
        panel.setFrame(frame, display: true)
        // macOS 14+ often ignores `activate(ignoringOtherApps:)`, which left key
        // presses (Esc) going to whatever app was in front. The panel itself
        // becoming key is what matters, so do that explicitly as well.
        NSApp.activate()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(panel.contentView)
        installMonitors()
        Task { await store.refreshStatuses() }
    }

    func hide() {
        store.pendingOpen = nil
        // Popovers (Preferences, branch picker) are child windows of the panel.
        panel.childWindows?.forEach { $0.orderOut(nil) }
        panel.orderOut(nil)
        removeMonitors()
    }

    private func installMonitors() {
        removeMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.handlesEscape(from: event.window) else { return event }
            // Esc first dismisses the in-panel confirmation, then the panel.
            if self.store.pendingOpen != nil {
                self.store.pendingOpen = nil
            } else {
                self.hide()
            }
            return nil
        }
    }

    /// Esc closes the whole panel from the panel or any of its popovers, but
    /// not from a separate modal window such as the folder chooser.
    private func handlesEscape(from window: NSWindow?) -> Bool {
        guard let window else { return panel.isVisible }
        if window is NSOpenPanel || window is NSSavePanel || NSApp.modalWindow != nil { return false }
        var current: NSWindow? = window
        while let w = current {
            if w === panel { return true }
            current = w.parent
        }
        // SwiftUI popovers are not always attached as child windows.
        return window.className.contains("Popover")
    }

    private func removeMonitors() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
        keyMonitor = nil
    }

    // MARK: Debug

    /// Sends a synthetic Esc through the app's event pipeline (same path as a
    /// real key press once the panel is key) for `GAB_ESC_TEST`.
    func debugSendEscape() {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ) else { return }
        NSApp.sendEvent(event)
    }
}
