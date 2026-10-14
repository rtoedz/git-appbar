import SwiftUI
import GitAppBarCore

struct BranchPicker: View {
    @Environment(RepoStore.self) private var store
    let repo: RepoItem
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var pending: Branch?

    private var changeCount: Int { repo.status?.changes.count ?? 0 }

    private func matches(_ b: Branch) -> Bool {
        query.isEmpty || b.name.localizedCaseInsensitiveContains(query)
    }

    private var local: [Branch] { store.branches.filter { !$0.isRemote && matches($0) } }
    private var remote: [Branch] { store.branches.filter { $0.isRemote && matches($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pending {
                dirtyConfirm(pending)
            } else {
                TextField("Cari branch…", text: $query)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        section("Lokal", local)
                        section("Remote", remote)
                        if local.isEmpty && remote.isEmpty {
                            Text(store.branches.isEmpty ? "Memuat branch…" : "Tidak ada branch cocok.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textDim)
                                .padding(8)
                        }
                    }
                }
                .frame(height: 340)
            }
        }
        .padding(12)
        .frame(width: 380)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Branch]) -> some View {
        if !items.isEmpty {
            Text(title.uppercased())
                .font(.system(size: 11))
                .tracking(0.8)
                .foregroundStyle(Theme.textDim)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 2)
            ForEach(items) { branch in
                BranchRow(branch: branch) { choose(branch) }
            }
        }
    }

    private func choose(_ branch: Branch) {
        if branch.isCurrent || (branch.isRemote && branch.localName == repo.status?.branch) {
            isPresented = false
            return
        }
        if changeCount > 0 {
            pending = branch
        } else {
            go(branch, stash: false)
        }
    }

    private func go(_ branch: Branch, stash: Bool) {
        isPresented = false
        Task { await store.switchBranch(to: branch, stashFirst: stash) }
    }

    private func dirtyConfirm(_ branch: Branch) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pindah ke \(branch.localName)?")
                .font(.system(size: 14, weight: .semibold))
            Text("Ada \(changeCount) perubahan belum di-commit di \(repo.status?.branch ?? "branch ini").")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                go(branch, stash: true)
            } label: {
                Label("Stash dulu, lalu pindah", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button {
                go(branch, stash: false)
            } label: {
                Text("Bawa perubahan ke branch baru").frame(maxWidth: .infinity)
            }
            .help("Git menolak kalau perubahan bentrok dengan branch tujuan")
            Button("Batal") { pending = nil }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct BranchRow: View {
    let branch: Branch
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: branch.isCurrent ? "checkmark" : (branch.isRemote ? "cloud" : "arrow.triangle.branch"))
                    .frame(width: 14)
                    .foregroundStyle(branch.isCurrent ? Theme.added : Theme.textDim)
                Text(branch.name)
                    .font(Theme.mono)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(branch.date, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.white.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
