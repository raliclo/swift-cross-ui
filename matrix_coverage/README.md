# matrix_coverage

Four files, and **two of them are matrices with opposite editing rules**. That
is the thing to get right before touching anything here.

| file | what it is | edit by hand? |
|---|---|---|
| `results.csv2` | run history: one row per app per run, append-only, never rewritten | **append only** |
| `coverage.zsh` | the generator | yes |
| `coverage.md` | Pn × platform, **generated** from `results.csv2` | **no — it is overwritten** |
| `coverage-matrix.csv2` | area × platform feature coverage, **hand-maintained** | **yes — nothing generates it** |

`coverage.md` and `coverage-matrix.csv2` are both "the coverage matrix" in
conversation and they are not the same table. `coverage.md` answers *has this
app been run on this platform, and when*; `coverage-matrix.csv2` answers *is
this feature covered, and by which test app*. Editing the first is wasted work
because the next `coverage.zsh` run replaces it. Regenerating over the second
would destroy it, because nothing can rebuild it.

Regenerate the first with:

```sh
zsh matrix_coverage/coverage.zsh
```

Both carry the six platforms: GTK/Linux, GTK/Windows, WinUI/Windows,
macOS/AppKit, iOS/UIKit and Android. In `coverage.md` a platform is a
`platform/backend` pair from `results.csv2`, and **a run whose pair matches no
column is reported on stderr rather than dropped** — that check caught two rows
recorded under ad-hoc backend labels the day it was added, which had been
silently missing from the table, where they read as "never tested".

`coverage-matrix.csv2` moved here from `testapp/` on 2026-08-27, when it gained
the three mobile and macOS columns. Nothing in the codebase referenced its path,
checked with `git grep` before the move rather than after.

## Who appends to `results.csv2`

One driver per platform. Each hard-codes its own `platform`/`backend` pair,
because the pair is a fact about the driver rather than a flag someone passes.

| driver | appends | how it runs an app |
|---|---|---|
| `testapp/sweep-test/sweep_drive.zsh` | `windows/gtk4` or `windows/winui` | tasklist, taskkill, gdigrab, `Pn.exe` |
| `testapp/sweep-test/sweep_drive_macos.zsh` | `mac/appkit` | drives `test.zsh <Pn> --macos` |

The macOS one is not a copy of the Windows one. It launches nothing itself:
`test.zsh <Pn> --macos` already builds, launches, waits for the render marker,
screenshots and closes on that platform, so the sweep is a loop, a reader of
that output and an appender. `verified-test-process.md` says not to write a new
harness.

Rows are appended with `csv2 -append`, not with a hand-written `printf >>`.
`-append` validates the row before writing and reads the existing file to check
its final record, so a malformed note or an already-truncated history is caught
at the point of writing rather than by whatever reads it next. The Windows
driver still quotes by hand; that is older, and it is the reason this note
exists.

Three things the macOS driver reads out of the run rather than assuming, each
of which was wrong in a first draft and would have put a false row in the table:

- **A missing `TEST_MARKER` is not a failure.** Eleven apps configure none, and
  `test_common.zsh` says so and falls back to timed capture. Reading only "did a
  marker appear" labelled all eleven as problems. Only `P37` and `P38` declare a
  marker and never print it.
- **The replay verdict is in the app's log, not the terminal.** `run_macos`
  launches with `>"$action_log"`, so the `-actionfile:` line never reaches
  stdout.
- **`-actionfile` needs a build with `SCUI_DEBUG`.** `test_common.zsh` only sets
  it when an action file is requested, so `-n` plus `--actionfile` yields an app
  with no replay support at all.

## 本資料夾說明

四個檔案，而**其中兩個是編輯規則完全相反的矩陣**——這是動任何東西之前必須先弄清楚的事（對照上表）。

`coverage.md` 與 `coverage-matrix.csv2` 在口語中都叫「coverage matrix」，但它們不是同一張表。前者
回答「某個 app 是否曾在某平台上跑過、何時跑的」；後者回答「某項功能是否已被涵蓋、由哪一支測試
app 涵蓋」。手動編輯前者是白費工夫，因為下一次執行 `coverage.zsh` 就會覆蓋它；而對後者執行「重新
產生」則會摧毀它，因為沒有任何東西能重建它。

