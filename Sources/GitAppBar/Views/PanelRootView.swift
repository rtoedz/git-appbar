import SwiftUI

struct PanelRootView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(RepoStore.self) private var store
    @State private var showPreferences = false
    @Environment(\.debugRender) private var debugRender

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.divider).frame(height: 1)
            HStack(spacing: 0) {
                RepoListView()
                    .frame(width: 300)
                Rectangle().fill(Theme.divider).frame(width: 1)
                Group {
                    if let repo = store.selected {
                        RepoDetailView(repo: repo)
                            .id(repo.id)
                    } else {
                        placeholder(tr("Select a repository on the left.", "Pilih repo di kiri."))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Theme.divider).frame(width: 1)
                CommitDetailView(repo: store.selected)
                    .frame(width: 420)
                    .frame(maxHeight: .infinity)
                    .background(Color.white.opacity(0.025))
            }
        }
        .foregroundStyle(Theme.text)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .environment(\.locale, Localizer.shared.locale)
        .onAppear { if !debugRender { rescan() } }
        .onChange(of: prefs.rootFolders) { rescan() }
        .onChange(of: prefs.scanDepth) { rescan() }
    }

    private func rescan() {
        store.rescan(roots: prefs.rootFolderURLs, depth: prefs.scanDepth)
    }

    private var background: some View {
        ZStack {
            if prefs.blur && !debugRender {
                VisualEffectBackground()
            }
            Theme.panel.opacity(prefs.opacity)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Source Control").font(.system(size: 15, weight: .semibold))
            Text(tr("\(count(store.repos.count, "repo")) · \(count(prefs.rootFolders.count, "folder"))", "\(store.repos.count) repo · \(prefs.rootFolders.count) folder"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
            Spacer()
            Button {
                Task { await store.fetchAll() }
            } label: {
                HStack(spacing: 6) {
                    if store.isFetchingAll {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(tr("Fetch all", "Fetch semua"))
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isFetchingAll || store.repos.isEmpty)
            .help(tr("git fetch --prune in every repository", "git fetch --prune di semua repo"))
            Button {
                showPreferences.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Preferences", "Preferensi"))
            .popover(isPresented: $showPreferences, arrowEdge: .bottom) {
                PreferencesView()
                    .environment(prefs)
                    .environment(\.locale, Localizer.shared.locale)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textDim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
