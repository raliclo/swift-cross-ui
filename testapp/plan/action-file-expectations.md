# `# expect: log-contains` across testapp/actions/win — the survey behind the markers

Written 2026-09-07. Regenerate the marker list with:

```
for f in testapp/actions/win/*.csv; do
    e="$(grep -m1 -E '^# *expect: *log-contains .' "$f")"
    [ -n "$e" ] && printf '%s\t%s\n' "${f:t}" "${e#*log-contains }"
done
```

and the count of files with any marker with

```
grep -l -E '^# *expect: *(log-contains|process-exits)' testapp/actions/win/*.csv | wc -l
```

Numbers below are as of the day this was written. Re-derive rather than trust
them: this file records a snapshot of logs that keep being appended to.

---

## What the marker is, and what it is not

`sweep_drive.zsh` reads `# expect: log-contains <literal text>` out of the action
file and, after the replay finishes, searches **this run's** log output plus
**this run's new bytes** of `testapp/output/<app>-debug-events.log` for that
text, with `grep -F`. Found → the verdict it already had, plus a note. Not found
while the app wrote something → `UNMET`. Not found and the app wrote nothing at
all → `UNCHECKED`. See that script's own header for the four states.

Before this pass, two of the 41 win action files declared anything:
`P10-ctrl-q.csv` (`# expect: process-exits`) and `P44-clip-third-cell.csv`
(`# expect: log-contains third cell clipped: true`). The other 39 reported `ok`
for a replay that ran, whatever it achieved — and driving P44 on 2026-09-07
returned `ok / ok / window` while only a hand reading of the capture and the log
showed the button had done anything. A file whose clicks **all** missed returns
the same three words.

### The rule that bounded this pass

**A marker was applied only where evidence already on disk proves that exact
string appears for that app.** Not one was derived from reading the Swift alone:
a string in a source file may be formatted, interpolated, conditional, or
written to a stream the driver never sees. P44's own line proves the point — it
never reaches the run log, only the app's `-debug-events.log`, because Swift's
`print` to a redirected stdout is block-buffered and `taskkill /F` kills before
the flush.

The second test each candidate had to pass: **would this text be absent if every
click missed?** A line written at startup, or on every render, proves nothing
about a click, and is not an expectation however specific it looks. That test
alone disqualified P7 (910 lines), P17 (1034 lines) and P22 (91 lines) — all
three log heavily, and every line is a layout measurement emitted per frame.

### 這個標記是什麼、不是什麼

`sweep_drive.zsh` 會從動作檔中讀出 `# expect: log-contains <字面文字>`，並在重放結束後，
以 `grep -F` 在**本次執行**的 log 輸出、加上 `testapp/output/<app>-debug-events.log` 於
**本次執行新增的位元組**中尋找該段文字。找到 → 維持原判決並加註；沒找到但 app 有寫東西 →
`UNMET`；沒找到且 app 從頭到尾什麼都沒寫 → `UNCHECKED`。四種狀態見該腳本自身的檔頭。

在這一輪之前，41 個 win 動作檔中只有兩個有任何宣告：`P10-ctrl-q.csv` 與
`P44-clip-third-cell.csv`。其餘 39 個無論重放達成了什麼，都一律回報 `ok`——而 2026-09-07 驅動
P44 得到的是 `ok / ok / window`，唯有人工讀取擷圖與 log 才看得出那顆按鈕有沒有作用。一個
**每一次點擊都沒中**的檔案，回報的是一模一樣的三個字。

**只有在磁碟上既有的證據已證明「該 app 確實寫出過那段文字」時，才加上標記。** 沒有任何一個標記
是單憑閱讀 Swift 推導出來的：原始碼中的字串可能經過格式化、插值、帶條件，或寫往驅動器根本看不到
的串流。P44 自己的那一行就是明證——它從未抵達 run log，只抵達 app 自己的 `-debug-events.log`，
因為 Swift 的 `print` 在 stdout 被重導時採區塊緩衝，而 `taskkill /F` 在 flush 之前就殺掉了行程。

