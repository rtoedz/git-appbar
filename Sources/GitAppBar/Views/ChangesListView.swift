import SwiftUI
import GitAppBarCore

/// Read-only list of working-tree changes for the selected repo (actions come in M2).
struct ChangesListView: View {
    let repo: RepoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(repo.name).font(.system(size: 18, weight: .semibold))
                if let branch = repo.status?.branch {
                    Text("⎇ \(branch)")
                        .font(Theme.mono)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
                }
                if let up = repo.status?.upstream {
                    Text("→ \(up)").font(Theme.mono).foregroundStyle(Theme.textDim)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Rectangle().fill(Theme.divider).frame(height: 1)

            if let status = repo.status {
                if status.changes.isEmpty {
                    Text("Working tree bersih. Tidak ada perubahan.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Text("CHANGES · \(status.changes.count)")
                                .font(.system(size: 11))
                                .tracking(0.8)
                                .foregroundStyle(Theme.textDim)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 6)
                            ForEach(status.changes) { change in
                                ChangeRow(change: change)
                            }
                        }
                        .padding(10)
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
    }
}

private struct ChangeRow: View {
    let change: FileChange

    private var fileName: String { (change.path as NSString).lastPathComponent }
    private var directory: String { (change.path as NSString).deletingLastPathComponent }

    private var badgeColors: (Color, Color) {
        switch change.badge {
        case "U", "A": return (Color(red: 0.11, green: 0.23, blue: 0.17), Theme.added)
        case "D": return (Color(red: 0.24, green: 0.12, blue: 0.13), Color(red: 1.0, green: 0.60, blue: 0.62))
        case "!": return (Color(red: 0.24, green: 0.12, blue: 0.13), Color(red: 1.0, green: 0.60, blue: 0.62))
        default: return (Color(red: 0.23, green: 0.18, blue: 0.09), Theme.modified)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(change.badge)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(badgeColors.1)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(badgeColors.0))
            Text(fileName).font(.system(size: 14))
            Text(directory)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            if change.isStaged {
                Text("staged").font(.system(size: 11)).foregroundStyle(Theme.added)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}
