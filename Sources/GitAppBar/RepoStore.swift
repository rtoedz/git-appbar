import Foundation
import Observation
import GitAppBarCore

struct RepoItem: Identifiable, Equatable {
    let url: URL
    var status: RepoStatus?
    var error: String?

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var parentPath: String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}

@MainActor
@Observable
final class RepoStore {
    private(set) var repos: [RepoItem] = []
    private(set) var isScanning = false
    private(set) var lastScannedRoots: [URL] = []
    var selectedID: String?

    private let git = GitRunner()
    private var scanTask: Task<Void, Never>?
    private let maxConcurrentStatus = 6

    var selected: RepoItem? { repos.first { $0.id == selectedID } }

    func rescan(roots: [URL], depth: Int) {
        scanTask?.cancel()
        lastScannedRoots = roots
        guard !roots.isEmpty else {
            repos = []
            selectedID = nil
            isScanning = false
            return
        }
        isScanning = true
        scanTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                RepoScanner.scan(roots: roots, maxDepth: depth)
            }.value
            guard let self, !Task.isCancelled else { return }

            let previous = Dictionary(uniqueKeysWithValues: self.repos.map { ($0.id, $0) })
            self.repos = found.map { previous[$0.path] ?? RepoItem(url: $0) }
            if self.selected == nil { self.selectedID = self.repos.first?.id }

            await self.refreshStatuses()
            if !Task.isCancelled { self.isScanning = false }
        }
    }

    /// Re-reads `git status` for every known repo, a few at a time.
    func refreshStatuses() async {
        let urls = repos.map(\.url)
        let git = self.git
        for start in stride(from: 0, to: urls.count, by: maxConcurrentStatus) {
            let batch = urls[start..<min(start + maxConcurrentStatus, urls.count)]
            let results = await withTaskGroup(of: (String, RepoStatus?, String?).self) { group in
                for url in batch {
                    group.addTask {
                        do { return (url.path, try await git.status(of: url), nil) }
                        catch { return (url.path, nil, error.localizedDescription) }
                    }
                }
                var out: [(String, RepoStatus?, String?)] = []
                for await r in group { out.append(r) }
                return out
            }
            if Task.isCancelled { return }
            for (path, status, error) in results {
                guard let i = repos.firstIndex(where: { $0.id == path }) else { continue }
                repos[i].status = status
                repos[i].error = error
            }
        }
    }
}
