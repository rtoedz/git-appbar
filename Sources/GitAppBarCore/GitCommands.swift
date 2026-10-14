import Foundation

extension GitRunner {
    /// Upstream of the current branch (e.g. `origin/dev`), or nil.
    public func upstream(of repo: URL) async -> String? {
        let out = try? await run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: repo)
        let value = out?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    /// Recent history of HEAD plus its upstream, so incoming commits show up too.
    /// One page of history. `skip` is applied after topo-ordering the full walk,
    /// so consecutive pages line up as long as the refs don't move in between.
    public func log(of repo: URL, limit: Int = 100, skip: Int = 0) async throws -> [CommitEntry] {
        var args = ["log", "--topo-order", "-n", String(limit), "--skip", String(skip),
                    "--format=\(GitLogParser.format)", "HEAD"]
        if let up = await upstream(of: repo) { args.append(up) }
        args.append("--")
        return GitLogParser.parse(try await run(args, in: repo))
    }

    public func commitFiles(_ hash: String, in repo: URL) async throws -> [CommitFile] {
        let base = ["show", "--format=", "-M", "-z", "--diff-merges=first-parent"]
        async let names = run(base + ["--name-status", hash], in: repo)
        async let stats = run(base + ["--numstat", hash], in: repo)
        return CommitFilesParser.parse(nameStatus: try await names, numstat: try await stats)
    }

    public func commitMessage(_ hash: String, in repo: URL) async throws -> String {
        try await run(["show", "-s", "--format=%B", hash], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func branches(of repo: URL) async throws -> [Branch] {
        BranchParser.parse(try await run(
            ["for-each-ref", "--format=\(BranchParser.format)", "refs/heads", "refs/remotes"], in: repo
        ))
    }

    /// Switches branch. A remote branch checks out the matching local branch,
    /// creating a tracking branch when none exists. With `stashFirst`, local
    /// changes (incl. untracked) are stashed before switching.
    @discardableResult
    public func switchBranch(_ branch: Branch, in repo: URL, localBranches: [Branch], stashFirst: Bool) async throws -> String {
        let target = branch.localName
        if stashFirst {
            _ = try await run(["stash", "push", "-u", "-m", "git-appbar: auto-stash sebelum pindah ke \(target)"], in: repo)
        }
        let hasLocal = localBranches.contains { !$0.isRemote && $0.name == target }
        if branch.isRemote && !hasLocal {
            _ = try await run(["switch", "--track", branch.name], in: repo)
        } else {
            _ = try await run(["switch", target], in: repo)
        }
        return target
    }
}
