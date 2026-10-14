import Foundation

/// Parses `git status --porcelain=v2 --branch -z --untracked-files=all`.
/// Format: https://git-scm.com/docs/git-status#_porcelain_format_version_2
public enum GitStatusParser {
    public static func parse(_ output: String) -> RepoStatus {
        var status = RepoStatus()
        var entries = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]

        while let entry = entries.popFirst() {
            if entry.hasPrefix("# ") {
                parseHeader(entry, into: &status)
                continue
            }
            guard let type = entry.first else { continue }
            switch type {
            case "1":
                let f = entry.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard f.count == 9 else { continue }
                let xy = Array(f[1])
                status.changes.append(FileChange(path: String(f[8]), index: xy[0], worktree: xy[1], kind: .ordinary))
            case "2":
                let f = entry.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard f.count == 10 else { continue }
                let xy = Array(f[1])
                let original = entries.popFirst() ?? ""
                status.changes.append(FileChange(path: String(f[9]), index: xy[0], worktree: xy[1], kind: .renamed(from: original)))
            case "u":
                let f = entry.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard f.count == 11 else { continue }
                let xy = Array(f[1])
                status.changes.append(FileChange(path: String(f[10]), index: xy[0], worktree: xy[1], kind: .unmerged))
            case "?":
                status.changes.append(FileChange(path: String(entry.dropFirst(2)), index: "?", worktree: "?", kind: .untracked))
            default:
                continue
            }
        }
        return status
    }

    private static func parseHeader(_ line: String, into status: inout RepoStatus) {
        let parts = line.split(separator: " ")
        guard parts.count >= 3 else { return }
        let value = parts[2...].joined(separator: " ")
        switch parts[1] {
        case "branch.oid":
            status.oid = value == "(initial)" ? nil : value
        case "branch.head":
            status.branch = value == "(detached)" ? nil : value
        case "branch.upstream":
            status.upstream = value
        case "branch.ab":
            guard parts.count == 4 else { return }
            status.ahead = Int(parts[2].dropFirst()) ?? 0
            status.behind = Int(parts[3].dropFirst()) ?? 0
        default:
            break
        }
    }
}
