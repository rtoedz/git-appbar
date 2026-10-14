# Git AppBar — Plan

Menu bar app macOS untuk source control multi-repo (seperti panel Source Control VS Code),
dibuka sebagai panel selebar layar di bawah menu bar.

## Keputusan
- Swift 6 toolchain, language mode v5, SwiftUI + AppKit, macOS 14+.
- SwiftPM tanpa dependency eksternal; `make_app.sh` membungkus jadi `.app` (LSUIElement).
- Tanpa sandbox (perlu akses folder repo + eksekusi `git`). Tidak untuk App Store.
- Semua data dari **git lokal** via `Process` (`/usr/bin/git`), bukan GitHub API.
- `GitAppBarCore` (library, bisa di-test) terpisah dari `GitAppBar` (UI).

## Arsitektur
| Bagian | Tanggung jawab |
|---|---|
| `AppDelegate` | `NSStatusItem`, toggle panel |
| `PanelController` | `NSPanel` borderless selebar layar, tutup saat klik di luar / Esc |
| `Preferences` | opasitas, blur, folder root, editor (UserDefaults) |
| `GitRunner` | jalankan git dengan PATH eksplisit, `GIT_TERMINAL_PROMPT=0` |
| `GitStatusParser` | parse `status --porcelain=v2 --branch -z` |
| `RepoStore` (M1) | discovery repo, refresh via FSEvents, auto-fetch |
| Views | RepoList, Changes + commit box, History, CommitDetail, Preferences |

## Milestone
- [x] **M0** — project, ikon menu bar, panel lebar transparan + Preferensi (opasitas, blur), parser status + test.
- [ ] **M1 Read-only** — scan repo di folder root, status per repo, history (`git log`), detail commit (`git show --numstat`), buka file di editor (`code -g`).
- [ ] **M2 Aksi** — stage/unstage, commit, commit & push, fetch, pull (`--ff-only`), push, stash push/pop/list, switch branch (auto-stash).
- [ ] **M3 Polish** — FSEvents live refresh, hotkey global ⌥⌘G, auto-fetch berkala, notifikasi, launch at login, ikon app.

## Guardrail (wajib di M2)
- Pull memakai `--ff-only`; kalau gagal, tampilkan pesan + tombol "Buka di editor", jangan auto-merge/rebase.
- Push diblokir kalau `behind > 0`.
- Commit butuh pesan + minimal 1 file ter-stage.
- Switch branch saat working tree kotor → tawarkan stash, jangan paksa.
- Tidak ada aksi destruktif (`reset --hard`, `clean -fd`, force push) di v1.

## Risiko
- App GUI tidak mewarisi PATH shell → `code`, `git-lfs`, hooks (husky) gagal. Set PATH eksplisit.
- Auth push/fetch: SSH agent & osxkeychain biasanya jalan dari launchd; prompt password tidak didukung (`GIT_TERMINAL_PROMPT=0`), error ditampilkan apa adanya.
- Repo besar: `status` bisa lambat → jalankan paralel terbatas + cache, refresh hanya repo yang berubah.
