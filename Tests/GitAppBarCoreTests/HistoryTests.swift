import XCTest
@testable import GitAppBarCore

final class HistoryTests: XCTestCase {
    private func commit(_ hash: String, _ parents: [String]) -> CommitEntry {
        CommitEntry(hash: hash, parents: parents, author: "a", email: "a@x", date: .distantPast,
                    refs: [], headBranch: nil, isHead: false, subject: hash)
    }

    // MARK: log

    func testLogParser() {
        let us = "\u{1f}", rs = "\u{1e}"
        let out = [
            ["a1", "b2 c3", "Krisna", "k@x.com", "2026-10-14T10:12:00+08:00", "HEAD -> dev, origin/dev, origin/HEAD, tag: v1.2", "Merge branch feature"].joined(separator: us),
            ["b2", "", "Rekan A", "r@x.com", "2026-10-13T17:40:00+08:00", "", "feat: subject with \u{1f} separator"].joined(separator: us)
        ].joined(separator: rs + "\n") + rs + "\n"

        let log = GitLogParser.parse(out)
        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log[0].parents, ["b2", "c3"])
        XCTAssertTrue(log[0].isMerge)
        XCTAssertTrue(log[0].isHead)
        XCTAssertEqual(log[0].headBranch, "dev")
        XCTAssertEqual(log[0].refs, ["dev", "origin/dev", "tag: v1.2"])
        XCTAssertEqual(log[0].author, "Krisna")
        XCTAssertNotEqual(log[0].date, .distantPast)
        XCTAssertEqual(log[1].parents, [])
        XCTAssertEqual(log[1].subject, "feat: subject with \u{1f} separator")
    }

    // MARK: graph

    func testLinearHistoryStaysInOneLane() {
        let rows = GraphLayout.layout([commit("c", ["b"]), commit("b", ["a"]), commit("a", [])])
        XCTAssertEqual(rows.map(\.column), [0, 0, 0])
        XCTAssertEqual(rows.map(\.laneCount), [1, 1, 1])
        XCTAssertEqual(rows[1].top, [GraphEdge(from: 0, to: 0)])
        XCTAssertEqual(rows[2].bottom, [])
    }

    func testMergeOpensAndClosesSecondLane() {
        // m merges p1 (first parent) and p2; both come from base.
        let rows = GraphLayout.layout([
            commit("m", ["p1", "p2"]),
            commit("p1", ["base"]),
            commit("p2", ["base"]),
            commit("base", [])
        ])
        XCTAssertEqual(rows.map(\.column), [0, 0, 1, 0])
        XCTAssertEqual(rows[0].bottom, [GraphEdge(from: 0, to: 0), GraphEdge(from: 0, to: 1)])
        XCTAssertEqual(rows[1].bottom, [GraphEdge(from: 0, to: 0), GraphEdge(from: 1, to: 1)])
        // p2 joins back into lane 0 where base is already expected.
        XCTAssertEqual(rows[2].bottom, [GraphEdge(from: 0, to: 0), GraphEdge(from: 1, to: 0)])
        XCTAssertEqual(rows[3].top, [GraphEdge(from: 0, to: 0)])
        XCTAssertEqual(rows[3].laneCount, 1)
    }

    func testTwoTipsConverge() {
        // HEAD tip and upstream tip share parent "base".
        let rows = GraphLayout.layout([commit("local", ["base"]), commit("remote", ["base"]), commit("base", [])])
        XCTAssertEqual(rows.map(\.column), [0, 1, 0])
        XCTAssertEqual(rows[1].bottom, [GraphEdge(from: 0, to: 0), GraphEdge(from: 1, to: 0)])
        XCTAssertEqual(rows[2].top, [GraphEdge(from: 0, to: 0)])
    }

    // MARK: commit files

    func testCommitFilesParser() {
        let nameStatus = ["M", ".woodpecker.yml", "A", "new.go", "D", "gone.go", "R087", "old/x.go", "new/x.go", "M", "img.png", ""].joined(separator: "\0")
        let numstat = ["4\t2\t.woodpecker.yml", "10\t0\tnew.go", "0\t7\tgone.go", "3\t1\t", "old/x.go", "new/x.go", "-\t-\timg.png", ""].joined(separator: "\0")
        let files = CommitFilesParser.parse(nameStatus: nameStatus, numstat: numstat)
        XCTAssertEqual(files.map(\.path), [".woodpecker.yml", "new.go", "gone.go", "new/x.go", "img.png"])
        XCTAssertEqual(files.map(\.status), ["M", "A", "D", "R", "M"])
        XCTAssertEqual(files[0].additions, 4)
        XCTAssertEqual(files[0].deletions, 2)
        XCTAssertEqual(files[3].oldPath, "old/x.go")
        XCTAssertEqual(files[3].additions, 3)
        XCTAssertNil(files[4].additions)
    }

    // MARK: branches

    func testBranchParser() {
        let us = "\u{1f}"
        let out = [
            [" ", "refs/heads/main", "main", "origin/main", "1700000000"],
            ["*", "refs/heads/dev", "dev", "origin/dev", "1760000000"],
            [" ", "refs/remotes/origin/HEAD", "origin", "", "0"],
            [" ", "refs/remotes/origin/feature/x", "origin/feature/x", "", "1750000000"]
        ].map { $0.joined(separator: us) }.joined(separator: "\n")
        let branches = BranchParser.parse(out)
        XCTAssertEqual(branches.map(\.name), ["dev", "origin/feature/x", "main"])
        XCTAssertTrue(branches[0].isCurrent)
        XCTAssertEqual(branches[1].localName, "feature/x")
        XCTAssertTrue(branches[1].isRemote)
    }

    // MARK: integration on a real repo

    func testRealRepoLogFilesAndSwitchWithStash() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gab-hist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let git = GitRunner()
        let ident = ["-c", "user.name=Tester", "-c", "user.email=t@x.com"]

        _ = try await git.run(["init", "-b", "main"], in: dir)
        try "one\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await git.run(["add", "."], in: dir)
        _ = try await git.run(ident + ["commit", "-m", "first"], in: dir)
        _ = try await git.run(["branch", "feature"], in: dir)
        try "one\ntwo\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await git.run(ident + ["commit", "-am", "second"], in: dir)

        let log = try await git.log(of: dir)
        XCTAssertEqual(log.map(\.subject), ["second", "first"])
        XCTAssertEqual(log[0].author, "Tester")
        XCTAssertEqual(log[0].headBranch, "main")

        let files = try await git.commitFiles(log[0].hash, in: dir)
        XCTAssertEqual(files.first?.path, "a.txt")
        XCTAssertEqual(files.first?.additions, 1)
        let rootFiles = try await git.commitFiles(log[1].hash, in: dir)
        XCTAssertEqual(rootFiles.first?.status, "A")

        // Dirty tree, then switch with auto-stash.
        try "dirty\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let branches = try await git.branches(of: dir)
        let feature = try XCTUnwrap(branches.first { $0.name == "feature" })
        try await git.switchBranch(feature, in: dir, localBranches: branches, stashFirst: true)

        let status = try await git.status(of: dir)
        XCTAssertEqual(status.branch, "feature")
        XCTAssertTrue(status.isClean)
        let stash = try await git.run(["stash", "list"], in: dir)
        XCTAssertTrue(stash.contains("git-appbar: auto-stash sebelum pindah ke feature"))
    }
}
