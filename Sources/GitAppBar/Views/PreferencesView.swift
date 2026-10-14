import SwiftUI

struct PreferencesView: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferensi").font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Opasitas background")
                    Spacer()
                    Text("\(Int(prefs.opacity * 100))%")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textDim)
                }
                Slider(value: $prefs.opacity, in: 0.3...1.0)
                HStack {
                    Text("Transparan")
                    Spacer()
                    Text("Solid")
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
            }

            Toggle("Blur di belakang panel (vibrancy)", isOn: $prefs.blur)

            Divider()

            FolderListSection()

            Stepper(value: $prefs.scanDepth, in: 1...8) {
                HStack {
                    Text("Kedalaman scan")
                    Spacer()
                    Text("\(prefs.scanDepth) level").font(Theme.mono).foregroundStyle(Theme.textDim)
                }
            }

            Divider()

            LabeledContent("Editor") {
                TextField("code -g", text: $prefs.editorCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono)
                    .frame(width: 170)
            }
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 360)
    }
}

/// Folders that are scanned for repos, with add (native picker) and remove.
struct FolderListSection: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folder yang di-scan")
            if prefs.rootFolders.isEmpty {
                Text("Belum ada folder.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
            }
            ForEach(prefs.rootFolders, id: \.self) { folder in
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(Theme.textDim)
                    Text(folder)
                        .font(Theme.mono)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        prefs.removeFolder(folder)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hapus folder \(folder)")
                }
            }
            Button {
                prefs.addFolders(FolderPicker.pickFolders())
            } label: {
                Label("Tambah folder…", systemImage: "plus")
            }
        }
    }
}
