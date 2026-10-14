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

/// A commit paired with its graph row. Views iterate these by commit hash —
/// never by index into two parallel arrays, which crashes when the list
/// shrinks (e.g. switching repo) while SwiftUI still updates old rows.
struct HistoryItem: Identifiable, Equatable {
    let commit: CommitEntry
    let row: GraphRow
    var id: String { commit.hash }
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
        didSet {
            guard oldValue != selectedID else { return }
            excludedPaths = []
            loadSelectedDetails()
        }
    }
    var selected: RepoItem? { repos.first { $0.id == selectedID } }

    // MARK: Selected repo details
    private(set) var history: [CommitEntry] = []
    private(set) var historyItems: [HistoryItem] = []
    private(set) var branches: [Branch] = []
    private(set) var historyLoading = false
    private(set) var historyLoadingMore = false
    private(set) var historyHasMore = false
    let historyPageSize = 100
    var selectedCommitHash: String?
    var expandedCommits: Set<String> = []
    private(set) var commitFiles: [String: [CommitFile]] = [:]
    private(set) var commitMessages: [String: String] = [:]

    // MARK: Working tree / actions
    private(set) var stashes: [StashEntry] = []
    /// Paths unchecked in the Changes list. Everything else gets committed,
    /// so new files are included by default (like VS Code's smart commit).
    var excludedPaths: Set<String> = []
    /// Draft commit message per repo, kept while switching repos.
    var commitDrafts: [String: String] = [:]

    // MARK: Feedback
    /// Label of the git action running on the selected repo ("Push", "Fetch"…).
    private(set) var busyAction: String?
    var isBusy: Bool { busyAction != nil }
    private(set) var isFetchingAll = false
    private(set) var banner: Banner?

    private let git = GitRunner()
    private var scanTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private let maxConcurrentStatus = 6

    var selectedCommit: CommitEntry? { history.first { $0.hash == selectedCommitHash } }
    var graphLaneCount: Int { min(historyItems.map(\.row.laneCount).max() ?? 1, 10) }

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
        setHistory([], rows: [])
        branches = []
        selectedCommitHash = nil
        expandedCommits = []
        commitFiles = [:]
        commitMessages = [:]
        stashes = []
        // excludedPaths is NOT reset here: this also runs after every action,
        // and a failed commit must not silently re-include unchecked files.
        guard let repo = selected else { return }

        historyLoading = true
        historyLoadingMore = false
        historyHasMore = false
        let git = self.git
        let pageSize = historyPageSize
        detailTask = Task { [weak self] in
            async let log = try? git.log(of: repo.url, limit: pageSize)
            async let branchList = try? git.branches(of: repo.url)
            async let stashList = try? git.stashes(repo.url)
            let (entries, branches, stashes) = await (log ?? [], branchList ?? [], stashList ?? [])
            let rows = await Task.detached { GraphLayout.layout(entries) }.value
            guard let self, !Task.isCancelled, self.selectedID == repo.id else { return }
            self.setHistory(entries, rows: rows)
            self.branches = branches
            self.stashes = stashes
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
            self.setHistory(merged, rows: rows)
            self.historyHasMore = page.count == pageSize
            self.historyLoadingMore = false
        }
    }

    /// Commits and their graph rows always change together.
    private func setHistory(_ entries: [CommitEntry], rows: [GraphRow]) {
        history = entries
        historyItems = zip(entries, rows).map { HistoryItem(commit: $0, row: $1) }
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
        busyAction = "Pindah branch"
        defer { busyAction = nil }
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

    // MARK: Git actions

    var commitMessage: String {
        get { selectedID.flatMap { commitDrafts[$0] } ?? "" }
        set { if let id = selectedID { commitDrafts[id] = newValue } }
    }

    /// Changes that will go into the next commit.
    var includedChanges: [FileChange] {
        (selected?.status?.changes ?? []).filter { !excludedPaths.contains($0.path) }
    }

    var hasConflicts: Bool {
        selected?.status?.changes.contains { $0.kind == .unmerged } ?? false
    }

    func toggleIncluded(_ path: String) {
        if excludedPaths.contains(path) { excludedPaths.remove(path) } else { excludedPaths.insert(path) }
    }

    func setAllIncluded(_ included: Bool) {
        excludedPaths = included ? [] : Set(selected?.status?.changes.map(\.path) ?? [])
    }

    /// Runs one git action on the selected repo: one at a time, errors shown as
    /// a banner, then status/history/stashes are re-read.
    private func perform(_ label: String, reloadHistory: Bool = true,
                         _ operation: @escaping @MainActor (RepoItem) async throws -> String?) async {
        guard let repo = selected, !isBusy else { return }
        busyAction = label
        do {
            if let message = try await operation(repo) { show(message, isError: false) }
        } catch {
            show(error.localizedDescription, isError: true)
        }
        await refreshStatus(of: [repo.url])
        busyAction = nil
        if selectedID == repo.id {
            if reloadHistory { loadSelectedDetails() } else { await reloadStashes(repo) }
        }
    }

    private func reloadStashes(_ repo: RepoItem) async {
        let list = (try? await git.stashes(repo.url)) ?? []
        if selectedID == repo.id { stashes = list }
    }

    /// Fresh status right before acting, so ahead/behind guards use current numbers.
    private func currentStatus(_ repo: RepoItem) async throws -> RepoStatus {
        let status = try await git.status(of: repo.url)
        if let i = repos.firstIndex(where: { $0.id == repo.id }) { repos[i].status = status }
        return status
    }

    func commit(andPush: Bool) async {
        let changes = includedChanges
        let message = commitMessage
        await perform(andPush ? "Commit & Push" : "Commit") { [git] repo in
            if andPush {
                let before = try await self.currentStatus(repo)
                if before.behind > 0 { throw GitActionError.behindRemote(before.behind) }
            }
            try await git.commit(changes, message: message, in: repo.url)
            self.commitDrafts[repo.id] = nil
            self.excludedPaths = []
            let n = changes.count
            guard andPush else { return "\(n) file di-commit" }
            do {
                try await git.push(repo.url, status: try await self.currentStatus(repo))
            } catch {
                throw PushAfterCommitError(underlying: error)
            }
            return "\(n) file di-commit dan di-push"
        }
    }

    func fetch() async {
        await perform("Fetch") { [git] repo in
            try await git.fetch(repo.url)
            let s = try await self.currentStatus(repo)
            return s.behind > 0 ? "\(s.behind) commit baru di \(s.upstream ?? "remote")" : "Sudah up to date"
        }
    }

    func pull() async {
        await perform("Pull") { [git] repo in
            let s = try await self.currentStatus(repo)
            if s.behind == 0 {
                try await git.fetch(repo.url)
            }
            let fresh = try await self.currentStatus(repo)
            guard fresh.behind > 0 else { return "Sudah up to date" }
            try await git.pull(repo.url, status: fresh)
            return "\(fresh.behind) commit di-pull ke \(fresh.branch ?? "branch ini")"
        }
    }

    func push() async {
        await perform("Push") { [git] repo in
            let s = try await self.currentStatus(repo)
            if s.upstream != nil && s.ahead == 0 { return "Tidak ada commit untuk di-push" }
            try await git.push(repo.url, status: s)
            return s.upstream == nil ? "Branch \(s.branch ?? "") dipublikasikan ke remote" : "\(s.ahead) commit di-push"
        }
    }

    func stash(message: String?) async {
        await perform("Stash", reloadHistory: false) { [git] repo in
            let s = try await self.currentStatus(repo)
            guard !s.changes.isEmpty else { return "Tidak ada perubahan untuk di-stash" }
            try await git.stashPush(repo.url, message: message)
            self.excludedPaths = []
            return "\(s.changes.count) file disimpan ke stash"
        }
    }

    func popStash(_ entry: StashEntry) async {
        await perform("Stash pop", reloadHistory: false) { [git] repo in
            do {
                try await git.stashPop(repo.url, ref: entry.ref)
            } catch {
                throw StashPopError(underlying: error)
            }
            return "Stash dikembalikan ke working tree"
        }
    }

    func applyStash(_ entry: StashEntry) async {
        await perform("Stash apply", reloadHistory: false) { [git] repo in
            try await git.stashApply(repo.url, ref: entry.ref)
            return "Stash diterapkan (tetap tersimpan di daftar)"
        }
    }

    /// Fetches every repo, a few at a time, then refreshes their status.
    func fetchAll() async {
        guard !isFetchingAll else { return }
        isFetchingAll = true
        defer { isFetchingAll = false }
        let urls = repos.map(\.url)
        let git = self.git
        var failed: [String] = []
        for start in stride(from: 0, to: urls.count, by: 4) {
            let batch = Array(urls[start..<min(start + 4, urls.count)])
            let errors = await withTaskGroup(of: String?.self) { group in
                for url in batch {
                    group.addTask { (try? await git.fetch(url)) == nil ? url.lastPathComponent : nil }
                }
                var out: [String] = []
                for await e in group { if let e { out.append(e) } }
                return out
            }
            failed += errors
            await refreshStatus(of: batch)
        }
        if failed.isEmpty {
            show("Semua \(urls.count) repo sudah di-fetch", isError: false)
        } else {
            show("Fetch gagal di: \(failed.sorted().joined(separator: ", "))", isError: true)
        }
        if let repo = selected, !isBusy { await reloadStashes(repo) }
    }
}

struct PushAfterCommitError: LocalizedError {
    let underlying: Error
    var errorDescription: String? {
        "Commit tersimpan, tapi push gagal: \(underlying.localizedDescription)"
    }
}

struct StashPopError: LocalizedError {
    let underlying: Error
    var errorDescription: String? {
        "Stash tidak bisa dikembalikan (kemungkinan konflik). Stash tetap tersimpan, tidak ada yang hilang. \(underlying.localizedDescription)"
    }
}
