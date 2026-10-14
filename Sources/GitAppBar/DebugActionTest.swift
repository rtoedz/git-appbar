import AppKit
import GitAppBarCore

/// `GAB_ACTION_TEST=/tmp/dir` builds a bare remote + two clones in that
/// directory and drives commit / push / fetch / pull / stash through RepoStore
/// (the same calls the buttons make), checking guards and results.
@MainActor
enum DebugActionTest {
    static func runIfRequested(store: RepoStore) -> Bool {
        guard let path = ProcessInfo.processInfo.environment["GAB_ACTION_TEST"] else { return false }
        Task { @MainActor in
            let ok = await run(root: URL(fileURLWithPath: path), store: store)
            print(ok ? "action-test: PASS" : "action-test: FAIL")
            exit(ok ? 0 : 1)
        }
        return true
    }

    private static func run(root: URL, store: RepoStore) async -> Bool {
        let git = GitRunner()
        let fm = FileManager.default
        try? fm.removeItem(at: root)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let remote = root.appendingPathComponent("remote.git")
        let a = root.appendingPathComponent("alpha")
        let b = root.appendingPathComponent("beta")
        var failures = 0
        func check(_ cond: Bool, _ what: String) {
            print("  \(cond ? "ok " : "FAIL") \(what)")
            if !cond { failures += 1 }
        }
        func write(_ text: String, _ name: String, _ repo: URL) {
            try? text.write(to: repo.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        do {
            let id = ["-c", "user.name=Tester", "-c", "user.email=t@x.com"]
            _ = try await git.run(["init", "-q", "--bare", "-b", "main", remote.path], in: root)
            for repo in [a, b] {
                _ = try await git.run(["clone", "-q", remote.path, repo.path], in: root)
                _ = try await git.run(["config", "user.name", "Tester"], in: repo)
                _ = try await git.run(["config", "user.email", "t@x.com"], in: repo)
            }
            write("hello\n", "readme.md", a)
            _ = try await git.run(["add", "."], in: a)
            _ = try await git.run(id + ["commit", "-qm", "init"], in: a)
            _ = try await git.run(["push", "-q", "-u", "origin", "main"], in: a)
            _ = try await git.run(["pull", "-q"], in: b)
        } catch {
            print("setup failed: \(error.localizedDescription)")
            return false
        }

        func select(_ repo: URL) async {
            store.rescan(roots: [root], depth: 2)
            for _ in 0..<50 where store.repos.count < 2 || store.repos.contains(where: { $0.status == nil }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            store.selectedID = repo.resolvingSymlinksInPath().path
            if store.selected == nil { store.selectedID = store.repos.first { $0.name == repo.lastPathComponent }?.id }
            try? await Task.sleep(for: .milliseconds(400))
        }
        func status() -> RepoStatus? { store.selected?.status }

        print("action-test: alpha commit with an excluded file, then Commit & Push")
        write("changed\n", "readme.md", a)
        write("new\n", "new.txt", a)
        write("secret\n", "local.env", a)
        await select(a)
        check(status()?.changes.count == 3, "3 changes visible")
        store.toggleIncluded("local.env")
        store.commitMessage = ""
        await store.commit(andPush: false)
        check(store.banner?.isError == true, "empty message refused")
        store.commitMessage = "feat: two files"
        await store.commit(andPush: true)
        check(store.banner?.isError == false, "commit & push ok: \(store.banner?.text ?? "-")")
        check(status()?.changes.map(\.path) == ["local.env"], "excluded file left uncommitted")
        check(status()?.ahead == 0, "nothing left to push")
        check(store.commitMessage.isEmpty, "draft cleared after commit")

        print("action-test: beta fetch + pull")
        await select(b)
        await store.fetch()
        check(status()?.behind == 1, "fetch shows 1 incoming (\(store.banner?.text ?? "-"))")
        await store.pull()
        check(status()?.behind == 0, "pull fast-forwarded")
        check(fm.fileExists(atPath: b.appendingPathComponent("new.txt").path), "pulled file present")

        print("action-test: diverged branch guards")
        await select(a)
        write("a2\n", "a2.txt", a)
        await select(a)
        store.excludedPaths = ["local.env"]
        store.commitMessage = "feat: a2"
        await store.commit(andPush: true)
        await select(b)
        write("b2\n", "b2.txt", b)
        await select(b)
        store.commitMessage = "feat: b2"
        await store.commit(andPush: false)
        await store.fetch()
        check(status()?.ahead == 1 && status()?.behind == 1, "beta diverged (↑1 ↓1)")
        await store.push()
        check(store.banner?.isError == true, "push blocked while behind: \(store.banner?.text ?? "-")")
        await store.pull()
        check(store.banner?.isError == true, "pull --ff-only refuses divergence")
        let head = (try? await git.run(["log", "-1", "--format=%s"], in: b))?.trimmingCharacters(in: .whitespacesAndNewlines)
        check(head == "feat: b2", "local HEAD commit untouched (\(head ?? "-"))")

        print("action-test: stash / pop")
        write("dirty\n", "readme.md", b)
        await select(b)
        await store.stash(message: "wip")
        check(status()?.isClean == true, "stash cleaned working tree")
        check(store.stashes.count == 1, "stash listed")
        if let entry = store.stashes.first { await store.popStash(entry) }
        check(status()?.changes.map(\.path) == ["readme.md"], "pop restored change")
        check(store.stashes.isEmpty, "stash removed after pop")

        print("action-test: fetch all")
        await store.fetchAll()
        check(store.banner?.isError == false, "fetch all ok: \(store.banner?.text ?? "-")")

        try? fm.removeItem(at: root)
        return failures == 0
    }
}
