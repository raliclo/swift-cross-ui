# macOS harness: what `test.zsh Pn --macos` does

Written 2026-10-24 from testapp/test.zsh, testapp/test_support/test_common.zsh
(`run_macos`, `wait_for_marker_macos`, `print_summary_macos`) and
testapp/compile.zsh.

## What

One command builds, launches, captures and closes one test app on this Mac:

```sh
zsh testapp/test.zsh P28 --macos --actionfile          # AppKitBackend
TEST_BACKEND=gtk4 zsh testapp/test.zsh P28 --macos     # GtkBackend, Homebrew GTK
```

Steps, in order:

1. **Target.** On a Darwin host the drivable targets are `macos`, `ios` and
   `android`; the default is `macos`. Most `test_Pn.zsh` files declare a Windows
   or WSL target; on a Mac that declaration is replaced and the run says so. An
   explicit `--wsl` on a Mac is refused, never redirected.
2. **Lock.** `testapp/ui-lock.zsh` is acquired for `test-<pn>` so two UI tests
   cannot photograph each other (up to 60 s wait; `SCUI_NO_UI_LOCK=1` skips it).
   INT and TERM release it (since 2026-09-30).
3. **Build.** `compile.zsh Pn` (or `compile.zsh -gtk4 Pn`). `SCUI_DEBUG`
   defaults to 1, so `-actionfile` and `--debug` exist in the release build;
   `SCUI_DEBUG=0` opts out. AppKit builds live in `testapp/.compile-work-appkit`,
   GTK builds in `.compile-work-gtk4`. The GTK binary is `output/Pn-gtk4`, so it
   never overwrites the AppKit `output/Pn`. `-n`/`--no-build` skips this step.
4. **Launch** from `.macApp/debugTarget.app` (see debugtarget-bundle.md), with
   `SCUI_DEBUG_EVENTS_DIR=testapp/debug-events`, arguments from `TEST_APP_ARGS`
   (default `--debug`), plus `-actionfile <file>` when given. stdout and stderr
   both go to `output/<app>-actionfile.log`.
5. **Captures**: `<pn>-macos-1s` one second after launch; then wait for
   `TEST_MARKER` (e.g. `RENDER COMPLETE`) in `debug-events/<pn>-debug-events.log`,
   up to `TEST_TIMEOUT_SECONDS` (30). On a timeout, `<pn>-macos-timeout`.
6. **Replay wait.** With an action file, poll the log for
   `-actionfile: (replayed|failed)` for up to 600 s, and stop early when neither
   `debugTarget` nor `Pn` is running any more.
7. **Showtime** (`--showtime N`, default 30 s), then `<pn>-macos-final`, of the
   window titled `TEST_TITLE` unless `TEST_FINAL_CAPTURE=desktop`.
8. **Close**: `pkill -TERM -x debugTarget` and `-x Pn`, then print the diagnostic
   lines matching `TEST_SUMMARY_PATTERN` and, with `SCUI_UPDATE_STATS=1`, the
   app's `update-stats:` line (otherwise "update-stats: off").

With `TEST_BACKEND=gtk4` the labels carry `-gtk4` (`p28-macos-gtk4-final-*.png`);
action files, captures and the replay wait are otherwise shared.

## Why each step is there

- **Replay before showtime** (2026-09-27): the showtime used to start at the
  render marker, so a replay longer than it was cut off and the "final" capture
  showed it half done (found by sweep_apple.zsh on P72 with a 2 s showtime).
- **Stop when the app is gone** (70e217b0, 2026-10-22): a GTK app quits with its
  last window; P75-close-the-window on GtkBackend made the loop wait the full
  600 s for a line nobody was left to print.
- **Both process names**: a bundled run is always called `debugTarget`; killing
  by `Pn` alone misses it.
- **stdout kept** (2026-10-22): `[Pn]` lines printed by the app are the evidence
  of what a click did.
- **Debug-events directory created before launch**: the app writes through
  `try?`, so a missing directory looks like an app that never logged.
- **ZERR trap**: a failure inside `run_macos` before the launch once left the
  lock held, and `sweep_drive_macos.zsh` waited 900 s per later app (2026-10-07).

## How to apply

- Per-app settings belong in `test_support/test_Pn.zsh`: `TEST_TITLE`,
  `TEST_MARKER`, `TEST_FINAL_CAPTURE`, `TEST_APP_ARGS`, `TEST_TIMEOUT_SECONDS`.
- A file that needs launch arguments states them as `# launch-args: -rows 500`;
  sweep_apple.zsh passes them through `TEST_APP_ARGS`, keeping `--debug`.
- An app that imports the WinUI products (P6) has no `-gtk4` build; use P6-v2.

## Limits

- `--showtime` short and no action file is the "at rest" capture used by the
  pairs decks; it asserts nothing.
- A replay that reports `replayed` only says every row ran, not that the file's
  stated end state was reached; read the final capture.

---

# macOS harness:`test.zsh Pn --macos` 做了什麼

2026-10-24 依 testapp/test.zsh、testapp/test_support/test_common.zsh(`run_macos`、`wait_for_marker_macos`、
`print_summary_macos`)與 testapp/compile.zsh 寫成。

