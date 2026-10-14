import Foundation
import Observation
import GitAppBarCore

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case indonesian = "id"

    var id: String { rawValue }

    /// Shown in its own language so it is recognisable whatever is selected.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .indonesian: return "Bahasa Indonesia"
        }
    }

    var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .indonesian: return Locale(identifier: "id_ID")
        }
    }
}

/// Current UI language. Observable, so every view that calls `tr` re-renders
/// immediately when the language changes in Preferences.
@Observable
final class Localizer {
    static let shared = Localizer()
    var language: AppLanguage = .english
    var locale: Locale { language.locale }
}

/// Inline translation: `tr("Fetch all", "Fetch semua")`.
func tr(_ english: String, _ indonesian: String) -> String {
    Localizer.shared.language == .indonesian ? indonesian : english
}

/// English count with singular/plural noun: `count(1, "file")` → "1 file",
/// `count(3, "repo")` → "3 repos". Indonesian nouns don't inflect, so callers
/// pass the plain number there.
func count(_ n: Int, _ noun: String, _ plural: String? = nil) -> String {
    "\(n) " + (n == 1 ? noun : (plural ?? noun + "s"))
}

/// User-facing text for errors coming out of GitAppBarCore.
func localizedMessage(_ error: Error) -> String {
    if let e = error as? GitActionError {
        switch e {
        case .emptyMessage:
            return tr("Write a commit message first.", "Tulis pesan commit dulu.")
        case .nothingSelected:
            return tr("Select at least 1 file to commit.", "Pilih minimal 1 file untuk di-commit.")
        case .unresolvedConflicts:
            return tr("There are unresolved merge conflicts. Resolve them in your editor first.",
                      "Masih ada konflik merge. Selesaikan di editor dulu.")
        case .noUpstreamToPull:
            return tr("This branch has no upstream on the remote, so there is nothing to pull.",
                      "Branch ini belum punya upstream di remote, jadi tidak ada yang bisa di-pull.")
        case .behindRemote(let n):
            return tr("The remote has \(count(n, "commit")) you haven't pulled. Pull before pushing.",
                      "Remote punya \(n) commit yang belum kamu pull. Pull dulu sebelum push.")
        case .noRemote:
            return tr("This repository has no remote.", "Repo ini tidak punya remote.")
        case .detachedHead:
            return tr("HEAD is detached. Switch to a branch first.",
                      "HEAD sedang detached. Pindah ke sebuah branch dulu.")
        }
    }
    if let e = error as? GitError, e.timedOut {
        return tr("git \(e.args.first ?? "") stopped responding and was cancelled. Check your connection or remote authentication.",
                  "git \(e.args.first ?? "") tidak merespons dan dihentikan. Cek koneksi atau autentikasi remote.")
    }
    if let e = error as? LocalizedError, let text = e.errorDescription { return text }
    return error.localizedDescription
}
