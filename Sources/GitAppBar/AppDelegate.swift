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
        if ProcessInfo.processInfo.environment["GAB_ESC_TEST"] == "1" {
            runEscapeTest()
        }
    }

    /// Opens the panel via the status item, then sends Esc; prints the outcome and quits.
    private func runEscapeTest() {
        Task { @MainActor in
            var failures = 0
            for round in 1...3 {
                statusItem.button?.performClick(nil)
                try? await Task.sleep(for: .milliseconds(600))
                let opened = panel.isVisible
                let key = panel.isKey
                panel.debugSendEscape()
                try? await Task.sleep(for: .milliseconds(300))
                let closed = !panel.isVisible
                if !(opened && key && closed) { failures += 1 }
                print("esc-test round \(round): opened=\(opened) key=\(key) closedByEsc=\(closed)")
            }
            print(failures == 0 ? "esc-test: PASS" : "esc-test: FAIL")
            NSApp.terminate(nil)
        }
    }

    @objc private func togglePanel() {
        panel.toggle(on: statusItem.button?.window?.screen)
    }
}
