# mac

Action files for the macOS AppKit runner. The `platform` column is `macos`;
none of these may be replayed against GTK or WinUI.

```zsh
zsh testapp/test.zsh P28 --macos --actionfile
```

## Verified

AppKit hit testing was fixed on 2026-09-01 (`226a4af7`), together with the
bundle-identity fault that had the same symptom (`test_common.zsh`). Files
run here since:

- `P28-hit-testing.csv` — `underlying button clicked count=1` then `count=2`
  in `testapp/output/p28-debug-events.log`. Its coordinates were also stale
  and are corrected.
- `P21-enabled-and-disabled.csv` — `Button — clicks: 1`. One, not two: the
  enabled button counted and the disabled one did not. Toggle, toggle-button
  and checkbox all flipped; every disabled counterpart stayed put.
- `P0-appstorage.csv` — the Reset click lands and the status line says so.
- `P26-swiftcrossui-tab.csv` — the tab click reaches the tab strip and one
  artifact is fetched.

## Everything else here is written but not yet replayed

This file used to say: *a file appears here only after it has been run here
and seen to work; an empty folder is an honest gap, and a copy of another
platform's file is a claim nobody checked.* That rule was right and the
reasoning still holds. It is suspended for one specific reason, written down
here rather than quietly ignored.

These were written while AppKit hit testing was broken, when no file *could*
be verified and waiting for the fix would have meant measuring every window
twice. That is fixed now, so the rule can go back to what it was — but only
after each file has actually been run, which four have been and the rest have
not. Until then they are measured, not confirmed.

One thing to know before replaying them: they were measured against the bare
executable, whose window and the bundle's now agree only because each app
finally has its own UserDefaults domain and so no inherited frame. An app
that gets resized will save its own frame and keep it, and its file's
coordinates will be stale from then on. `measure_macos.zsh` reports the size
it measured; compare it against the size in the file's header before
believing a miss.

What is written down is therefore what was measured, not what was observed to
work. Every coordinate here was read off a window capture taken by
`testapp/sweep-test/measure_macos.zsh` while that app was running, and every
file records the window size and capture scale it was measured at, so a
coordinate can be rechecked without re-running the app. What no file claims is
that the click had an effect.

Each file also says what each row *should* change. That is the part that makes
verification a replay rather than a re-measurement: run the file, read the line
the note names, and the file has either passed or found something.

## Apps with no file here, and why

These are gaps with reasons, not oversights.

| App | Why |
| --- | --- |
| `P25` | Needs a drag from the Finder. A cross-application drag comes from the window server's drag session; `NSApp.postEvent` cannot start one. |
| `P30`, `P39`, `P40` | They open now -- the abort was fixed on 2026-09-01. ~~AppKitBackend still implements neither effect family, so every view in them renders unmodified.~~ **Superseded 2026-09-02: AppKitBackend implements both `VisualEffects` and `GeometricEffects`, verified against P39 (all nine cells distinct from the control) and P40 (offset, rotation and the two anchors all correct).** These three still have no action file, but the reason is now the one that always applied to them and not the missing conformances: they take no input, so what they demonstrate is read from a capture rather than driven by a click. |
| `P37` | Asks for another application's window to be given focus, which the synthesiser cannot do — it posts into this app's own event queue. |
| `P17-DOE` | Three drawn rectangles and no controls. A capture answers it. |
| `P6-v2` | Imports `Gtk` and `GtkBackend` directly. It does not build for AppKit and is not meant to. |
| `wincap` | A Windows command-line tool. No window. |

## Second windows are out of reach until the fix lands

Menus, alerts, file dialogs and popovers are separate windows, so their
contents cannot be measured until a click can open one. Where a file stops for
this reason it says so on the row: `P19` and `P20` open their menus and stop,
`P6` leaves its Resolution popup alone, `P2`, `P17` and `P36` open their pickers
and close them with Escape.

Escape is used wherever a modal has to be dismissed without knowing its
geometry — `P1`, `P18`, `P5`, `P31`. It reaches a key window without a
coordinate, which is exactly what a measured-by-capture file cannot supply for
a window that did not exist when the capture was taken.

**That technique is macOS-only, and the sentence above is the reason someone
will try it elsewhere.** Measured 2026-09-03 on Windows/GtkBackend with
`testapp/actions/win/P31-tab-and-escape.csv`: Escape does **not** reach a
modal there. `Win32Synthesiser` does not have AppKit's notion of a key window —
`ownWindow()` picks the process's **largest-area** visible top-level window, and
a dialog is a smaller separate top-level window, so it can never be chosen; the
synthesiser then calls `SetForegroundWindow` on the main window, which takes
focus off the modal before the key is even sent. Full write-up in
`bugs/Gtk4-bugs.md` §6. Keys themselves work on Windows — the same run moved
focus with Tab and activated a button with Space — so a replay of a ported
Escape row reports no error and proves nothing. **Do not copy an Escape row from
here into `win/` and read the absence of a failure as a pass.**

---

# mac（繁體中文）

供 macOS AppKit runner 使用的動作檔。`platform` 欄位為 `macos`，這些檔案皆不可拿到 GTK 或
WinUI 上重放。

