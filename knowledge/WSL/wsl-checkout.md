# The WSL checkout: /home/lowei/proj/swift-cross-ui is a copy, not a repo

Written 2026-10-24 from `testapp/rsync_WSL.zsh`,
testapp/gtk-test-plan-findings.md ("the WSL checkout is a separate, stale
copy") and `testapp/test_support/test_common.zsh`.

## What

The Windows machine has two trees. The Windows checkout is the git repository
where edits land. `/home/lowei/proj/swift-cross-ui` inside WSL is a separate
copy with no `.git`, restored by rsync after an earlier incident. It holds the
Linux `.build` (about 1.2 GB when noted), `.compile-work*` and
`testapp/output`, and every WSL build and launch happens there. The apps write
their event logs to `testapp/debug-events` in that copy.

## Why not build from /mnt/c

- Build output must stay per platform: the two sides produce `P7` and `P7.exe`
  from the same source, and Windows object files must not reach WSL.
- `/mnt/c` is 9p; scanning or compiling over it is slow (see the Segoe UI note
  in [theme-and-fonts.md](theme-and-fonts.md) for a measured cost of reading
  over 9p).
- An action file given as `/mnt/c/...` would replay whatever the Windows copy
  holds, not the synced one; `test.zsh` re-roots it.

## How it is kept in step

`testapp/rsync_WSL.zsh` (run by `test.zsh --wsl` unless `-n`) copies only:
`*.swift`, `*.c`, `*.h`, `*.modulemap`, `testapp/**/*.zsh`,
`testapp/install_tool_wsl.sh` and `testapp/actions/**/*.actions`. It excludes
`.git/`, `.build/`, `.swiftpm/`, `.compile-work*/`, `.tmp/` and `output/`.
`WSL_PROJECT_ROOT` or `--target` names another destination.

Each include exists because its absence once failed silently:

- C files: a new shim in `gtk_helpers.c` failed on WSL as "cannot find ... in
  scope", which reads as a Swift visibility problem.
- `install_tool_wsl.sh`: the WSL copy was still the 16 August version.
- `.actions`: the app reported the file missing while it sat in the Windows
  checkout.
- `.compile-work*/`, not `.compile-work/`: the per-backend trees did not match
  and a 7.9 GB Windows build tree was copied into WSL on every run
  (2026-09-04).

## How to apply

- Deletions do not propagate (no `--delete`, on purpose: WSL keeps its own
  build output and local edits). SwiftPM ignores directories `Package.swift`
  no longer declares, so the WSL build keeps succeeding on a tree that no
  longer matches: dropping GTK3 removed 193 files on Windows, all still in WSL
  afterwards. Delete them in WSL by hand.
- A WSL build without a sync first compiles the old sources and reports
  success. Sync, then trust the build.
- Nothing in the WSL copy is versioned. Edits made there are lost to git;
  make them in the Windows checkout and sync.
- Package files (`Package.swift`, `Package.resolved`) and other non-matching
  files are not synced by this script; changes to them need copying by hand.
  This follows from the include list; not separately verified.

---

# WSL checkout:/home/lowei/proj/swift-cross-ui 是複本，不是 repo

2026-10-24 依 `testapp/rsync_WSL.zsh`、testapp/gtk-test-plan-findings.md(「WSL 的 checkout 是另一份、且會過期的
複本」)與 `testapp/test_support/test_common.zsh` 寫成。

## 是什麼

Windows 機器上有兩棵樹。Windows checkout 是編輯落地的 git repo。WSL 內的 `/home/lowei/proj/swift-cross-ui` 是另一份
複本，沒有 `.git`,是先前事件後以 rsync 還原的。它存放 Linux 的 `.build`(記錄當時約 1.2 GB)、`.compile-work*` 與
`testapp/output`,每一次 WSL 建置與啟動都在那裡。app 的事件 log 寫在該複本的 `testapp/debug-events`。

## 為什麼不從 /mnt/c 建置

- 建置產物必須依平台分開：兩邊從同一份原始碼產出 `P7` 與 `P7.exe`,Windows 的目的檔不能進到 WSL。
- `/mnt/c` 走 9p,在上面掃描或編譯很慢(經 9p 讀取的實測成本見 [theme-and-fonts.md](theme-and-fonts.md) 的 Segoe UI
  註記)。
- 以 `/mnt/c/...` 給的動作檔會重放 Windows 那份當下的內容，而非同步過去的那份;`test.zsh` 會重新指向。

## 怎麼保持同步

`testapp/rsync_WSL.zsh`(`test.zsh --wsl` 在未加 `-n` 時執行)只複製:`*.swift`、`*.c`、`*.h`、`*.modulemap`、
`testapp/**/*.zsh`、`testapp/install_tool_wsl.sh` 與 `testapp/actions/**/*.actions`。排除 `.git/`、`.build/`、`.swiftpm/`、
`.compile-work*/`、`.tmp/` 與 `output/`。`WSL_PROJECT_ROOT` 或 `--target` 可指定其他目的地。

每一個 include 都是因為少了它曾經無聲地失敗:

- C 檔:`gtk_helpers.c` 新增的 shim 在 WSL 上報「cannot find ... in scope」,看起來像 Swift 的可見性問題。
- `install_tool_wsl.sh`:WSL 的副本仍是 8 月 16 日的版本。
- `.actions`:app 回報檔案不存在，而它就在 Windows checkout 裡。
- `.compile-work*/` 而非 `.compile-work/`:各 backend 的建置樹比對不到，每次執行都把 7.9 GB 的 Windows 建置樹複製進
  WSL(2026-09-04)。

## 怎麼用

- 刪除不會傳播(刻意不加 `--delete`:WSL 保有自己的建置產物與本地修改)。SwiftPM 會忽略 `Package.swift` 不再宣告的
  目錄，所以 WSL 會在已經不一致的樹上持續建置成功：移除 GTK3 時在 Windows 刪掉 193 個檔案，事後全部仍在 WSL。請在
  WSL 內手動刪除。
- 沒有先同步的 WSL 建置會編到舊原始碼並回報成功。先同步，再信任建置結果。
- WSL 複本中沒有任何東西受版本控制。在那裡做的修改 git 看不到；請在 Windows checkout 修改後再同步。
- 套件檔(`Package.swift`、`Package.resolved`)等不符合樣式的檔案不會被這支腳本同步，變更時需要手動複製。這是由
  include 清單推得的，未另行驗證。
