# Git AppBar

Menu bar app macOS untuk melihat dan mengelola banyak repo git sekaligus —
changes, history, branch, commit, fetch/pull/push, stash — dari panel transparan
selebar layar di bawah menu bar.

> Status: **M0** (shell app). Lihat [PLAN.md](PLAN.md).

## Build & run

```bash
swift run              # dev run cepat (tanpa fitur bundle)
swift test             # unit test GitAppBarCore
./make_app.sh          # build GitAppBar.app
open GitAppBar.app
```

Buka panel langsung saat launch (untuk dev):

```bash
GAB_OPEN_ON_LAUNCH=1 swift run
```

## Struktur

| Path | Isi |
|---|---|
| `Sources/GitAppBar/` | App: AppDelegate, PanelController, Preferences, Views |
| `Sources/GitAppBarCore/` | Model, GitRunner, parser output git (tanpa UI, bisa di-test) |
| `Tests/GitAppBarCoreTests/` | Unit test parser |
| `Info.plist` | LSUIElement, bundle id |
| `make_app.sh` | Build release + rakit `.app` + ad-hoc codesign |

## Requirements

macOS 14+, Xcode / Swift 6 toolchain, `git` di `/usr/bin/git`.
