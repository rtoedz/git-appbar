import AppKit
import SwiftUI

/// Borderless panels refuse key status by default; the commit box needs typing.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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

        let host = NSHostingView(rootView: PanelRootView().environment(preferences).environment(store))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
    }

    var isVisible: Bool { panel.isVisible }

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
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        Task { await store.refreshStatuses() }
    }

    func hide() {
        panel.orderOut(nil)
        removeMonitors()
    }

    private func installMonitors() {
        removeMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc closes the panel only when it comes from the panel itself, not the folder chooser.
            if event.keyCode == 53, event.window === self?.panel {
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
        keyMonitor = nil
    }
}
