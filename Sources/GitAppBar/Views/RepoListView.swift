import SwiftUI
import GitAppBarCore

struct RepoListView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(RepoStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("REPOSITORI · \(store.repos.count)")
                    .font(.system(size: 11))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textDim)
                Spacer()
                if store.isScanning {
                    ProgressView().controlSize(.small)
                }
                Button {
                    store.rescan(roots: prefs.rootFolderURLs, depth: prefs.scanDepth)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim)
                .help("Scan ulang folder")
                .accessibilityLabel("Scan ulang")
                .disabled(prefs.rootFolders.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if prefs.rootFolders.isEmpty {
                emptyNoFolder
            } else if store.repos.isEmpty && !store.isScanning {
                emptyNoRepo
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.repos) { repo in
                            RepoRow(repo: repo, isSelected: repo.id == store.selectedID)
                                .onTapGesture { store.selectedID = repo.id }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var emptyNoFolder: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textDim)
            Text("Pilih folder yang berisi repo git.\nSemua subfolder akan di-scan otomatis.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
            Button("Pilih folder…") {
                prefs.addFolders(FolderPicker.pickFolders())
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private var emptyNoRepo: some View {
        VStack(spacing: 10) {
            Text("Tidak ada repo git ditemukan\n(kedalaman \(prefs.scanDepth) level).")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
            Button("Tambah folder lain…") {
                prefs.addFolders(FolderPicker.pickFolders())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

private struct RepoRow: View {
    let repo: RepoItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(repo.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let s = repo.status, !s.changes.isEmpty {
                    Text("\(s.changes.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.10, green: 0.07, blue: 0.02))
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(Color(red: 0.91, green: 0.64, blue: 0.24)))
                }
            }
            HStack(spacing: 10) {
                if let error = repo.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .lineLimit(1)
                        .foregroundStyle(Theme.modified)
                } else if let s = repo.status {
                    Text("⎇ \(s.branch ?? "detached")").lineLimit(1)
                    if s.behind > 0 { Text("↓\(s.behind)").foregroundStyle(Theme.behind) }
                    if s.ahead > 0 { Text("↑\(s.ahead)").foregroundStyle(Theme.added) }
                    if s.isClean && s.ahead == 0 && s.behind == 0 { Text("✓ clean") }
                } else {
                    Text("memuat…")
                }
            }
            .font(Theme.mono)
            .foregroundStyle(Theme.textDim)
            Text(repo.parentPath)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color(red: 0.15, green: 0.16, blue: 0.21) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color(red: 0.23, green: 0.29, blue: 0.42) : .clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
