import XCTest
@testable import GitAppBarCore

final class RepoScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gab-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeRepo(_ path: String, gitAsFile: Bool = false) throws {
        let dir = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let git = dir.appendingPathComponent(".git")
        if gitAsFile {
            try "gitdir: /somewhere/else".write(to: git, atomically: true, encoding: .utf8)
        } else {
            try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        }
    }

    private func names(_ urls: [URL]) -> [String] {
        // Compare paths relative to the temp root, independent of /var vs /private/var.
        let marker = "/" + root.lastPathComponent + "/"
        return urls.map { url in
            guard let range = url.path.range(of: marker) else { return url.path }
            return String(url.path[range.upperBound...])
        }
    }

    func testFindsReposAtVariousDepths() throws {
        try makeRepo("a")
        try makeRepo("group/b")
        try makeRepo("group/deeper/c")
        try makeRepo("worktree", gitAsFile: true)

        let found = RepoScanner.scan(roots: [root], maxDepth: 4)
        XCTAssertEqual(names(found), ["a", "group/b", "group/deeper/c", "worktree"])
    }

    func testStopsAtRepoRootAndSkipsDependencyFolders() throws {
        try makeRepo("app")
        try makeRepo("app/packages/inner")
        try makeRepo("web/node_modules/some-lib")
        try makeRepo(".hidden/repo")

        let found = RepoScanner.scan(roots: [root], maxDepth: 4)
        XCTAssertEqual(names(found), ["app"])
    }

    func testRespectsMaxDepthAndRootIsRepo() throws {
        try makeRepo("x/y/z/too-deep")
        XCTAssertTrue(RepoScanner.scan(roots: [root], maxDepth: 3).isEmpty)
        XCTAssertEqual(RepoScanner.scan(roots: [root], maxDepth: 4).count, 1)

        try makeRepo("solo")
        let solo = root.appendingPathComponent("solo")
        XCTAssertEqual(RepoScanner.scan(roots: [solo], maxDepth: 0).count, 1)
    }

    func testDeduplicatesOverlappingRoots() throws {
        try makeRepo("p/q")
        let found = RepoScanner.scan(roots: [root, root.appendingPathComponent("p")], maxDepth: 4)
        XCTAssertEqual(found.count, 1)
    }
}
