import SwiftUI

struct PanelRootView: View {
    @Environment(Preferences.self) private var prefs
    @State private var showPreferences = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.divider).frame(height: 1)
            HStack(spacing: 0) {
                column(title: "Repositori", hint: "Daftar repo dari \(prefs.rootFolder) — M1")
                    .frame(width: 300)
                Rectangle().fill(Theme.divider).frame(width: 1)
                column(title: "Changes · History", hint: "Commit box, file berubah, history — M1/M2")
                    .frame(maxWidth: .infinity)
                Rectangle().fill(Theme.divider).frame(width: 1)
                column(title: "Detail commit", hint: "Author, tanggal, hash, file +/− — M1")
                    .frame(width: 440)
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
    }

    private var background: some View {
        ZStack {
            if prefs.blur {
                VisualEffectBackground()
            }
            Theme.panel.opacity(prefs.opacity)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Source Control").font(.system(size: 15, weight: .semibold))
            Text(prefs.rootFolder).font(.system(size: 12)).foregroundStyle(Theme.textDim)
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
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func column(title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11))
                .tracking(0.8)
                .foregroundStyle(Theme.textDim)
            Spacer()
            Text(hint)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(16)
        .frame(maxHeight: .infinity)
    }
}
