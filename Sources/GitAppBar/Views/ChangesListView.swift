import SwiftUI
import GitAppBarCore

enum RepoTab: String, CaseIterable {
    case changes, history

    var title: String {
        switch self {
        case .changes: return tr("Changes", "Perubahan")
        case .history: return tr("History", "Riwayat")
        }
    }
}

/// Middle column: repo header with branch switcher, tabs, and their content.
struct RepoDetailView: View {
    @Environment(RepoStore.self) private var store
    let repo: RepoItem
    @State private var tab: RepoTab = .history
    @State private var showBranches = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let banner = store.banner {
                BannerView(banner: banner) { store.dismissBanner() }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
            }
            tabs
            Rectangle().fill(Theme.divider).frame(height: 1)
            switch tab {
            case .changes: ChangesContent(repo: repo)
            case .history: HistoryView(repo: repo)
            }
        }
        .onAppear {
            // Land where the work is: uncommitted changes → Changes tab.
            if let n = repo.status?.changes.count, n > 0 { tab = .changes }
        }
    }

    /// Picks the first layout that fits the column width: everything on one
    /// row, toolbar on its own row, then icon-only toolbar without upstream.
    /// Labels never get truncated to "…".
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                titleGroup(showUpstream: true)
                Spacer(minLength: 12)
                GitToolbar(repo: repo, compact: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                titleGroup(showUpstream: true)
                GitToolbar(repo: repo, compact: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                titleGroup(showUpstream: false)
                GitToolbar(repo: repo, compact: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func titleGroup(showUpstream: Bool) -> some View {
        HStack(spacing: 10) {
            Text(repo.name)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
            Button {
                showBranches.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(repo.status?.branch ?? "detached").lineLimit(1).fixedSize()
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .font(Theme.mono)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy)
            .accessibilityLabel(tr("Switch branch", "Pindah branch"))
            .popover(isPresented: $showBranches, arrowEdge: .bottom) {
                BranchPicker(repo: repo, isPresented: $showBranches)
                    .environment(store)
            }

            if let s = repo.status {
                if showUpstream, let up = s.upstream {
                    Text("→ \(up)").font(Theme.mono).foregroundStyle(Theme.textDim).lineLimit(1).fixedSize()
                }
                if s.behind > 0 { Text("↓\(s.behind)").font(Theme.mono).foregroundStyle(Theme.behind).fixedSize() }
                if s.ahead > 0 { Text("↑\(s.ahead)").font(Theme.mono).foregroundStyle(Theme.added).fixedSize() }
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(RepoTab.allCases, id: \.self) { t in
                Button {
                    tab = t
                } label: {
                    HStack(spacing: 6) {
                        Text(t.title)
                        if t == .changes, let n = repo.status?.changes.count, n > 0 {
                            Text("\(n)").foregroundStyle(Theme.textDim)
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tab == t ? Color.white : Theme.textDim)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(tab == t ? Theme.behind : .clear).frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }
}

struct BannerView: View {
    let banner: Banner
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(banner.isError ? Theme.modified : Theme.added)
            Text(banner.text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim)
                .accessibilityLabel(tr("Close", "Tutup"))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(banner.isError ? Color(red: 0.17, green: 0.14, blue: 0.09) : Color(red: 0.12, green: 0.16, blue: 0.13))
        )
    }
}

/// Working-tree changes: commit box on top, then every changed file with a
/// checkbox (all included by default). Clicking a file name opens it.
struct ChangesContent: View {
    @Environment(Preferences.self) private var prefs
    @Environment(RepoStore.self) private var store
    let repo: RepoItem

    var body: some View {
        if let status = repo.status {
            VStack(spacing: 0) {
                CommitBox(repo: repo, status: status)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                if store.hasConflicts {
                    Label(tr("Some files have conflicts (!). Resolve them in your editor before committing.", "Ada file konflik (!). Selesaikan di editor sebelum commit."), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.modified)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 6)
                }
                if status.changes.isEmpty {
                    Text(tr("Working tree clean. No changes.", "Working tree bersih. Tidak ada perubahan."))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    selectAllRow(status)
                    PanelScroll {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(status.changes) { change in
                                HStack(spacing: 4) {
                                    Toggle("", isOn: Binding(
                                        get: { !store.excludedPaths.contains(change.path) },
                                        set: { _ in store.toggleIncluded(change.path) }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    .accessibilityLabel(tr("Include in commit: ", "Ikut commit: ") + change.path)
                                    FileRow(
                                        path: change.path,
                                        badge: change.badge,
                                        trailing: change.isStaged ? "staged" : nil
                                    ) {
                                        EditorOpener.open(repo.url.appendingPathComponent(change.path), command: prefs.editorCommand)
                                    }
                                }
                                .padding(.leading, 10)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 10)
                    }
                }
            }
        } else if let error = repo.error {
            Text(error)
                .font(.system(size: 13))
                .foregroundStyle(Theme.modified)
                .padding(18)
            Spacer()
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func selectAllRow(_ status: RepoStatus) -> some View {
        let included = store.includedChanges.count
        let total = status.changes.count
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { included == total },
                set: { store.setAllIncluded($0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(tr("Select all files", "Pilih semua file"))
            Text(tr("CHANGES · \(included) of \(total) selected", "PERUBAHAN · \(included) dari \(total) dipilih"))
                .font(.system(size: 11))
                .tracking(0.8)
                .foregroundStyle(Theme.textDim)
            Spacer()
        }
        .padding(.leading, 24)
        .padding(.vertical, 4)
    }
}

private struct CommitBox: View {
    @Environment(RepoStore.self) private var store
    let repo: RepoItem
    let status: RepoStatus

    private var message: String { store.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Why committing is not possible right now, or nil.
    private var blockReason: String? {
        if status.changes.isEmpty { return tr("No changes", "Tidak ada perubahan") }
        if store.hasConflicts { return tr("Resolve conflicts first", "Selesaikan konflik dulu") }
        if store.includedChanges.isEmpty { return tr("Select at least 1 file", "Pilih minimal 1 file") }
        if message.isEmpty { return tr("Write a commit message", "Tulis pesan commit") }
        return nil
    }

    private var pushBlockReason: String? {
        if let r = blockReason { return r }
        if status.branch == nil { return "HEAD detached" }
        if status.behind > 0 { return tr("Remote is ahead (↓\(status.behind)), pull first", "Remote lebih baru (↓\(status.behind)), pull dulu") }
        return nil
    }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 8) {
            TextField(tr("Message for \(status.branch ?? "HEAD")  (⌘↩ to commit)", "Pesan commit ke \(status.branch ?? "HEAD")  (⌘↩ untuk commit)"),
                      text: $store.commitMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(2...6)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))

            HStack(spacing: 8) {
                Text(pushBlockReason ?? tr("\(count(store.includedChanges.count, "file")) will be committed", "\(store.includedChanges.count) file akan di-commit"))
                    .font(.system(size: 11))
                    .foregroundStyle(blockReason == nil && pushBlockReason != nil ? Theme.modified : Theme.textDim)
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { await store.commit(andPush: false) }
                } label: {
                    Label(store.busyAction == "Commit" ? "Commit…" : "Commit", systemImage: "checkmark")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(blockReason != nil || store.isBusy)
                .help(blockReason ?? tr("git commit the selected files", "git commit file yang dipilih"))

                Button {
                    Task { await store.commit(andPush: true) }
                } label: {
                    Text(store.busyAction == "Commit & Push" ? "Commit & Push…" : "Commit & Push")
                }
                .disabled(pushBlockReason != nil || store.isBusy)
                .help(pushBlockReason ?? tr("Commit, then push to the remote", "Commit lalu push ke remote"))
            }
            .controlSize(.regular)
        }
    }
}

/// One file line: status badge, name, directory, optional trailing info. Clickable.
struct FileRow: View {
    let path: String
    let badge: String
    var additions: Int? = nil
    var deletions: Int? = nil
    var trailing: String? = nil
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    private var fileName: String { (path as NSString).lastPathComponent }
    private var directory: String { (path as NSString).deletingLastPathComponent }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                StatusBadge(letter: badge)
                Text(fileName).font(.system(size: 13)).lineLimit(1)
                Text(directory)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 8)
                if let a = additions { Text("+\(a)").font(Theme.mono).foregroundStyle(Theme.added) }
                if let d = deletions { Text("−\(d)").font(Theme.mono).foregroundStyle(Theme.deleted) }
                if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(Theme.added) }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering && enabled ? Color.white.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(enabled ? tr("Open in editor", "Buka di editor") : tr("File was deleted", "File sudah dihapus"))
    }
}

struct StatusBadge: View {
    let letter: String

    private var colors: (Color, Color) {
        switch letter {
        case "U", "A": return (Color(red: 0.11, green: 0.23, blue: 0.17), Theme.added)
        case "D", "!": return (Color(red: 0.24, green: 0.12, blue: 0.13), Theme.deleted)
        case "R", "C": return (Color(red: 0.13, green: 0.17, blue: 0.27), Theme.behind)
        default: return (Color(red: 0.23, green: 0.18, blue: 0.09), Theme.modified)
        }
    }

    var body: some View {
        Text(letter)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(colors.1)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(colors.0))
    }
}
