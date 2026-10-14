import XCTest
@testable import GitAppBarCore

final class GitStatusParserTests: XCTestCase {
    private func z(_ entries: [String]) -> String {
        entries.joined(separator: "\0") + "\0"
    }

    func testBranchHeaders() {
        let s = GitStatusParser.parse(z([
            "# branch.oid a91c3f27d04e8b6125f0c9e7a3d2b8146e0f5c31",
            "# branch.head develop",
            "# branch.upstream origin/develop",
            "# branch.ab +2 -7"
        ]))
        XCTAssertEqual(s.oid, "a91c3f27d04e8b6125f0c9e7a3d2b8146e0f5c31")
        XCTAssertEqual(s.branch, "develop")
        XCTAssertEqual(s.upstream, "origin/develop")
        XCTAssertEqual(s.ahead, 2)
        XCTAssertEqual(s.behind, 7)
        XCTAssertTrue(s.isClean)
    }

    func testDetachedAndInitial() {
        let s = GitStatusParser.parse(z(["# branch.oid (initial)", "# branch.head (detached)"]))
        XCTAssertNil(s.oid)
        XCTAssertNil(s.branch)
        XCTAssertTrue(s.isDetached)
    }

    func testOrdinaryUntrackedRenamedUnmerged() {
        let s = GitStatusParser.parse(z([
            "# branch.head main",
            "1 .M N... 100644 100644 100644 3f2a 3f2a services/venue/repository/gorm_repository.go",
            "1 A. N... 000000 100644 100644 0000 9b1c path with spaces/new file.go",
            "2 R. N... 100644 100644 100644 aaaa bbbb R100 new/name.go",
            "old/name.go",
            "u UU N... 100644 100644 100644 100644 1111 2222 3333 conflict.go",
            "? migrations/qa/qa-prod-2026-10-08-rollback.sql"
        ]))
        XCTAssertEqual(s.changes.count, 5)

        XCTAssertEqual(s.changes[0].path, "services/venue/repository/gorm_repository.go")
        XCTAssertEqual(s.changes[0].badge, "M")
        XCTAssertFalse(s.changes[0].isStaged)

        XCTAssertEqual(s.changes[1].path, "path with spaces/new file.go")
        XCTAssertEqual(s.changes[1].badge, "A")
        XCTAssertTrue(s.changes[1].isStaged)

        XCTAssertEqual(s.changes[2].path, "new/name.go")
        XCTAssertEqual(s.changes[2].kind, .renamed(from: "old/name.go"))
        XCTAssertEqual(s.changes[2].badge, "R")

        XCTAssertEqual(s.changes[3].kind, .unmerged)
        XCTAssertEqual(s.changes[3].badge, "!")

        XCTAssertEqual(s.changes[4].kind, .untracked)
        XCTAssertEqual(s.changes[4].badge, "U")
    }

    func testRealGitOutput() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gab-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let git = GitRunner()
        _ = try await git.run(["init", "-b", "main"], in: dir)
        try "hello".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: dir.appendingPathComponent("untracked file.txt"), atomically: true, encoding: .utf8)
        _ = try await git.run(["add", "a.txt"], in: dir)

        let s = try await git.status(of: dir)
        XCTAssertEqual(s.branch, "main")
        XCTAssertEqual(Set(s.changes.map(\.path)), ["a.txt", "untracked file.txt"])
        XCTAssertEqual(s.changes.first { $0.path == "a.txt" }?.isStaged, true)
    }
}
