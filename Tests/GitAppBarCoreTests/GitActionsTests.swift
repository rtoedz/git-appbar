import XCTest
@testable import GitAppBarCore

/// Integration tests against real repositories: a bare "remote" plus two clones.
final class GitActionsTests: XCTestCase {
    private var root: URL!
    private var remote: URL!
    private var a: URL!
    private var b: URL!
    private let git = GitRunner()
    private let ident = ["-c", "user.name=Tester", "-c", "user.email=t@x.com"]

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gab-act-\(UUID().uuidString)")
        remote = root.appendingPathComponent("remote.git")
        a = root.appendingPathComponent("a")
        b = root.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        _ = try await git.run(["init", "--bare", "-b", "main", remote.path], in: root)
        _ = try await git.run(["clone", "-q", remote.path, a.path], in: root)
        try configure(a)
        try write("hello\n", "readme.md", in: a)
        _ = try await git.run(ident + ["commit", "-qam", "init", "--allow-empty"], in: a)
        _ = try await git.run(["add", "."], in: a)
        _ = try await git.run(ident + ["commit", "-qm", "readme"], in: a)
        _ = try await git.run(["push", "-q", "-u", "origin", "main"], in: a)
        _ = try await git.run(["clone", "-q", remote.path, b.path], in: root)
        try configure(b)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func configure(_ repo: URL) throws {
        let config = repo.appendingPathComponent(".git/config")
        let extra = "\n[user]\n\tname = Tester\n\temail = t@x.com\n"
        let handle = try FileHandle(forWritingTo: config)
        handle.seekToEndOfFile()
        handle.write(Data(extra.utf8))
        try handle.close()
    }

    private func write(_ text: String, _ name: String, in repo: URL) throws {
        let url = repo.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: commit

    func testCommitOnlySelectedFilesIncludingUntrackedDeletedAndRenamed() async throws {
        try write("changed\n", "readme.md", in: a)
        try write("new\n", "src/new file.go", in: a)
        try write("keep out\n", "other.txt", in: a)
        _ = try await git.run(["add", "other.txt"], in: a) // staged but not selected

        let status = try await git.status(of: a)
        let selected = status.changes.filter { $0.path != "other.txt" }
        XCTAssertEqual(selected.count, 2)
        try await git.commit(selected, message: "  feat: pick files  ", in: a)

        let after = try await git.status(of: a)
        XCTAssertEqual(after.changes.map(\.path), ["other.txt"])
        XCTAssertTrue(after.changes[0].isStaged, "unselected staged file stays staged")
        let last = try await git.log(of: a, limit: 1)
        XCTAssertEqual(last.first?.subject, "feat: pick files")
        let files = try await git.commitFiles(last[0].hash, in: a)
        XCTAssertEqual(Set(files.map(\.path)), ["readme.md", "src/new file.go"])

        // deletion + rename
        try FileManager.default.removeItem(at: a.appendingPathComponent("readme.md"))
        _ = try await git.run(["mv", "src/new file.go", "src/renamed.go"], in: a)
        let s2 = try await git.status(of: a)
        try await git.commit(s2.changes.filter { $0.path != "other.txt" }, message: "chore: move", in: a)
        let s3 = try await git.status(of: a)
        XCTAssertEqual(s3.changes.map(\.path), ["other.txt"])
    }

    func testCommitGuards() async throws {
        try write("x\n", "readme.md", in: a)
        let status = try await git.status(of: a)
        do { try await git.commit(status.changes, message: "  ", in: a); XCTFail() }
        catch { XCTAssertEqual(error as? GitActionError, .emptyMessage) }
        do { try await git.commit([], message: "msg", in: a); XCTFail() }
        catch { XCTAssertEqual(error as? GitActionError, .nothingSelected) }
        let conflict = FileChange(path: "readme.md", index: "U", worktree: "U", kind: .unmerged)
        do { try await git.commit([conflict], message: "msg", in: a); XCTFail() }
        catch { XCTAssertEqual(error as? GitActionError, .unresolvedConflicts) }
    }

    // MARK: fetch / pull / push

    func testPushFetchPullFastForward() async throws {
        try write("from a\n", "a.txt", in: a)
        try await git.commit(try await git.status(of: a).changes, message: "feat: a", in: a)
        var sa = try await git.status(of: a)
        XCTAssertEqual(sa.ahead, 1)
        try await git.push(a, status: sa)
        sa = try await git.status(of: a)
        XCTAssertEqual(sa.ahead, 0)

        var sb = try await git.status(of: b)
        XCTAssertEqual(sb.behind, 0, "not fetched yet")
        try await git.fetch(b)
        sb = try await git.status(of: b)
        XCTAssertEqual(sb.behind, 1)
        try await git.pull(b, status: sb)
        sb = try await git.status(of: b)
        XCTAssertEqual(sb.behind, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.appendingPathComponent("a.txt").path))
    }

