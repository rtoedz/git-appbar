import AppKit
import GitAppBarCore

extension Notification.Name {
    /// Posted when the panel should get out of the way (e.g. a file opened in the editor).
    static let gabHidePanel = Notification.Name("gab.hidePanel")
}

@MainActor
enum EditorOpener {
    /// Entry point for every "click a file name" in the panel: checks the file
    /// still exists, asks for confirmation (unless turned off), then opens it.
    /// `fromHistory` adds a note that the working-tree version is opened, not
    /// the version from the selected commit.
    static func requestOpen(repo: URL, path: String, prefs: Preferences, store: RepoStore, fromHistory: Bool = false) {
        let file = repo.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: file.path) else {
            store.show(tr("\(path) no longer exists in the working tree (deleted or renamed after this commit).",
                          "\(path) sudah tidak ada di working tree (dihapus atau di-rename setelah commit ini)."),
                       isError: true)
            return
        }
        if prefs.confirmBeforeOpening {
            switch confirm(file: file, path: path, command: prefs.editorCommand, fromHistory: fromHistory) {
            case .cancel:
                return
            case .open(let dontAskAgain):
                if dontAskAgain { prefs.confirmBeforeOpening = false }
            }
        }
        open(file, command: prefs.editorCommand)
    }

    private enum Choice { case open(dontAskAgain: Bool), cancel }

    private static func confirm(file: URL, path: String, command: String, fromHistory: Bool) -> Choice {
        let alert = makeAlert(file: file, path: path, command: command, fromHistory: fromHistory)
        NSApp.activate()
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return .cancel }
        return .open(dontAskAgain: alert.suppressionButton?.state == .on)
    }

    static func makeAlert(file: URL, path: String, command: String, fromHistory: Bool) -> NSAlert {
        let editor = editorName(for: command)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = tr("Open in \(editor)?", "Buka di \(editor)?")
        var info = tr("\((path as NSString).lastPathComponent) will be opened with:",
                      "\((path as NSString).lastPathComponent) akan dibuka dengan:")
        info += "\n\(command.isEmpty ? "open" : command) \((file.path as NSString).abbreviatingWithTildeInPath)"
        if fromHistory {
            info += "\n\n" + tr("This opens the current version in your working tree, not the version from this commit.",
                                "Yang dibuka adalah versi sekarang di working tree, bukan versi dari commit ini.")
        }
        alert.informativeText = info
        alert.addButton(withTitle: tr("Open", "Buka"))
        alert.addButton(withTitle: tr("Cancel", "Batal"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = tr("Don't ask again", "Jangan tanya lagi")
        // The repo panel floats at status-bar level; keep the alert above it.
        alert.layout()
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        return alert
    }

    /// Friendly name for the configured CLI: `code -g` → "VS Code".
    static func editorName(for command: String) -> String {
        let parts = command.split(separator: " ").map(String.init)
        guard let first = parts.first else { return tr("the default app", "aplikasi default") }
        if first == "open", let i = parts.firstIndex(of: "-a"), i + 1 < parts.count {
            return parts[(i + 1)...].joined(separator: " ")
        }
        switch (first as NSString).lastPathComponent {
        case "code": return "VS Code"
        case "code-insiders": return "VS Code Insiders"
        case "cursor": return "Cursor"
        case "zed": return "Zed"
        case "subl": return "Sublime Text"
        case "windsurf": return "Windsurf"
        case "idea": return "IntelliJ IDEA"
        case "goland": return "GoLand"
        case "nvim", "vim": return "Vim"
        default: return first
        }
    }

    /// Opens `file` with the configured editor CLI (default `code -g`), falling
    /// back to the system default app when the CLI is missing or fails.
    static func open(_ file: URL, line: Int? = nil, command: String) {
        NotificationCenter.default.post(name: .gabHidePanel, object: nil)

        let parts = command.split(separator: " ").map(String.init)
        guard !parts.isEmpty else {
            NSWorkspace.shared.open(file)
            return
        }
        var target = file.path
        if let line { target += ":\(line)" }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = parts + [target]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = GitRunner.searchPath
        process.environment = env
        process.terminationHandler = { p in
            guard p.terminationStatus != 0 else { return }
            DispatchQueue.main.async { NSWorkspace.shared.open(file) }
        }
        do {
            try process.run()
        } catch {
            NSWorkspace.shared.open(file)
        }
    }
}
