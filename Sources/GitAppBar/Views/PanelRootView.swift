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
                        placeholder("Pilih repo di kiri.")
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
            Text("\(store.repos.count) repo · \(prefs.rootFolders.count) folder")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
            Spacer()
            Button {
                showPreferences.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preferensi")
            .popover(isPresented: $showPreferences, arrowEdge: .bottom) {
                PreferencesView()
                    .environment(prefs)
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