    func testPushBlockedWhenBehindAndPullRefusesDivergence() async throws {
        try write("a\n", "a.txt", in: a)
        try await git.commit(try await git.status(of: a).changes, message: "a", in: a)
        try await git.push(a, status: try await git.status(of: a))

        try write("b\n", "b.txt", in: b)
        try await git.commit(try await git.status(of: b).changes, message: "b", in: b)
        try await git.fetch(b)
        let sb = try await git.status(of: b)
        XCTAssertEqual(sb.ahead, 1)
        XCTAssertEqual(sb.behind, 1)

        do { try await git.push(b, status: sb); XCTFail("push must be blocked") }
        catch { XCTAssertEqual(error as? GitActionError, .behindRemote(1)) }

        // Diverged: --ff-only refuses instead of merging/rebasing.
        do { try await git.pull(b, status: sb); XCTFail("pull must refuse") }
        catch { XCTAssertTrue(error is GitError) }
        let log = try await git.log(of: b, limit: 1)
        XCTAssertEqual(log.first?.subject, "b", "local history untouched")
    }

    func testPushNewBranchSetsUpstream() async throws {
        _ = try await git.run(["switch", "-q", "-c", "feature/x"], in: a)
        try write("f\n", "f.txt", in: a)
        try await git.commit(try await git.status(of: a).changes, message: "f", in: a)
        var s = try await git.status(of: a)
        XCTAssertNil(s.upstream)
        try await git.push(a, status: s)
        s = try await git.status(of: a)
        XCTAssertEqual(s.upstream, "origin/feature/x")
    }

    func testPullWithoutUpstream() async throws {
        _ = try await git.run(["switch", "-q", "-c", "local-only"], in: a)
        let s = try await git.status(of: a)
        do { try await git.pull(a, status: s); XCTFail() }
        catch { XCTAssertEqual(error as? GitActionError, .noUpstreamToPull) }
    }

    func testUnreachableRemoteFailsFast() async throws {
        _ = try await git.run(["remote", "set-url", "origin", root.appendingPathComponent("missing.git").path], in: a)
        do { try await git.fetch(a); XCTFail() }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }

    // MARK: stash

    func testStashPushListPop() async throws {
        try write("dirty\n", "readme.md", in: a)
        try write("untracked\n", "u.txt", in: a)
        try await git.stashPush(a, message: "wip test")
        let clean = try await git.status(of: a)
        XCTAssertTrue(clean.isClean)

        let list = try await git.stashes(a)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].ref, "stash@{0}")
        XCTAssertTrue(list[0].message.contains("wip test"))

        try await git.stashPop(a, ref: list[0].ref)
        let restored = try await git.status(of: a)
        XCTAssertEqual(Set(restored.changes.map(\.path)), ["readme.md", "u.txt"])
        let empty = try await git.stashes(a)
        XCTAssertTrue(empty.isEmpty)
    }

    func testStashPopConflictKeepsStash() async throws {
        try write("stashed\n", "readme.md", in: a)
        try await git.stashPush(a, message: nil)
        try write("committed\n", "readme.md", in: a)
        try await git.commit(try await git.status(of: a).changes, message: "c", in: a)
        do { try await git.stashPop(a); XCTFail("expected conflict") } catch {}
        let list = try await git.stashes(a)
        XCTAssertEqual(list.count, 1, "stash kept after failed pop")
    }

    func testTimeoutKillsHungCommand() async throws {
        let started = Date()
        do {
            _ = try await git.run(["-c", "alias.hang=!sleep 10", "hang"], in: a, timeout: 0.5)
            XCTFail("should time out")
        } catch let e as GitError {
            XCTAssertTrue(e.timedOut)
            XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        }
    }
}