## 是什麼

一個指令在這台 Mac 上建置、啟動、擷圖並關閉一支測試 app:

```sh
zsh testapp/test.zsh P28 --macos --actionfile          # AppKitBackend
TEST_BACKEND=gtk4 zsh testapp/test.zsh P28 --macos     # GtkBackend,Homebrew GTK
```

依序:

1. **目標。** Darwin 主機能驅動的目標是 `macos`、`ios`、`android`,預設 `macos`。多數 `test_Pn.zsh` 宣告的是
   Windows 或 WSL;在 Mac 上該宣告會被替換並明講。在 Mac 上明確指定 `--wsl` 會被拒絕，不會改道。
2. **鎖。** 以 `test-<pn>` 取得 `testapp/ui-lock.zsh`,讓兩個 UI 測試不會互拍(最多等 60 秒;`SCUI_NO_UI_LOCK=1`
   可略過)。INT 與 TERM 都會釋放它(自 2026-09-30)。
3. **建置。** `compile.zsh Pn`(或 `compile.zsh -gtk4 Pn`)。`SCUI_DEBUG` 預設為 1,release 建置內就有
   `-actionfile` 與 `--debug`;`SCUI_DEBUG=0` 可退出。AppKit 建置在 `testapp/.compile-work-appkit`,GTK 在
   `.compile-work-gtk4`。GTK 執行檔是 `output/Pn-gtk4`,不會蓋掉 AppKit 的 `output/Pn`。`-n`/`--no-build` 略過此步。
4. **啟動**:從 `.macApp/debugTarget.app`(見 debugtarget-bundle.md),帶 `SCUI_DEBUG_EVENTS_DIR=testapp/debug-events`、
   `TEST_APP_ARGS` 的參數(預設 `--debug`),有動作檔時再加 `-actionfile <檔>`。stdout 與 stderr 都寫進
   `output/<app>-actionfile.log`。
5. **擷圖**:啟動一秒後拍 `<pn>-macos-1s`;接著在 `debug-events/<pn>-debug-events.log` 等 `TEST_MARKER`(例如
   `RENDER COMPLETE`),最多 `TEST_TIMEOUT_SECONDS`(30)秒;逾時則拍 `<pn>-macos-timeout`。
6. **等重放。** 有動作檔時，在 log 中輪詢 `-actionfile: (replayed|failed)`,最多 600 秒;`debugTarget` 與 `Pn`
   都不在時提早停止。
7. **Showtime**(`--showtime N`,預設 30 秒),然後拍 `<pn>-macos-final`,對象是標題為 `TEST_TITLE` 的視窗，除非
   `TEST_FINAL_CAPTURE=desktop`。
8. **關閉**:`pkill -TERM -x debugTarget` 與 `-x Pn`,印出符合 `TEST_SUMMARY_PATTERN` 的診斷行；設了
   `SCUI_UPDATE_STATS=1` 時再印 app 的 `update-stats:` 行(否則印「update-stats: off」)。

`TEST_BACKEND=gtk4` 時標籤帶 `-gtk4`(`p28-macos-gtk4-final-*.png`);動作檔、擷圖與重放等待其餘皆共用。

## 各步驟的理由

- **先等重放再 showtime**(2026-09-27):showtime 原本從算繪 marker 起算，比它長的重放會被截斷,「final」擷圖拍到
  做到一半的畫面(sweep_apple.zsh 以 2 秒 showtime 跑 P72 時發現)。
- **app 不在就停**(70e217b0,2026-10-22):GTK app 在最後一個視窗關閉時結束;GtkBackend 上的 P75-close-the-window
  讓迴圈為一行已無人會印的字等滿 600 秒。
- **兩個行程名**:經 bundle 的執行一律叫 `debugTarget`,只用 `Pn` 去 kill 會落空。
- **保留 stdout**(2026-10-22):app 印出的 `[Pn]` 行就是一次點擊做了什麼的證據。
- **啟動前建立 debug-events 目錄**:app 經 `try?` 寫入，目錄不存在時看起來就像 app 從未寫 log。
- **ZERR trap**:`run_macos` 在啟動前失敗曾讓鎖留著，`sweep_drive_macos.zsh` 之後每支 app 都等 900 秒(2026-10-07)。

## 怎麼用

- 每支 app 的設定放在 `test_support/test_Pn.zsh`:`TEST_TITLE`、`TEST_MARKER`、`TEST_FINAL_CAPTURE`、
  `TEST_APP_ARGS`、`TEST_TIMEOUT_SECONDS`。
- 需要啟動參數的動作檔以一行 `# launch-args: -rows 500` 寫明;sweep_apple.zsh 經 `TEST_APP_ARGS` 傳入並保留 `--debug`。
- 匯入 WinUI product 的 app(P6)沒有 `-gtk4` 建置;改用 P6-v2。

## 限制

- `--showtime` 很短又不帶動作檔，是 pairs 簡報用的「靜止」擷圖，不斷言任何東西。
- 重放回報 `replayed` 只代表每一列都執行了，不代表檔案所寫的結束狀態達成；要看最終擷圖。
