import Foundation

public struct StashEntry: Identifiable, Equatable, Sendable {
    /// `stash@{0}`
    public let ref: String
    public let message: String
    public let date: Date
    public var id: String { ref }
}

public enum StashParser {
    public static let format = "%gd%x1f%gs%x1f%ct"

    public static func parse(_ output: String) -> [StashEntry] {
        output.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count >= 3, f[0].hasPrefix("stash@{") else { return nil }
            return StashEntry(ref: f[0], message: f[1], date: Date(timeIntervalSince1970: TimeInterval(f[2]) ?? 0))
        }
    }
}

public enum GitActionError: LocalizedError, Equatable {
    case emptyMessage
    case nothingSelected
    case unresolvedConflicts
    case noUpstreamToPull
    case behindRemote(Int)
    case noRemote
    case detachedHead

    public var errorDescription: String? {
        switch self {
        case .emptyMessage: return "Write a commit message first."
        case .nothingSelected: return "Select at least 1 file to commit."
        case .unresolvedConflicts: return "There are unresolved merge conflicts."
        case .noUpstreamToPull: return "This branch has no upstream to pull from."
        case .behindRemote(let n): return "The remote has \(n) commit(s) you haven't pulled. Pull before pushing."
        case .noRemote: return "This repository has no remote."
        case .detachedHead: return "HEAD is detached. Switch to a branch first."
        }
    }
}

extension GitRunner {
    // MARK: Commit

    /// Commits exactly `changes` (staging them first, including untracked and
    /// deleted files). Anything else that happened to be staged stays staged
    /// but is not part of this commit.
    @discardableResult
    public func commit(_ changes: [FileChange], message: String, in repo: URL) async throws -> String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GitActionError.emptyMessage }
        guard !changes.isEmpty else { throw GitActionError.nothingSelected }
        guard !changes.contains(where: { $0.kind == .unmerged }) else { throw GitActionError.unresolvedConflicts }

        var paths: [String] = []
        for change in changes {
            paths.append(change.path)
            if case .renamed(let from) = change.kind { paths.append(from) }
        }
        // Only stage what still has working-tree changes. Fully staged entries
        // (e.g. a staged rename or delete) may no longer exist on disk, and
        // `git add` on such a path fails; `commit --only` still picks them up.
        let toStage = changes.filter { $0.kind == .untracked || $0.worktree != "." }.map(\.path)
        if !toStage.isEmpty {
            _ = try await run(["add", "-A", "--"] + toStage, in: repo)
        }
        // Path-limited commit (`--only`): ignores unrelated staged files.
        _ = try await run(["commit", "-m", text, "--only", "--"] + paths, in: repo)
        return try await run(["rev-parse", "HEAD"], in: repo).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Remote

    public func fetch(_ repo: URL) async throws {
        _ = try await run(["fetch", "--prune"], in: repo, timeout: Self.networkTimeout)
    }

    /// Fast-forward only: never creates a merge or rebases behind your back.
    public func pull(_ repo: URL, status: RepoStatus) async throws {
        guard status.branch != nil else { throw GitActionError.detachedHead }
        guard status.upstream != nil else { throw GitActionError.noUpstreamToPull }
        _ = try await run(["pull", "--ff-only"], in: repo, timeout: Self.networkTimeout)
    }

    /// Pushes the current branch. Refuses when the remote is ahead (no force push).
    /// A branch without upstream is published to `origin` and tracked.
    public func push(_ repo: URL, status: RepoStatus) async throws {
        guard let branch = status.branch else { throw GitActionError.detachedHead }
        if status.behind > 0 { throw GitActionError.behindRemote(status.behind) }
        if status.upstream != nil {
            _ = try await run(["push"], in: repo, timeout: Self.networkTimeout)
            return
        }
        let remotes = try await run(["remote"], in: repo).split(separator: "\n").map(String.init)
        guard let remote = remotes.contains("origin") ? "origin" : remotes.first else { throw GitActionError.noRemote }
        _ = try await run(["push", "-u", remote, branch], in: repo, timeout: Self.networkTimeout)
    }

    // MARK: Stash

    public func stashes(_ repo: URL) async throws -> [StashEntry] {
        StashParser.parse(try await run(["stash", "list", "--format=\(StashParser.format)"], in: repo))
    }

    public func stashPush(_ repo: URL, message: String?) async throws {
        var args = ["stash", "push", "--include-untracked"]
        if let message, !message.isEmpty { args += ["-m", message] }
        _ = try await run(args, in: repo)
    }

    /// Applies and removes the stash. On conflict git keeps the stash, so nothing is lost.
    public func stashPop(_ repo: URL, ref: String = "stash@{0}") async throws {
        _ = try await run(["stash", "pop", "--index", ref], in: repo)
    }

    public func stashApply(_ repo: URL, ref: String) async throws {
        _ = try await run(["stash", "apply", "--index", ref], in: repo)
    }
}
