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
