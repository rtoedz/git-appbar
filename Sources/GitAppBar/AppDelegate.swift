import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: PanelController!
    let preferences = Preferences()
    let store = RepoStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if DebugRender.runIfRequested(preferences: preferences, store: store) { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Git AppBar")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel)
        }

        panel = PanelController(preferences: preferences, store: store)

        if ProcessInfo.processInfo.environment["GAB_OPEN_ON_LAUNCH"] == "1" {
            togglePanel()
        }
    }

    @objc private func togglePanel() {
        panel.toggle(on: statusItem.button?.window?.screen)
    }
}
