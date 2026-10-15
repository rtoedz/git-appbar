import Foundation
import Observation

@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let opacity = "panel.opacity"
        static let blur = "panel.blur"
        static let rootFolders = "repos.rootFolders"
        static let legacyRootFolder = "repos.rootFolder"
        static let scanDepth = "repos.scanDepth"
        static let editorCommand = "editor.command"
        static let language = "app.language"
        static let confirmOpen = "editor.confirmOpen"
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

    /// Folders scanned for git repositories, stored with `~` abbreviated.
    var rootFolders: [String] {
        didSet { defaults.set(rootFolders, forKey: Key.rootFolders) }
    }

    /// How many folder levels below each root are searched for repos.
    var scanDepth: Int {
        didSet { defaults.set(scanDepth, forKey: Key.scanDepth) }
    }

    /// CLI used to open files, e.g. `code -g`.
    var editorCommand: String {
        didSet { defaults.set(editorCommand, forKey: Key.editorCommand) }
    }

    /// UI language; English unless the user picks another one.
    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Key.language)
            Localizer.shared.language = language
        }
    }

    /// Ask before opening a clicked file in the editor.
    var confirmBeforeOpening: Bool {
        didSet { defaults.set(confirmBeforeOpening, forKey: Key.confirmOpen) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedLanguage = defaults.string(forKey: Key.language).flatMap(AppLanguage.init(rawValue:)) ?? .english
        language = savedLanguage
        Localizer.shared.language = savedLanguage
        opacity = defaults.object(forKey: Key.opacity) as? Double ?? 0.82
        blur = defaults.object(forKey: Key.blur) as? Bool ?? true
        if let folders = defaults.stringArray(forKey: Key.rootFolders) {
            rootFolders = folders
        } else if let legacy = defaults.string(forKey: Key.legacyRootFolder) {
            rootFolders = [legacy]
        } else {
            rootFolders = []
        }
        scanDepth = defaults.object(forKey: Key.scanDepth) as? Int ?? 4
        editorCommand = defaults.string(forKey: Key.editorCommand) ?? "code -g"
        confirmBeforeOpening = defaults.object(forKey: Key.confirmOpen) as? Bool ?? true
    }

    var rootFolderURLs: [URL] {
        rootFolders.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    func addFolders(_ paths: [String]) {
        let normalized = paths.map { ($0 as NSString).abbreviatingWithTildeInPath }
        let new = normalized.filter { !rootFolders.contains($0) }
        if !new.isEmpty { rootFolders.append(contentsOf: new) }
    }

    func removeFolder(_ path: String) {
        rootFolders.removeAll { $0 == path }
    }
}
