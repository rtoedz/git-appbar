import AppKit

@MainActor
enum FolderPicker {
    /// Shows a native folder chooser above the menu bar panel. Returns chosen paths.
    static func pickFolders() -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = tr("Choose", "Pilih")
        panel.message = tr("Choose folders that contain git repositories. Subfolders are scanned automatically.",
                           "Pilih folder yang berisi repo git. Subfolder akan di-scan otomatis.")
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        // The repo panel sits at .statusBar level; keep the chooser above it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map(\.path)
    }
}
