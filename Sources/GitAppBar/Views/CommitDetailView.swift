import SwiftUI
import AppKit
import GitAppBarCore

/// Right column: who committed what, when, and which files changed.
struct CommitDetailView: View {
    @Environment(RepoStore.self) private var store
    @Environment(Preferences.self) private var prefs
    let repo: RepoItem?
    @State private var copied = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("COMMIT DETAILS", "DETAIL COMMIT"))
                .font(.system(size: 11))
                .tracking(0.8)
                .foregroundStyle(Theme.textDim)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if let repo, let commit = store.selectedCommit {
                content(repo: repo, commit: commit)
            } else {
                Text(tr("Select a commit in the History tab\nto see its details.", "Pilih commit di tab Riwayat\nuntuk melihat detailnya."))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func content(repo: RepoItem, commit: CommitEntry) -> some View {
        let files = store.commitFiles[commit.hash]
        VStack(alignment: .leading, spacing: 14) {
            Text(store.commitMessages[commit.hash] ?? commit.subject)
                .font(.system(size: 15, weight: .semibold))
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(8)

            HStack(spacing: 10) {
                Text(initials(commit.author))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.86, green: 0.90, blue: 1.0))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.lane(stableIndex(commit.author)).opacity(0.35)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.author).font(.system(size: 14, weight: .medium))
                    Text(commit.email).font(.system(size: 12)).foregroundStyle(Theme.textDim).textSelection(.enabled)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text(tr("Date", "Tanggal")).foregroundStyle(Theme.textDim)
                    Text("\(commit.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))) · \(commit.date.formatted(.relative(presentation: .named).locale(locale)))")
                }
                GridRow {
                    Text("Hash").foregroundStyle(Theme.textDim)
                    HStack(spacing: 6) {
                        Text(commit.hash).font(Theme.mono).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(commit.hash, forType: .string)
                            copied = true
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textDim)
                        .accessibilityLabel(tr("Copy hash", "Salin hash"))
                    }
                }
                if !commit.parents.isEmpty {
                    GridRow {
                        Text(commit.isMerge ? "Parents" : "Parent").foregroundStyle(Theme.textDim)
                        Text(commit.parents.map { String($0.prefix(7)) }.joined(separator: ", ")).font(Theme.mono)
                    }
                }
                if !commit.refs.isEmpty {
                    GridRow {
                        Text("Ref").foregroundStyle(Theme.textDim)
                        HStack(spacing: 4) {
                            ForEach(commit.refs, id: \.self) { RefPill(ref: $0, isCurrent: false) }
                        }
                    }
                }
            }
            .font(.system(size: 12))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .onChange(of: commit.hash) { copied = false }

        Rectangle().fill(Theme.divider).frame(height: 1)

        HStack {
            Text(files.map { tr("\(count($0.count, "file")) changed", "\($0.count) file berubah") } ?? tr("Loading files…", "Memuat file…"))
            Spacer()
            if let files {
                Text("+\(files.compactMap(\.additions).reduce(0, +))").foregroundStyle(Theme.added)
                Text("−\(files.compactMap(\.deletions).reduce(0, +))").foregroundStyle(Theme.deleted)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(Theme.textDim)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)

        PanelScroll {
            LazyVStack(spacing: 0) {
                ForEach(files ?? []) { file in
                    FileRow(
                        path: file.path,
                        badge: file.status,
                        additions: file.additions,
                        deletions: file.deletions,
                        enabled: file.status != "D"
                    ) {
                        EditorOpener.open(repo.url.appendingPathComponent(file.path), command: prefs.editorCommand)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }

    /// Same author → same avatar color across launches (hashValue is randomized per process).
    private func stableIndex(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" })
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
