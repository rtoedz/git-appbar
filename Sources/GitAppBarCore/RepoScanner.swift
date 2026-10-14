import Foundation

/// Finds git repositories under one or more root folders.
/// Stops descending once a repo root is found (nested repos/submodules are
/// handled by git itself) and skips heavy dependency/build folders.
public enum RepoScanner {
    public static let skippedFolders: Set<String> = [
        "node_modules", ".build", "build", "dist", "Pods", "DerivedData", "vendor",
        ".next", ".nuxt", ".dart_tool", "venv", ".venv", "__pycache__", "target",
        "Library", ".Trash"
    ]

    public static func scan(roots: [URL], maxDepth: Int = 4) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()
        for root in roots {
            walk(root.standardizedFileURL.resolvingSymlinksInPath(), depth: 0, maxDepth: maxDepth, found: &found, seen: &seen)
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public static func isRepository(_ dir: URL) -> Bool {
        // `.git` is a directory for normal repos, a file for worktrees/submodules.
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path)
    }

    private static func walk(_ dir: URL, depth: Int, maxDepth: Int, found: inout [URL], seen: inout Set<String>) {
        if isRepository(dir) {
            if seen.insert(dir.path).inserted { found.append(dir) }
            return
        }
        guard depth < maxDepth else { return }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return }

        for child in children {
            guard let values = try? child.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true,
                  values.isSymbolicLink != true,
                  !skippedFolders.contains(child.lastPathComponent)
            else { continue }
            walk(child, depth: depth + 1, maxDepth: maxDepth, found: &found, seen: &seen)
        }
    }
}