兩者都涵蓋六個平台：GTK/Linux、GTK/Windows、WinUI/Windows、macOS/AppKit、iOS/UIKit 與 Android。
在 `coverage.md` 中，一個平台是 `results.csv2` 裡的 `platform/backend` 配對，而**若某筆執行的配對
不符合任何欄位，會在 stderr 上回報而非直接捨棄**——這項檢查在加入的當天就抓到兩筆以臨時 backend
標籤記錄的資料，它們原本悄悄地不在表中，讀起來就成了「從未測試過」。

`coverage-matrix.csv2` 於 2026-08-27 自 `testapp/` 移入此處，同時新增了三個行動裝置與 macOS 欄位。
程式碼中沒有任何地方引用它的路徑——這是在搬移**之前**以 `git grep` 查證的，而非事後才確認。

## 2026-09-04: Android filled, iOS still empty, and why they were filled differently

`results.csv2` gained 45 rows and `coverage.md` regenerated from them, so the
Android column now reads `pass` for every app that has an Android action file.
`coverage-matrix.csv2` gained 91 `✅` in its `android` column by the same
evidence.

**The dates came from the action files and the screenshots, not from a sweep.**
These runs were driven by hand rather than by `sweep_drive.zsh`, so nothing
appended the history at the time. 31 files record their own `REPLAYED <date>`;
the other 14 were dated from `testapp/output/screenshots/<app>-android-*-<date>.png`,
which `test_android.zsh` writes on every run. Every one of the 45 had one or the
other -- the script that appended them printed `NO EVIDENCE` for any app that
did not, and printed none.

**The iOS column was left at `-` on purpose.** 46 iOS action files exist and
record replays, so the evidence for filling it is the same *kind* as Android's.
It was not filled because I did not run them: this session drove Android, and
reading a date out of a file I did not produce and calling it a run is the step
this table exists to prevent. Filling it is a real task with its own evidence --
either re-run the sweep on the simulator, or reconcile from the files and label
the rows as reconciliation, which this file has precedent for (`P23` and `P24`
carry "by reconciliation, NOT a new run" in their notes).

**`executable-size.csv2` gained four columns**: `ios_uikit_bytes`,
`android_exe_bytes`, `android_apk_bytes` and `android_measured`. The last one is
there because the existing `measured` column cannot carry two dates, and the
Android figures were taken two days after the Windows, Linux and iOS ones.
`macos_appkit_bytes` is still empty for every app; nothing has measured it.

## 2026-09-04：Android 已填入、iOS 仍為空，以及兩者為何處理方式不同

`results.csv2` 新增 45 列，`coverage.md` 據以重新產生，因此 Android 欄現在對每一支「有 Android
動作檔」的 app 都顯示 `pass`。`coverage-matrix.csv2` 的 `android` 欄也依同一份證據新增了 91 個 `✅`。

**那些日期來自動作檔與截圖，而不是來自一次 sweep。** 這些執行是手動驅動的，不是由
`sweep_drive.zsh` 進行的，因此當時沒有任何東西把歷史附加上去。31 份檔案自己記錄了
`REPLAYED <日期>`；其餘 14 支的日期取自
`testapp/output/screenshots/<app>-android-*-<date>.png`——那是 `test_android.zsh` 每次執行都會寫入
的。45 支全都具備其中之一：附加這些列的腳本會對任何缺乏證據的 app 印出 `NO EVIDENCE`，而它一個
也沒印。

**iOS 欄是刻意留在 `-` 的。** 存在 46 份 iOS 動作檔且其中記錄了重放，因此填入它的證據與 Android
屬於同一**種類**。之所以沒有填，是因為那些不是我跑的：本次會期驅動的是 Android，而「從一份我沒有
產生的檔案中讀出一個日期、並稱之為一次執行」，正是這張表所要防止的那一步。填入它是一件有其自身
證據的實在工作——要嘛在模擬器上重跑該 sweep，要嘛從檔案進行對帳並把那些列標記為對帳，而本檔對此
有先例（`P23` 與 `P24` 的備註中寫著「by reconciliation, NOT a new run」）。

**`executable-size.csv2` 新增了四欄**：`ios_uikit_bytes`、`android_exe_bytes`、
`android_apk_bytes` 與 `android_measured`。最後一欄的存在，是因為既有的 `measured` 欄無法承載兩個
日期，而 Android 的數字是在 Windows、Linux 與 iOS 之後兩天才量的。`macos_appkit_bytes` 對每一支
app 仍為空；沒有任何東西量過它。
