import SwiftUI

struct PreferencesView: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Preferences", "Preferensi")).font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Language", "Bahasa"))
                Picker(tr("Language", "Bahasa"), selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tr("Background opacity", "Opasitas background"))
                    Spacer()
                    Text("\(Int(prefs.opacity * 100))%")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textDim)
                }
                Slider(value: $prefs.opacity, in: 0.3...1.0)
                HStack {
                    Text(tr("Transparent", "Transparan"))
                    Spacer()
                    Text("Solid")
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
            }

            Toggle(tr("Blur behind the panel (vibrancy)", "Blur di belakang panel (vibrancy)"), isOn: $prefs.blur)

            Divider()

            FolderListSection()

            Stepper(value: $prefs.scanDepth, in: 1...8) {
                HStack(spacing: 4) {
                    Text(tr("Scan depth", "Kedalaman scan"))
                    InfoButton(
                        title: tr("Scan depth", "Kedalaman scan"),
                        text: tr("How many folder levels below each scanned folder are searched for git repositories. Example with 2: ~/Project/work/app is found, ~/Project/work/team/app is not. Searching stops inside a repository, and folders like node_modules, vendor and build are skipped. Higher values find more but scan slower.",
                                 "Seberapa dalam subfolder di bawah tiap folder yang dicari repo git-nya. Contoh dengan 2: ~/Project/kerjaan/app ketemu, ~/Project/kerjaan/tim/app tidak. Pencarian berhenti di dalam sebuah repo, dan folder seperti node_modules, vendor, dan build dilewati. Makin besar makin banyak yang ketemu, tapi scan makin lambat.")
                    )
                    Spacer()
                    Text(tr(count(prefs.scanDepth, "level"), "\(prefs.scanDepth) level")).font(Theme.mono).foregroundStyle(Theme.textDim)
                }
            }

            Divider()

            HStack(spacing: 4) {
                Text("Editor")
                InfoButton(
                    title: "Editor",
                    text: tr("The terminal command used to open a file when you click its name in Changes, History or Commit details. The file path is added at the end, e.g. code -g ~/Project/app/main.go.\n\nExamples: code -g (VS Code), cursor -g (Cursor), zed (Zed), subl (Sublime Text), open -a Xcode.\n\nIf the command fails, the file opens in the default macOS app.",
                             "Perintah terminal untuk membuka file saat kamu klik namanya di Perubahan, Riwayat, atau Detail commit. Path file ditambahkan di akhir, contoh: code -g ~/Project/app/main.go.\n\nContoh: code -g (VS Code), cursor -g (Cursor), zed (Zed), subl (Sublime Text), open -a Xcode.\n\nKalau perintahnya gagal, file dibuka dengan aplikasi default macOS.")
                )
                Spacer()
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
            HStack(spacing: 4) {
                Text(tr("Scanned folders", "Folder yang di-scan"))
                InfoButton(
                    title: tr("Scanned folders", "Folder yang di-scan"),
                    text: tr("Every git repository inside these folders (up to the scan depth) is listed on the left. Add a parent folder like ~/Project to pick up all your projects at once. Removing a folder only hides its repositories here; nothing is deleted.",
                             "Semua repo git di dalam folder-folder ini (sampai kedalaman scan) tampil di daftar kiri. Tambahkan folder induk seperti ~/Project supaya semua project langsung terbaca. Menghapus folder dari sini hanya menyembunyikan repo-nya, tidak ada file yang dihapus.")
                )
            }
            if prefs.rootFolders.isEmpty {
                Text(tr("No folders yet.", "Belum ada folder."))
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
                    .accessibilityLabel(tr("Remove folder ", "Hapus folder ") + folder)
                }
            }
            Button {
                prefs.addFolders(FolderPicker.pickFolders())
            } label: {
                Label(tr("Add folder…", "Tambah folder…"), systemImage: "plus")
            }
        }
    }
}
