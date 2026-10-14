import Foundation

public struct FileChange: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case ordinary
        case renamed(from: String)
        case unmerged
        case untracked
    }

    public let path: String
    public let index: Character
    public let worktree: Character
    public let kind: Kind

    public var id: String { path }

    public init(path: String, index: Character, worktree: Character, kind: Kind) {
        self.path = path
        self.index = index
        self.worktree = worktree
        self.kind = kind
    }

    public var isStaged: Bool {
        switch kind {
        case .untracked, .unmerged: return false
        default: return index != "."
        }
    }

    /// Single letter shown in the UI, VS Code style.
    public var badge: String {
        switch kind {
        case .untracked: return "U"
        case .unmerged: return "!"
        case .renamed: return "R"
        case .ordinary:
            let c = worktree != "." ? worktree : index
            return String(c)
        }
    }
}

public struct RepoStatus: Equatable, Sendable {
    public var oid: String?
    public var branch: String?
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var changes: [FileChange]

    public init(oid: String? = nil, branch: String? = nil, upstream: String? = nil,
                ahead: Int = 0, behind: Int = 0, changes: [FileChange] = []) {
        self.oid = oid
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.changes = changes
    }

    public var isDetached: Bool { branch == nil }
    public var isClean: Bool { changes.isEmpty }
}