每個候選還必須通過第二項測試：**如果每一次點擊都沒中，這段文字還會出現嗎？** 在啟動時、或在每次
算繪時寫出的行，無論看起來多具體，都證明不了任何關於點擊的事，因而不是預期。光這一項就淘汰了
P7（910 行）、P17（1034 行）與 P22（91 行）——三者都寫得很多，而每一行都是逐幀寫出的版面量測。

---

## Where the evidence came from

No app was run for this survey. Everything below was read off files already on
disk, and the driver's own view is `testapp/output/`:

| Location | What it is |
| --- | --- |
| `testapp/output/*-debug-events.log` | 37 files; the copies the sweep driver reads, because it launches with that as the working directory |
| `testapp/*-debug-events.log` | the same apps run with `testapp/` as the working directory, 2026-09-05 13:00–13:25 |
| `<repo root>/*-debug-events.log` | the same apps run from the repo root, mostly 2026-09-03 |
| `/tmp/sweep_drive-gtk4/*.log` | 35 per-run driver logs; used to date runs and to attribute a line to one action file rather than another |

The three copies exist because several apps build their log path from
`currentDirectoryPath`, and `run.zsh` launches by absolute path without `cd`ing.
That turned out to be the single most useful fact in this survey: **eight apps
have their only interaction evidence outside `testapp/output/`** — P0, P28, P30,
P32, P33, P34, P35, P36 — because the sweep driver has never driven them, while
hand runs on 2026-09-03 and 2026-09-05 did, from other directories.

### 證據的來源

本調查沒有執行任何 app。以下全部讀自磁碟上既有的檔案，而驅動器所見的是 `testapp/output/`。
三份副本之所以存在，是因為有數支 app 以 `currentDirectoryPath` 組出 log 路徑，而 `run.zsh`
以絕對路徑啟動、不做 `cd`。這件事成了本次調查中最有用的一項事實：**有八支 app 唯一的互動證據
位於 `testapp/output/` 之外**——P0、P28、P30、P32、P33、P34、P35、P36——因為 sweep 驅動器從未
驅動過它們，而 2026-09-03 與 2026-09-05 的手動執行在別的目錄下做到了。

### Attributing a line to one file and not its neighbour

Six apps have more than one action file, and the apps append to one log, so
"P13 wrote this" is not "P13-zorder wrote this". Each such line was pinned by
matching the debug log's UTC timestamp against the mtime of the matching run log
in `/tmp/sweep_drive-gtk4/` (local time, UTC+8), and against the action file's
own sleep budget. Two cases turned on it:

- **P20.** `clicked: level 1` lands ~6 s into the *first* run of each pair —
  2026-09-06 14:10:48 UTC, inside `P20-disabled-item.log` which closed at
  14:10:50, and before `P20-open-level-1.log` which closed at 14:11:21. It
  belongs to `P20-disabled-item.csv`, whose header calls that click the
  positive control. `P20-open-level-1.csv` left **no** event line at all.
- **P13.** `z-order reversed` lands at 12:27:20 UTC, between
  `P13-duplicates-and-split.log` closing at 12:27:05 and `P13-zorder.log`
  closing at 12:27:21. It belongs to `P13-zorder.csv`.

### 把某一行歸屬到某一個檔案，而非它的鄰居

有六支 app 擁有不只一個動作檔，而 app 只寫一份 log，因此「P13 寫了這一行」不等於
「P13-zorder 寫了這一行」。每一行都以「debug log 的 UTC 時戳」對照
`/tmp/sweep_drive-gtk4/` 中對應 run log 的 mtime（本地時間，UTC+8），再對照該動作檔自身的
sleep 預算來釘定歸屬。有兩個案例正是由此決定，見上方英文段落。

---

## The table — all 41 files

`marker` is the literal text after `log-contains`. `evidence` is the file the
text was read from. Paths are relative to the repo root.

