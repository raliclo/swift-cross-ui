# macOS harness: screenshots and window-title resolution

Written 2026-10-24 from testapp/screenshot.zsh (the self-contained macOS
section), testapp/test_support/test_common.zsh (`capture`, `final_window`) and
testapp/test_support/measure/README.md. The macOS path was added by c6df07ce.

## What

`screenshot.zsh [-d s] [-w title] label` writes
`testapp/output/screenshots/<label>-<timestamp>.png`:

- **Priority 1** (with `-w`): resolve the window, then
  `screencapture -x -o -l <CGWindowID>`. `-l` reads the window itself, covered or
  not, with no raise; `-o` drops the shadow so two captures align. Accepted when
  the file exists and is over 5000 bytes.
- **Priority 2**: the whole screen (`screencapture -x`). As a fallback it first
  raises the window's process through System Events
  (`set frontmost ... whose unix id is <pid>`) and prints
  `captured from priority 2: screen (window capture failed)`. Without `-w` the
  screen is the requested subject and prints `captured from screen`.
- No file at all: a hint about permissions, display sleep and locked screen,
  then exit 1. No path is printed for a file that does not exist.

**Resolution.** The window list comes from `CGWindowListCopyWindowInfo` through
`osascript -l JavaScript` (nothing to compile, no Accessibility needed):

- `ObjC.castRefToObject` is required; without it `deepUnwrap` gives undefined,
  and the output is empty with exit 0, the same as "no windows".
- Rows: id, owner, title, x, y, w, h, pid, joined by US (`\037`, written as
  `fromCharCode(31)`); a title may hold tabs, commas or quotes.
- Windows under 100 px either side and layers below 0 are skipped. The filter is
  on owner, not layer: `layer !== 0` used to drop P37's `.topmost()` window at
  layer 3, so the one app about window levels fell back to the screen silently.
- A title match anywhere in the list beats an owner-name match; which one
  matched is printed (`resolved window title to ...` or
  `matched the owning program ...`).

The harness takes the 1 s and timeout captures of the window titled
`TEST_TITLE` (default: the app name), and the final one too unless
`TEST_FINAL_CAPTURE=desktop`.

## Why

- gdigrab, the Windows path, printed `Unknown input format` on macOS and exited
  0, so `test.zsh P28 --macos` once left no screenshots while reporting them.
- `kCGWindowName` is readable only with Screen Recording permission (macOS
  10.15+): measured on one machine, 0 of 28 titles without it, 22 of 26 with it.
  `kCGWindowOwnerName` is present either way, but for a bundled run the owner is
  `debugTarget`, which identifies the app, not which of its windows.
- While the display sleeps, `-l` fails for every window, frontmost included,
  and a whole-screen capture still exits 0 with a black frame. A fallback to the
  screen is a signal, not a lesser success.

## How to apply

- Give each app a `TEST_TITLE` substring that matches every state of its title:
  P50's title changes at runtime, so its tests use `P50 TITLE`; a description
  that matched no window sent every P50 capture to the desktop (results.csv2:
  2026-09-10, mac, appkit, P50). P26 uses `P26: networking`; a wrong P26 title
  was fixed before the 2026-09-27 sweep, whose captures were all windows.
- A result in another window (a sheet, a second window) is not reached by the
  title: AppKit sheets are untitled windows. Use `TEST_FINAL_CAPTURE=desktop`
  (P81, 2026-10-22) or `measure/window_shots.swift` during the showtime (P103's
  long-press sheet, 2026-10-17).
- Read the `captured from` line before reading the image.

## Contradiction, settled

`testapp/sweep-test/measure_macos.zsh` (2026-09-01) says
`osascript -l JavaScript <<'JXA'` reads no script from stdin and prints nothing.
Re-tested 2026-10-24 on this Mac: a heredoc script prints its result value with
exit 0, and screenshot.zsh depends on that. The silent failure there was
`console.log`, which writes to stderr; with `2>/dev/null` the result is lost.
Return the value from the script, or keep `2>&1`.

---

# macOS harness:擷圖與視窗標題解析

2026-10-24 依 testapp/screenshot.zsh(自成一段的 macOS 區塊)、testapp/test_support/test_common.zsh(`capture`、
`final_window`)與 testapp/test_support/measure/README.md 寫成。macOS 路徑由 c6df07ce 加入。

## 是什麼

