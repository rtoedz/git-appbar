import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: PanelController!
    let preferences = Preferences()
    let store = RepoStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if DebugRender.runIfRequested(preferences: preferences, store: store) { return }
        if DebugActionTest.runIfRequested(store: store) { return }

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
        if ProcessInfo.processInfo.environment["GAB_PICKER_TEST"] == "1" {
            runPickerTest()
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
            // With the open-in-editor dialog up, Esc closes only the dialog.
            statusItem.button?.performClick(nil)
            try? await Task.sleep(for: .milliseconds(600))
            store.pendingOpen = PendingOpen(file: URL(fileURLWithPath: "/tmp/x"), path: "x", command: "code -g", fromHistory: false)
            panel.debugSendEscape()
            try? await Task.sleep(for: .milliseconds(300))
            let dialogClosed = store.pendingOpen == nil
            let panelStillOpen = panel.isVisible
            print("esc-test dialog: dialogClosed=\(dialogClosed) panelStillOpen=\(panelStillOpen)")
            if !(dialogClosed && panelStillOpen) { failures += 1 }
            panel.debugSendEscape()
            try? await Task.sleep(for: .milliseconds(300))
            if panel.isVisible { failures += 1 }

            print(failures == 0 ? "esc-test: PASS" : "esc-test: FAIL")
            NSApp.terminate(nil)
        }
    }

    /// Opens the panel, opens the folder chooser, and checks *while it is on
    /// screen* that it is in front of the panel; then cancels it.
    private func runPickerTest() {
        Task { @MainActor in
            statusItem.button?.performClick(nil)
            try? await Task.sleep(for: .milliseconds(600))
            var inFront = false
            var levels = ""
            FolderPicker.whileOpen = { [panel] chooser in
                let order = NSWindow.windowNumbers(options: []) ?? []   // front to back
                let chooserIndex = order.firstIndex(of: NSNumber(value: chooser.windowNumber))
                let panelIndex = order.firstIndex(of: NSNumber(value: panel!.windowNumber))
                inFront = chooser.isVisible && chooserIndex != nil && panelIndex != nil && chooserIndex! < panelIndex!
                levels = "chooser=\(chooser.level.rawValue) panel=\(panel!.level.rawValue) order=\(String(describing: chooserIndex))<\(String(describing: panelIndex))"
                NSApp.abortModal()
            }
            _ = FolderPicker.pickFolders()
            FolderPicker.whileOpen = nil
            try? await Task.sleep(for: .milliseconds(200))
            let restored = panel.level == .statusBar && panel.isVisible
            print("picker-test: \(levels) chooserInFront=\(inFront) panelRestored=\(restored)")
            print(inFront && restored ? "picker-test: PASS" : "picker-test: FAIL")
            NSApp.terminate(nil)
        }
    }

    @objc private func togglePanel() {
        panel.toggle(on: statusItem.button?.window?.screen)
    }
}