| # | file | app | marker | evidence | if not marked, why |
| --- | --- | --- | --- | --- | --- |
| 1 | P0-present-environment-alert.csv | P0 | `immediate alert button clicked` | `p0-debug-events.log`, `testapp/p0-debug-events.log` | — |
| 2 | P1-open-root-sheet.csv | P1 | — | — | P1 writes no debug-events log anywhere on disk; the verdict is the capture |
| 3 | P10-ctrl-q.csv | P10 | *(pre-existing)* `# expect: process-exits` | — | already done; not touched |
| 4 | P10-hit-testing.csv | P10 | — | — | `p10-debug-events.log` holds `RENDER COMPLETE` and nothing else, 18 times over |
| 5 | P13-duplicates-and-split.csv | P13 | — | — | neither "More duplicates" nor "Narrower" writes; the only P13 interaction line belongs to the other P13 file |
| 6 | P13-zorder.csv | P13 | `z-order reversed -- top should now be red` | `testapp/output/p13-debug-events.log` | — |
| 7 | P15-colour-scheme.csv | P15 | — | — | `p15-debug-events.log` holds only `RENDER COMPLETE`, once per launch |
| 8 | P16-force-update-winui.csv | P16 | — | — | `p16-debug-events.log` holds startup arguments, `RENDER COMPLETE` and per-render `sidebar:`/`detail:` sizes; nothing from the button |
| 9 | P17-picker-and-sizes.csv | P17 | — | — | 1034 lines, five shapes, all layout measurements emitted on every render |
| 10 | P18-three-dialogs.csv | P18 | `open: cancelled` | `p18-debug-events.log` (repo root, 2026-09-03) | — (**expected to report UNMET today** — see the note below) |
| 11 | P19-menu-open.csv | P19 | — | — | the file deliberately has no click and no readout; its own header says the picture is the only evidence there is |
| 12 | P19-open-and-select.csv | P19 | `clicked: second button item` | `testapp/output/p19-debug-events.log` | — |
| 13 | P2-controls-and-resizing.csv | P2 | — | — | P2 writes no debug-events log; and its most recent run log is 0 bytes |
| 14 | P20-disabled-item.csv | P20 | `clicked: level 1` | `testapp/output/p20-debug-events.log` | — |
| 15 | P20-open-level-1.csv | P20 | — | — | its run (2026-09-06 14:11:01–14:11:21 UTC) produced no event line at all; nothing on disk shows its clicks landing |
| 16 | P21-buttons-and-disabled.csv | P21 | — | — | `p21-debug-events.log` holds `backend` + `RENDER COMPLETE` only |
| 17 | P22-weights.csv | P22 | — | — | 91 lines, all text-metric measurements written at render time |
| 18 | P23-more-rows.csv | P23 | — | — | `p23-debug-events.log` holds `backend` + `RENDER COMPLETE` only |
| 19 | P24-push-one-level-winui.csv | P24 | — | — | its one row is marked `STALE 125% coordinate`; every P24 push line on disk comes from a GtkBackend run, and the 2026-08-29 WinUI launch wrote startup lines only |
| 20 | P24-push-one-level.csv | P24 | `push recorded at level 3` | `testapp/output/p24-debug-events.log` | — |
| 21 | P26-tab-switching.csv | P26 | — | — | `p26-debug-events.log` holds cache-dir, index-row and render lines, all written at startup |
| 22 | P28-click-through-overlay.csv | P28 | `underlying button clicked count=1` | `p28-debug-events.log`, `testapp/p28-debug-events.log` | — |
| 23 | P29-texteditor-disabled.csv | P29 | — | — | `p29-debug-events.log` is 0 bytes; no debug-events writer in P29.swift |
| 24 | P3-sidebar-and-image.csv | P3 | — | — | P3 writes no debug-events log anywhere on disk |
| 25 | P30-toggle-frame-width.csv | P30 | `size toggled wide=true` | `p30-debug-events.log`, `testapp/p30-debug-events.log` | — |
| 26 | P31-tab-and-escape.csv | P31 | `alert opened` | `testapp/output/p31-debug-events.log` | — (`alert OK` deliberately not used; see below) |
| 27 | P32-empty-label-button.csv | P32 | `empty-label button clicked` | `p32-debug-events.log`, `testapp/p32-debug-events.log` | — |
| 28 | P33-hide-details.csv | P33 | `details expanded=false` | `p33-debug-events.log`, `testapp/p33-debug-events.log` | — |
| 29 | P34-show-more-rows.csv | P34 | `show plus 100 -> visibleRows=` | `p34-debug-events.log`, `testapp/p34-debug-events.log` | — |
| 30 | P35-increment-count.csv | P35 | `count=1` | `p35-debug-events.log`, `testapp/p35-debug-events.log` | — |
| 31 | P36-string-label-button.csv | P36 | `button clicked` | `p36-debug-events.log`, `testapp/p36-debug-events.log` | — |
| 32 | P4-row-callback.csv | P4 | — | — | P4 writes no debug-events log; its own header opens "READ THIS FIRST -- P4 HAS NO DEBUG LOG" |
| 33 | P41-wheel-scroll.csv | P41 | — | — | `p41-debug-events.log` is 0 bytes; no debug-events writer in P41.swift |
| 34 | P44-clip-third-cell.csv | P44 | *(pre-existing)* `third cell clipped: true` | `testapp/output/p44-debug-events.log` | already done; not touched |
| 35 | P46-increment-model-winui.csv | P46 | `model.count=1 constructions=1` | `testapp/output/p46-debug-events.log` | — |
| 36 | P46-increment-model.csv | P46 | `model.count=1 constructions=1` | `testapp/output/p46-debug-events.log` (WinUI run — the weakest marker here; see below) | — |
| 37 | P46-scroll-to-lazy.csv | P46 | — | — | its own header: "this is a case where the log CANNOT help. Nothing in P46 writes on scroll" |
| 38 | P5-stacked-alerts.csv | P5 | `requesting A, B and C together` | `testapp/output/p5-debug-events.log` | — |
| 39 | P7-list-selection.csv | P7 | — | — | 910 lines, five shapes, all pane measurements emitted on every render; selection writes nothing |
| 40 | P8-scroll-outer.csv | P8 | — | — | `p8-debug-events.log` holds four probe sizes and `RENDER COMPLETE`, all at startup; the wheel writes nothing |
| 41 | P9-force-update-and-width.csv | P9 | — | — | `p9-debug-events.log` holds one line, `RENDER COMPLETE`, per launch |