`screenshot.zsh [-d 秒] [-w 標題] 標籤` 寫出 `testapp/output/screenshots/<標籤>-<時間戳>.png`:

- **優先序 1**(有 `-w`):解析出視窗後執行 `screencapture -x -o -l <CGWindowID>`。`-l` 直接讀視窗本身，被蓋住也行，
  不必帶到前景;`-o` 去掉陰影，兩張擷圖才對得齊。檔案存在且大於 5000 位元組才算成功。
- **優先序 2**:整個螢幕(`screencapture -x`)。作為退路時先經 System Events 把該視窗的行程帶到前景，並印出
  `captured from priority 2: screen (window capture failed)`。沒給 `-w` 時，螢幕就是要拍的對象，印 `captured from screen`。
- 完全沒有檔案：印出權限、顯示器休眠與螢幕鎖定的提示，以 1 結束。不會印出不存在的檔案路徑。

**解析方式。** 視窗清單取自 `CGWindowListCopyWindowInfo`,經 `osascript -l JavaScript` 呼叫(不必編譯，不需輔助使用權限):

- 必須用 `ObjC.castRefToObject`;少了它 `deepUnwrap` 得到 undefined,輸出為空且結束碼 0,與「沒有視窗」一樣。
- 每列：id、擁有者、標題、x、y、w、h、pid,以 US(`\037`,寫成 `fromCharCode(31)`)分隔；標題可能含 tab、逗號或引號。
- 略過任一邊小於 100 px 的視窗與 layer 小於 0 的視窗。以擁有者而非 layer 過濾:原本的 `layer !== 0` 會濾掉 P37 因
  `.topmost()` 而位於 layer 3 的視窗，讓唯一以視窗層級為主題的 app 靜默退回整螢幕擷取。
- 清單中任何一列的標題比中，都優先於程式名稱比中；比中的是哪一種會印出來。

harness 的 1 秒與逾時擷圖拍標題為 `TEST_TITLE`(預設為 app 名稱)的視窗；最終擷圖也是，除非 `TEST_FINAL_CAPTURE=desktop`。

## 為什麼

- Windows 路徑的 gdigrab 在 macOS 上印出 `Unknown input format` 卻以 0 結束,`test.zsh P28 --macos` 曾因此一張擷圖都沒有、
  卻回報有。
- `kCGWindowName` 只在有「螢幕錄製」權限時讀得到(macOS 10.15 起):同一台機器上實測，沒有權限時 28 個標題全空，有權限時
  26 個中 22 個讀得到。`kCGWindowOwnerName` 兩種情況都有，但經 bundle 的執行擁有者是 `debugTarget`,只能分辨是哪支 app,
  分不出是它的哪個視窗。
- 顯示器休眠時,`-l` 對每個視窗都失敗(最前面的也一樣),整螢幕擷取卻仍以 0 結束並回傳全黑畫面。退回整螢幕是一個訊號，
  不是較差的成功。

## 怎麼用

- 每支 app 的 `TEST_TITLE` 要取能比中所有標題狀態的子字串:P50 的標題在執行時會變，因此用 `P50 TITLE`;原本設成說明文字、
  比不中任何視窗，使 P50 的每張擷圖都退回桌面(results.csv2:2026-09-10、mac、appkit、P50)。P26 用 `P26: networking`;
  P26 錯誤的標題在 2026-09-27 sweep 之前修好，該次擷圖全部都是視窗。
- 結果在另一個視窗(sheet、第二個視窗)時，依標題拍不到:AppKit 的 sheet 是沒有標題的視窗。用 `TEST_FINAL_CAPTURE=desktop`
  (P81,2026-10-22),或在 showtime 期間用 `measure/window_shots.swift`(P103 的長按 sheet,2026-10-17)。
- 看圖之前先讀 `captured from` 那一行。

## 矛盾與結論

`testapp/sweep-test/measure_macos.zsh`(2026-09-01)寫著 `osascript -l JavaScript <<'JXA'` 不從 stdin 讀腳本、什麼都不印。
2026-10-24 在這台 Mac 上重測:heredoc 腳本會印出它的結果值、結束碼 0,而 screenshot.zsh 正依賴這一點。當時真正無聲失敗的是
`console.log`——它寫到 stderr,加了 `2>/dev/null` 結果就沒了。要嘛讓腳本回傳值，要嘛保留 `2>&1`。
