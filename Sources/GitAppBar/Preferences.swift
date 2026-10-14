import Foundation
import Observation

@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let opacity = "panel.opacity"
        static let blur = "panel.blur"
        static let rootFolder = "repos.rootFolder"
        static let editorCommand = "editor.command"
    }

    private let defaults: UserDefaults

    /// Background opacity of the panel, 0.3 ... 1.0.
    var opacity: Double {
        didSet { defaults.set(opacity, forKey: Key.opacity) }
    }

    /// Frosted-glass blur of whatever is behind the panel.
    var blur: Bool {
        didSet { defaults.set(blur, forKey: Key.blur) }
    }

    /// Folder scanned for git repositories (M1).
    var rootFolder: String {
        didSet { defaults.set(rootFolder, forKey: Key.rootFolder) }
    }

    /// CLI used to open files, e.g. `code -g` (M1).
    var editorCommand: String {
        didSet { defaults.set(editorCommand, forKey: Key.editorCommand) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        opacity = defaults.object(forKey: Key.opacity) as? Double ?? 0.82
        blur = defaults.object(forKey: Key.blur) as? Bool ?? true
        rootFolder = defaults.string(forKey: Key.rootFolder) ?? "~/Project"
        editorCommand = defaults.string(forKey: Key.editorCommand) ?? "code -g"
    }
}
