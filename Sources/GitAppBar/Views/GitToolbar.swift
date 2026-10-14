import SwiftUI
import GitAppBarCore

/// Fetch / Pull / Push / Stash for the selected repo.
struct GitToolbar: View {
    @Environment(RepoStore.self) private var store
    let repo: RepoItem
    @State private var showStash = false

    private var status: RepoStatus? { repo.status }

    var body: some View {
        HStack(spacing: 6) {
            ToolbarButton(title: "Fetch", icon: "arrow.triangle.2.circlepath",
                          busy: store.busyAction == "Fetch") {
                Task { await store.fetch() }
            }
            .help("git fetch --prune")

            ToolbarButton(title: "Pull", icon: "arrow.down", count: status?.behind, countColor: Theme.behind,
                          busy: store.busyAction == "Pull") {
                Task { await store.pull() }
            }
            .disabled(status?.upstream == nil)
            .help(status?.upstream == nil ? tr("This branch has no upstream", "Branch ini belum punya upstream")
                                           : tr("git pull --ff-only (never merges or rebases for you)", "git pull --ff-only (tidak pernah merge/rebase otomatis)"))

            ToolbarButton(title: "Push", icon: "arrow.up", count: status?.ahead, countColor: Theme.added,
                          busy: store.busyAction == "Push") {
                Task { await store.push() }
            }
            .disabled((status?.behind ?? 0) > 0)
            .help(pushHelp)

            ToolbarButton(title: "Stash", icon: "tray.and.arrow.down", count: store.stashes.count,
                          countColor: Theme.lane(1), busy: store.busyAction?.hasPrefix("Stash") == true,
                          chevron: true) {
                showStash.toggle()
            }
            .popover(isPresented: $showStash, arrowEdge: .bottom) {
                StashMenu(repo: repo, isPresented: $showStash)
                    .environment(store)
            }
        }
    }

    private var pushHelp: String {
        guard let s = status else { return "" }
        if s.behind > 0 { return tr("The remote is ahead (↓\(s.behind)). Pull before pushing.", "Remote lebih baru (↓\(s.behind)). Pull dulu sebelum push.") }
        if s.upstream == nil { return tr("Publish this branch to the remote", "Publikasikan branch ini ke remote") }
        return tr("git push (never forced)", "git push (tanpa force)")
    }
}

private struct ToolbarButton: View {
    let title: String
    let icon: String
    var count: Int? = nil
    var countColor: Color = Theme.textDim
    var busy = false
    var chevron = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(RepoStore.self) private var store

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                if let count, count > 0 {
                    Text("\(count)").foregroundStyle(countColor).font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                if chevron {
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textDim)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy)
    }
}

private struct StashMenu: View {
    @Environment(RepoStore.self) private var store
    let repo: RepoItem
    @Binding var isPresented: Bool
    @State private var message = ""

    private var changeCount: Int { repo.status?.changes.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stash").font(.system(size: 14, weight: .semibold))

            HStack(spacing: 8) {
                TextField(tr("Stash message (optional)", "Pesan stash (opsional)"), text: $message)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(stashNow)
                Button(tr("Stash \(count(changeCount, "file"))", "Stash \(changeCount) file"), action: stashNow)
                    .disabled(changeCount == 0)
            }

            Divider()

            Text(tr("SAVED", "TERSIMPAN") + " · \(store.stashes.count)")
                .font(.system(size: 11))
                .tracking(0.8)
                .foregroundStyle(Theme.textDim)

            if store.stashes.isEmpty {
                Text(tr("No stashes yet.", "Belum ada stash."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.stashes) { entry in
                            StashRow(entry: entry) { apply in
                                isPresented = false
                                Task {
                                    if apply { await store.applyStash(entry) } else { await store.popStash(entry) }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(14)
        .frame(width: 420)
    }

    private func stashNow() {
        guard changeCount > 0 else { return }
        let text = message
        isPresented = false
        Task { await store.stash(message: text.isEmpty ? nil : text) }
    }
}

private struct StashRow: View {
    let entry: StashEntry
    let onRestore: (_ apply: Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.ref)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.lane(1))
                .fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Text(entry.date, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 6)
            Button("Apply") { onRestore(true) }
                .help(tr("Apply and keep the stash", "Terapkan, stash tetap disimpan"))
            Button("Pop") { onRestore(false) }
                .help(tr("Apply and remove it from the list (kept if it conflicts)", "Terapkan lalu hapus dari daftar (tetap disimpan kalau konflik)"))
        }
        .controlSize(.small)
        .padding(.vertical, 4)
    }
}
