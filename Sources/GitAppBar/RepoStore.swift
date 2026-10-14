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

struct Banner: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}

@MainActor
@Observable
final class RepoStore {
    // MARK: Repos
    private(set) var repos: [RepoItem] = []
    private(set) var isScanning = false
    var selectedID: String? {
        didSet { if oldValue != selectedID { loadSelectedDetails() } }
    }
    var selected: RepoItem? { repos.first { $0.id == selectedID } }

    // MARK: Selected repo details
    private(set) var history: [CommitEntry] = []
    private(set) var graph: [GraphRow] = []
    private(set) var branches: [Branch] = []
    private(set) var historyLoading = false
    private(set) var historyLoadingMore = false
    private(set) var historyHasMore = false
    let historyPageSize = 100
    var selectedCommitHash: String?
    var expandedCommits: Set<String> = []
    private(set) var commitFiles: [String: [CommitFile]] = [:]
    private(set) var commitMessages: [String: String] = [:]

    // MARK: Feedback
    private(set) var isBusy = false
    private(set) var banner: Banner?

    private let git = GitRunner()
    private var scanTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private let maxConcurrentStatus = 6

    var selectedCommit: CommitEntry? { history.first { $0.hash == selectedCommitHash } }
    var graphLaneCount: Int { min(graph.map(\.laneCount).max() ?? 1, 10) }

    // MARK: Scanning

    func rescan(roots: [URL], depth: Int) {
        scanTask?.cancel()
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
        for start in stride(from: 0, to: urls.count, by: maxConcurrentStatus) {
            let batch = Array(urls[start..<min(start + maxConcurrentStatus, urls.count)])
            await refreshStatus(of: batch)
            if Task.isCancelled { return }
        }
    }

    private func refreshStatus(of urls: [URL]) async {
        let git = self.git
        let results = await withTaskGroup(of: (String, RepoStatus?, String?).self) { group in
            for url in urls {
                group.addTask {
                    do { return (url.path, try await git.status(of: url), nil) }
                    catch { return (url.path, nil, error.localizedDescription) }
                }
            }
            var out: [(String, RepoStatus?, String?)] = []
            for await r in group { out.append(r) }
            return out
        }
        for (path, status, error) in results {
            guard let i = repos.firstIndex(where: { $0.id == path }) else { continue }
            repos[i].status = status
            repos[i].error = error
        }
    }

    // MARK: History & branches

    func loadSelectedDetails() {
        detailTask?.cancel()
        history = []
        graph = []
        branches = []
        selectedCommitHash = nil
        expandedCommits = []
        commitFiles = [:]
        commitMessages = [:]
        guard let repo = selected else { return }

        historyLoading = true
        historyLoadingMore = false
        historyHasMore = false
        let git = self.git
        let pageSize = historyPageSize
        detailTask = Task { [weak self] in
            async let log = try? git.log(of: repo.url, limit: pageSize)
            async let branchList = try? git.branches(of: repo.url)
            let (entries, branches) = await (log ?? [], branchList ?? [])
            let rows = await Task.detached { GraphLayout.layout(entries) }.value
            guard let self, !Task.isCancelled, self.selectedID == repo.id else { return }
            self.history = entries
            self.graph = rows
            self.branches = branches
            self.historyHasMore = entries.count == pageSize
            self.historyLoading = false
        }
    }

    /// Appends the next page. The graph is re-laid out over everything loaded
    /// so lanes stay continuous across page boundaries.
    func loadMoreHistory() {
        guard historyHasMore, !historyLoadingMore, !historyLoading, let repo = selected else { return }
        historyLoadingMore = true
        let git = self.git
        let pageSize = historyPageSize
        let skip = history.count
        Task { [weak self] in
            let page = (try? await git.log(of: repo.url, limit: pageSize, skip: skip)) ?? []
            guard let self, self.selectedID == repo.id, self.history.count == skip else {
                self?.historyLoadingMore = false
                return
            }
            let known = Set(self.history.map(\.hash))
            let merged = self.history + page.filter { !known.contains($0.hash) }
            let rows = await Task.detached { GraphLayout.layout(merged) }.value
            guard self.selectedID == repo.id else { return }
            self.history = merged
            self.graph = rows
            self.historyHasMore = page.count == pageSize
            self.historyLoadingMore = false
        }
    }

    func toggleCommit(_ hash: String) {
        selectedCommitHash = hash
        if expandedCommits.contains(hash) {
            expandedCommits.remove(hash)
        } else {
            expandedCommits.insert(hash)
        }
        loadCommitFiles(hash)
    }

    func loadCommitFiles(_ hash: String) {
        guard commitFiles[hash] == nil, let repo = selected else { return }
        let git = self.git
        Task { [weak self] in
            async let files = try? git.commitFiles(hash, in: repo.url)
            async let message = try? git.commitMessage(hash, in: repo.url)
            let (f, m) = await (files ?? [], message)
            guard let self else { return }
            self.commitFiles[hash] = f
            if let m { self.commitMessages[hash] = m }
        }
    }

    // MARK: Actions

    func switchBranch(to branch: Branch, stashFirst: Bool) async {
        guard let repo = selected, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let target = try await git.switchBranch(branch, in: repo.url, localBranches: branches, stashFirst: stashFirst)
            show(stashFirst ? "Perubahan di-stash, pindah ke \(target)" : "Pindah ke \(target)", isError: false)
        } catch {
            let note = stashFirst ? " Perubahanmu aman di stash." : ""
            show(error.localizedDescription + note, isError: true)
        }
        await refreshStatus(of: [repo.url])
        loadSelectedDetails()
    }

    func show(_ text: String, isError: Bool) {
        let banner = Banner(text: text, isError: isError)
        self.banner = banner
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 8 : 4))
            if self?.banner?.id == banner.id { self?.banner = nil }
        }
    }

    func dismissBanner() { banner = nil }
}
