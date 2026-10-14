import AppKit
import GitAppBarCore

extension Notification.Name {
    /// Posted when the panel should get out of the way (e.g. a file opened in the editor).
    static let gabHidePanel = Notification.Name("gab.hidePanel")
}

@MainActor
enum EditorOpener {
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