**Totals: 17 of the 39 got a marker; 22 did not.** With the two that already had
one, 19 of the 41 files now declare an outcome.

**A 42nd file appeared while this was being written.** `P11-clamped-sliders.csv`
was created at 2026-09-07 21:59 by another session and is untracked; it is
outside this pass and was not touched. For the record it would not have been
marked either: `p11-debug-events.log` holds one line, `RENDER COMPLETE`, in each
of its eight runs.

**合計：39 個之中有 17 個加上了標記，22 個沒有。** 連同原本就有的兩個，41 個檔案中現有 19 個
會宣告結果。本文撰寫期間另有第 42 個檔案 `P11-clamped-sliders.csv` 於 2026-09-07 21:59 由另一個
工作階段建立且尚未納入版控；它不在本輪範圍內，也未被更動。附帶一提，它同樣不會被標記：
`p11-debug-events.log` 在八次執行中每次都只有一行 `RENDER COMPLETE`。

---

## Three markers that needed a judgement, recorded here rather than buried

### P18 — the marker is expected to report UNMET, and that is not P18's fault

`open: cancelled` is proven: the repo-root `p18-debug-events.log` holds
`open:` / `folder:` / `save: cancelled` at 22:33:10, :15 and :19 on 2026-09-03,
three seconds apart, matching this file's three 3.0 s sleeps. P18's startup
lines are `backend GtkBackend.Type` and `RENDER COMPLETE`, so a `cancelled` line
cannot come from launching.

But `testapp/output/p18-debug-events.log` holds **nine** driven runs and not one
`cancelled` line, and the matching run log contains **zero**
`target window changed` lines — so no picker ever opened in the sweep and the
three Escapes had nothing to cancel. In the same sweep session, P31's click
inside its own alert landed on a `Windows.UI.Core.CoreWindow`. Both are the
foreground problem `sweep_drive.zsh` documents at `clear_desktop`.

