import SwiftUI
import GitAppBarCore

enum GraphStyle {
    static let laneWidth: CGFloat = 14
    static let inset: CGFloat = 10
    static let rowHeight: CGFloat = 30
    static func x(_ lane: Int) -> CGFloat { inset + CGFloat(lane) * laneWidth }
    static func width(lanes: Int) -> CGFloat { inset * 2 + CGFloat(max(lanes - 1, 0)) * laneWidth }
}

struct HistoryView: View {
    @Environment(RepoStore.self) private var store
    @Environment(Preferences.self) private var prefs
    let repo: RepoItem

    var body: some View {
        if store.historyLoading && store.history.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.history.isEmpty {
            Text("Belum ada commit.")
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let graphWidth = GraphStyle.width(lanes: store.graphLaneCount)
            PanelScroll {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.history.indices, id: \.self) { i in
                        let commit = store.history[i]
                        let row = store.graph[i]
                        CommitRow(
                            commit: commit,
                            row: row,
                            graphWidth: graphWidth,
                            isSelected: store.selectedCommitHash == commit.hash,
                            isExpanded: store.expandedCommits.contains(commit.hash),
                            currentBranch: repo.status?.branch
                        ) {
                            store.toggleCommit(commit.hash)
                        }
                        if store.expandedCommits.contains(commit.hash) {
                            ExpandedFiles(repo: repo, hash: commit.hash, lanes: row.lanesBelow, graphWidth: graphWidth)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

private struct CommitRow: View {
    let commit: CommitEntry
    let row: GraphRow
    let graphWidth: CGFloat
    let isSelected: Bool
    let isExpanded: Bool
    let currentBranch: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                GraphCell(row: row, isHead: commit.isHead, isMerge: commit.isMerge)
                    .frame(width: graphWidth, height: GraphStyle.rowHeight)
                Text(commit.subject)
                    .font(.system(size: 13, weight: commit.isHead ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.behind : Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                ForEach(commit.refs.prefix(3), id: \.self) { ref in
                    RefPill(ref: ref, isCurrent: ref == currentBranch && commit.isHead)
                }
                Spacer(minLength: 8)
                Text(commit.author)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                    .frame(minWidth: 70, maxWidth: 130, alignment: .trailing)
                    .layoutPriority(1)
                Text(commit.date, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                    .frame(width: 92, alignment: .trailing)
                Text(commit.shortHash)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize()
            }
            .padding(.trailing, 14)
            .frame(height: GraphStyle.rowHeight)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(commit.author) · \(commit.date.formatted(date: .abbreviated, time: .shortened))")
    }

    private var rowBackground: some View {
        Rectangle().fill(
            isSelected ? Color(red: 0.15, green: 0.17, blue: 0.23)
            : hovering ? Color.white.opacity(0.04) : .clear
        )
        .overlay(
            Rectangle().strokeBorder(isSelected ? Color(red: 0.23, green: 0.33, blue: 0.52) : .clear)
        )
    }
}

struct RefPill: View {
    let ref: String
    let isCurrent: Bool

    private var isTag: Bool { ref.hasPrefix("tag: ") }
    private var isRemote: Bool { !isTag && ref.contains("/") && ref.split(separator: "/").first.map { ["origin", "upstream"].contains(String($0)) } == true }
    private var label: String { isTag ? String(ref.dropFirst(5)) : ref }
    private var icon: String { isTag ? "tag" : isRemote ? "cloud" : "arrow.triangle.branch" }
    private var color: Color { isTag ? Theme.modified : isRemote ? Theme.lane(1) : Theme.lane(0) }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isCurrent ? "scope" : icon).font(.system(size: 9, weight: .semibold))
            Text(label).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(height: 18)
        .foregroundStyle(isCurrent ? Color.white : color)
        .background(Capsule().fill(isCurrent ? color.opacity(0.85) : color.opacity(0.16)))
        .fixedSize()
    }
}

/// Draws one row of the commit graph: incoming edges (top half), outgoing edges
/// (bottom half) and the commit dot.
struct GraphCell: View {
    let row: GraphRow
    let isHead: Bool
    let isMerge: Bool

    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            for e in row.top {
                ctx.stroke(edge(from: CGPoint(x: GraphStyle.x(e.from), y: 0), to: CGPoint(x: GraphStyle.x(e.to), y: mid)),
                           with: .color(Theme.lane(e.from)), lineWidth: 2)
            }
            for e in row.bottom {
                ctx.stroke(edge(from: CGPoint(x: GraphStyle.x(e.from), y: mid), to: CGPoint(x: GraphStyle.x(e.to), y: size.height)),
                           with: .color(Theme.lane(e.to)), lineWidth: 2)
            }
            let c = CGPoint(x: GraphStyle.x(row.column), y: mid)
            let color = Theme.lane(row.column)
            if isHead {
                let r: CGFloat = 6
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Theme.panel))
                ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2.5)
            } else {
                let r: CGFloat = isMerge ? 3.5 : 4.5
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }

    private func edge(from a: CGPoint, to b: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        if a.x == b.x {
            p.addLine(to: b)
        } else {
            let dy = b.y - a.y
            p.addCurve(to: b, control1: CGPoint(x: a.x, y: a.y + dy * 0.6), control2: CGPoint(x: b.x, y: b.y - dy * 0.6))
        }
        return p
    }
}

/// Vertical lane lines that keep the graph continuous through expanded content.
private struct GraphContinuation: View {
    let lanes: Set<Int>

    var body: some View {
        Canvas { ctx, size in
            for lane in lanes {
                var p = Path()
                p.move(to: CGPoint(x: GraphStyle.x(lane), y: 0))
                p.addLine(to: CGPoint(x: GraphStyle.x(lane), y: size.height))
                ctx.stroke(p, with: .color(Theme.lane(lane)), lineWidth: 2)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ExpandedFiles: View {
    @Environment(RepoStore.self) private var store
    @Environment(Preferences.self) private var prefs
    let repo: RepoItem
    let hash: String
    let lanes: Set<Int>
    let graphWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            GraphContinuation(lanes: lanes).frame(width: graphWidth)
            VStack(alignment: .leading, spacing: 0) {
                if let files = store.commitFiles[hash] {
                    if files.isEmpty {
                        Text("Tidak ada file berubah.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textDim)
                            .frame(height: 28)
                    }
                    ForEach(files) { file in
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
                } else {
                    ProgressView().controlSize(.small).frame(height: 28)
                }
            }
            .padding(.trailing, 10)
            .padding(.vertical, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
