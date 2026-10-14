import SwiftUI
import GitAppBarCore

enum RepoTab: String, CaseIterable {
    case changes = "Changes"
    case history = "History"
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
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(repo.name).font(.system(size: 18, weight: .semibold)).lineLimit(1)
            Button {
                showBranches.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(repo.status?.branch ?? "detached").lineLimit(1)
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
            .accessibilityLabel("Pindah branch")
            .popover(isPresented: $showBranches, arrowEdge: .bottom) {
                BranchPicker(repo: repo, isPresented: $showBranches)
                    .environment(store)
            }

            if let s = repo.status {
                if let up = s.upstream {
                    Text("→ \(up)").font(Theme.mono).foregroundStyle(Theme.textDim).lineLimit(1)
                }
                if s.behind > 0 { Text("↓\(s.behind)").font(Theme.mono).foregroundStyle(Theme.behind) }
                if s.ahead > 0 { Text("↑\(s.ahead)").font(Theme.mono).foregroundStyle(Theme.added) }
            }
            if store.isBusy { ProgressView().controlSize(.small) }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(RepoTab.allCases, id: \.self) { t in
                Button {
                    tab = t
                } label: {
                    HStack(spacing: 6) {
                        Text(t.rawValue)
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
                .accessibilityLabel("Tutup")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(banner.isError ? Color(red: 0.17, green: 0.14, blue: 0.09) : Color(red: 0.12, green: 0.16, blue: 0.13))
        )
    }
}

/// Working-tree changes for the repo (read-only until M2). Click opens the file.
struct ChangesContent: View {
    @Environment(Preferences.self) private var prefs
    let repo: RepoItem

    var body: some View {
        if let status = repo.status {
            if status.changes.isEmpty {
                Text("Working tree bersih. Tidak ada perubahan.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PanelScroll {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(status.changes) { change in
                            FileRow(
                                path: change.path,
                                badge: change.badge,
                                trailing: change.isStaged ? "staged" : nil
                            ) {
                                EditorOpener.open(repo.url.appendingPathComponent(change.path), command: prefs.editorCommand)
                            }
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
        .help(enabled ? "Buka di editor" : "File sudah dihapus")
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