The marker was applied anyway, because `UNMET` is the truthful answer for those
runs and silence is not. The action file's header now carries the diagnosis, so
the first thing an `UNMET` here points at is the `target window changed` count,
not `P18.swift`.

### P31 — `alert opened`, not the `alert OK` its own last row calls the verdict

Both lines are on disk. `alert OK` was last written on 2026-09-05 17:05:53;
none of the three most recent runs produced it, and the run log says why rather
than leaving it to inference — the move to frame (53,44) reports
`hitClass=Windows.UI.Core.CoreWindow`. Asserting it today would report "the
click missed its control, or the control does nothing" for a desktop problem.
`alert opened` was written by all three recent runs and is absent from the
2026-09-03 launch that had no action file. Promote the marker once a run
produces `alert OK`.

### P46-increment-model.csv — the weakest marker in the directory, and labelled as such

`model.count=1 constructions=1` is on disk in `testapp/output/p46-debug-events.log`,
written by the Button's action and by nothing else — but that run reads
`backend WinUIBackend`, so the only surviving instance comes from the *winui*
twin of this file. The write call is one line of backend-independent Swift, the
row note in the GTK file records the same text as VERIFIED on GTK the same day,
and the winui file calls its own output "byte-identical to the GTK run" — but no
GTK run survives on disk to prove it. The file's header says all of this, and
says what to check first if it reports UNMET (the coordinate: the button sits at
y 586 and GTK gives that window 661 points of content).

### 三個需要判斷的標記，記在此處而不埋起來

- **P18**：`open: cancelled` 已被證明存在，但目前的 sweep 預期會回報 UNMET，而那是**桌面**的問題
  ——該次執行的 run log 中 `target window changed` 的行數為零，代表沒有任何 picker 被開啟。標記仍然
  加上，因為對那些執行而言 `UNMET` 才是誠實的答案，沉默不是；動作檔的標頭已寫明該先查什麼。
- **P31**：採 `alert opened` 而非其最後一列自稱為判準的 `alert OK`。後者最近三次執行都沒有產生，
  而 run log 指出原因：移動到 frame (53,44) 時 `hitClass=Windows.UI.Core.CoreWindow`。待有任何一次
  執行產生 `alert OK`，再將標記升級。
- **P46-increment-model.csv**：磁碟上唯一的實例來自 WinUI 那次執行，因此這是本目錄中最弱的標記，
  且已在檔案標頭中如此標明，並寫出「若回報 UNMET 該先查座標」。

---

## Two collision checks, because a false PASS is silent

The driver's haystack is the run log **plus** the app's new bytes, so a short
marker could in principle be satisfied by driver noise. Two of the markers are
short enough to matter and both were measured on 2026-09-07 rather than assumed:

```
grep -l 'count=1'        /tmp/sweep_drive-gtk4/*.log   # matches none of the 35
grep -l 'button clicked' /tmp/sweep_drive-gtk4/*.log   # matches none of the 35
```

P31 writes `button clicked count=1`, which would satisfy P36's marker — but it
is a different app writing to its own log, and the driver only ever reads the
log of the app it launched.

驅動器的搜尋範圍是 run log **加上** app 新寫入的位元組，因此過短的標記在原理上可能被驅動器本身的
輸出滿足。其中兩個標記短到需要在意，兩者都在 2026-09-07 實測而非想當然耳：對
`/tmp/sweep_drive-gtk4` 中全部 35 份 log 執行上列兩個 `grep -l`，都沒有任何一份命中。

---

## What was NOT changed

No coordinate, no `Measured on a WxH` header, and no `action,x,y,...` row was
touched in any file. Every edit is comment lines inserted into an existing
header block. All 41 files were LF-only before and after (`tr -dc '\r' | wc -c`
returns 0 for each), and nothing under `matrix_coverage/` was modified.

未更動任何座標、任何 `Measured on a WxH` 標頭、任何 `action,x,y,...` 資料列。所有編輯都是插入既有
標頭區塊中的註解行。41 個檔案在編輯前後都只有 LF（每一個的 `tr -dc '\r' | wc -c` 皆為 0），
`matrix_coverage/` 底下也沒有任何改動。
