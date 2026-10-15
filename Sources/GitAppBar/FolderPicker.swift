import AppKit

extension Notification.Name {
    /// A system modal window (open panel…) is about to run. `runModal()` forces
    /// it to the modal level, below our status-bar-level panel, so the panel
    /// lowers itself until `gabModalDidEnd`.
    static let gabModalWillBegin = Notification.Name("gab.modalWillBegin")
    static let gabModalDidEnd = Notification.Name("gab.modalDidEnd")
}

@MainActor
enum FolderPicker {
    /// Hook for GAB_PICKER_TEST: runs while the chooser is on screen.
    static var whileOpen: ((NSOpenPanel) -> Void)?

    /// Shows a native folder chooser above the menu bar panel. Returns chosen paths.
    static func pickFolders() -> [String] {
        let chooser = NSOpenPanel()
        chooser.canChooseDirectories = true
        chooser.canChooseFiles = false
        chooser.allowsMultipleSelection = true
        chooser.canCreateDirectories = false
        chooser.prompt = tr("Choose", "Pilih")
        chooser.message = tr("Choose folders that contain git repositories. Subfolders are scanned automatically.",
                             "Pilih folder yang berisi repo git. Subfolder akan di-scan otomatis.")
        chooser.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        NotificationCenter.default.post(name: .gabModalWillBegin, object: nil)
        defer { NotificationCenter.default.post(name: .gabModalDidEnd, object: nil) }

        if let hook = whileOpen {
            let timer = Timer(timeInterval: 0.5, repeats: false) { _ in
                MainActor.assumeIsolated { hook(chooser) }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
        }

        NSApp.activate()
        guard chooser.runModal() == .OK else { return [] }
        return chooser.urls.map(\.path)
    }
}
