import SwiftUI

/// "Open in editor?" shown as an overlay inside the panel, so it is always on
/// top of it. Return opens, Esc / Cancel dismisses.
struct OpenConfirmDialog: View {
    @Environment(RepoStore.self) private var store
    @Environment(Preferences.self) private var prefs
    let pending: PendingOpen
    @State private var dontAskAgain = false

    private var editor: String { EditorOpener.editorName(for: pending.command) }
    private var fileName: String { (pending.path as NSString).lastPathComponent }
    private var commandLine: String {
        "\(pending.command.isEmpty ? "open" : pending.command) \((pending.file.path as NSString).abbreviatingWithTildeInPath)"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { cancel() }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.behind)
                    Text(tr("Open in \(editor)?", "Buka di \(editor)?"))
                        .font(.system(size: 16, weight: .semibold))
                }

                Text(tr("\(fileName) will be opened with:", "\(fileName) akan dibuka dengan:"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textDim)

                Text(commandLine)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))

                if pending.fromHistory {
                    Label(tr("This opens the current version in your working tree, not the version from this commit.",
                             "Yang dibuka adalah versi sekarang di working tree, bukan versi dari commit ini."),
                          systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.modified)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Toggle(tr("Don't ask again", "Jangan tanya lagi"), isOn: $dontAskAgain)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                    Spacer()
                    Button(tr("Cancel", "Batal"), action: cancel)
                        .keyboardShortcut(.cancelAction)
                    Button(tr("Open", "Buka"), action: confirm)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .foregroundStyle(Theme.text)
            .padding(20)
            .frame(width: 460)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.15))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            )
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }

    private func cancel() {
        store.pendingOpen = nil
    }

    private func confirm() {
        if dontAskAgain { prefs.confirmBeforeOpening = false }
        let target = pending
        store.pendingOpen = nil
        EditorOpener.open(target.file, command: target.command)
    }
}