## 已驗證

兩份檔案曾在此實際執行並確認可運作：

- `P28-hit-testing.csv` — `testapp/output/p28-debug-events.log` 中的
  `underlying button clicked count=1`。
- `P26-swiftcrossui-tab.csv` — 分頁點擊抵達分頁列，並取得一項 artifact。

## 此處其餘一切皆未驗證，而這是規則的變更

本檔原本寫著：*檔案唯有在此平台實際執行過並確認可運作之後才會出現於此；空資料夾是誠實的缺口，
而從其他平台複製過來的檔案，是一項無人查證過的主張。* 那條規則是對的，其理由至今仍然成立。它因
一個特定的理由被暫停，而該理由寫在此處，而非被默默忽略。

AppKit 的 hit testing 在這台機器上是壞的（見 `todo.md`）。重放能抵達 P26 的分頁列，其餘一律不能
——P21 對「按鈕正中央」的點擊回報 `Button — clicks: 0`，P28 的計數器在修正後的 overlay 中心點
仍停留在零。因此今天所寫的任何檔案都**不可能**被驗證；而等待修復則意味著每個視窗都要量兩次：
現在量一次以得知控制項的位置，日後再量一次。

所以此處寫下的是「量到的東西」，而非「觀察到能運作的東西」。這裡的每一個座標，都是在該 app 執行
期間，自 `testapp/sweep-test/measure_macos.zsh` 所拍攝的視窗擷取影像上讀出的；每一份檔案都記錄了
它所依據的視窗尺寸與擷取縮放比例，因此座標可以在不重新執行 app 的情況下被重新核對。所有檔案都
不曾主張「該次點擊產生了效果」。

每一份檔案也都寫明各列**應該**改變什麼。正是這一部分，使日後的驗證成為一次重放，而非一次重新量測：
執行該檔、讀取註解所指名的那一行，該檔便已經通過，或是發現了什麼。

## 此處沒有檔案的 app，以及原因

這些是有理由的缺口，不是疏漏。

| App | 原因 |
| --- | --- |
| `P25` | 需要從 Finder 拖曳。跨應用程式的拖曳來自 window server 的 drag session；`NSApp.postEvent` 無法發起。 |
| `P30`、`P39`、`P40` | 現在開得起來了——那個中止已於 2026-09-01 修復。~~但 AppKitBackend 兩個效果系列仍都未實作，因此其中每一個 view 都以未經修飾的樣貌算繪。~~ **2026-09-02 起已被取代：AppKitBackend 已實作 `VisualEffects` 與 `GeometricEffects`，並以 P39（九格全部與對照格不同）與 P40（offset、rotation 與兩個 anchor 皆正確）驗證。** 這三支仍然沒有 action file，但理由已換成那個一直都成立的理由，而不是缺少 conformance：它們不接受任何輸入，要看的東西是從擷取影像讀出來的，不是點出來的。 |
| `P37` | 要求把焦點交給另一個應用程式的視窗，而 synthesiser 做不到——它只把事件送入本 app 自己的事件佇列。 |
| `P17-DOE` | 三個繪製出來的矩形，沒有任何控制項。擷取影像即可回答。 |
| `P6-v2` | 直接 `import Gtk` 與 `GtkBackend`。它不會為 AppKit 建置，也不打算如此。 |
| `wincap` | 一支 Windows 命令列工具。沒有視窗。 |

## 在修復落地之前，第二個視窗不可及

選單、警示、檔案對話框與 popover 都是獨立的視窗，因此在點擊能夠開啟其中之一之前，其內容無從量測。
凡是因此而停下的檔案，都會在該列上說明：`P19` 與 `P20` 開啟選單後即停止，`P6` 不碰它的 Resolution
下拉選單，`P2`、`P17` 與 `P36` 開啟各自的 picker 後以 Escape 關閉。

凡是必須在不知道其幾何資訊的情況下關閉 modal 之處，一律使用 Escape——`P1`、`P18`、`P5`、`P31`。
它無需座標即可抵達 key window，而這正是「以擷取影像量測而成的檔案」對一個「拍攝當下尚不存在的
視窗」所無法提供的東西。

**這個手法僅限 macOS，而上面那句話正是有人會把它搬到別處的原因。** 2026-09-03 於
Windows/GtkBackend 以 `testapp/actions/win/P31-tab-and-escape.csv` 實測：Escape 在那裡**到不了**
modal。`Win32Synthesiser` 沒有 AppKit 的 key window 概念——`ownWindow()` 挑的是本行程中**面積最大**
的可見 top-level 視窗，而對話框是較小的獨立 top-level 視窗，因此永遠選不到；合成器接著又對主視窗
呼叫 `SetForegroundWindow`，在按鍵送出之前就把焦點從 modal 手上拿走。完整記述見
`bugs/Gtk4-bugs.md` 第 6 節。按鍵本身在 Windows 上是能用的——同一次執行以 Tab 移動了焦點、以
Space 觸發了按鈕——所以把 Escape 那一列搬過去重放，會不回報任何錯誤，卻什麼也沒證明。**請勿把
此處的 Escape 列複製到 `win/`，並把「沒有失敗」讀成通過。**
