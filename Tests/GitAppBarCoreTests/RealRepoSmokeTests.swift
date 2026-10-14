import XCTest
@testable import GitAppBarCore

/// Runs only with GAB_REAL_REPO=/path/to/repo, against a real, large history.
final class RealRepoSmokeTests: XCTestCase {
    func testRealRepo() async throws {
        guard let path = ProcessInfo.processInfo.environment["GAB_REAL_REPO"] else {
            throw XCTSkip("Set GAB_REAL_REPO to run")
        }
        let repo = URL(fileURLWithPath: path)
        let git = GitRunner()

        let started = Date()
        let log = try await git.log(of: repo)
        let rows = GraphLayout.layout(log)
        let branches = try await git.branches(of: repo)
        let files = try await git.commitFiles(log[0].hash, in: repo)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertFalse(log.isEmpty)
        XCTAssertEqual(rows.count, log.count)
        XCTAssertTrue(log.allSatisfy { !$0.author.isEmpty && $0.date != .distantPast })
        print("""
        [smoke] commits=\(log.count) maxLanes=\(rows.map(\.laneCount).max() ?? 0) \
        branches=\(branches.count) (current=\(branches.first { $0.isCurrent }?.name ?? "-")) \
        headFiles=\(files.count) authors=\(Set(log.map(\.author)).count) time=\(String(format: "%.2f", elapsed))s
        [smoke] top: \(log.prefix(3).map { "\($0.shortHash) \($0.author): \($0.subject)" })
        """)
    }
}
