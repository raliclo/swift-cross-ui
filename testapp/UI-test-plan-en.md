# UI test plan (English)

**One file per language, and this is the English one.** It used to be five --
an overall plan, a bug plan, a Linux plan, a platform matrix and a results log --
with the Traditional Chinese half in six more. Eleven files for two documents
meant a reader had to know which one held the answer before looking it up, and an
edit to a step had five places it might belong.

**Nothing was rewritten in the merge.** Each part below is one of those files,
with its headings pushed down a level so they nest under the part, its own title
line dropped because the part heading replaces it, and references between the
former files turned into links within this one. Every other line is unchanged.

The Traditional Chinese half is `UI-test-plan-zhTW.md`. The two are not
line-for-line translations and never were.

## Parts

- [Overall plan: P0-P41](#overall-plan-p0-p41) — Every app's steps, in order. The largest part and the one to read first.
- [Bug plan: AppKit, UIKit and AndroidBackend](#bug-plan-appkit-uikit-and-androidbackend) — The apps written against specific defects on the Apple and Android backends.
- [Linux plan: GtkBackend through WSL](#linux-plan-gtkbackend-through-wsl) — Toolchain, phases, and what a WSLg result is and is not evidence for.
- [Platform matrix](#platform-matrix) — Which issue runs where, and whether the answer counts.
- [Results log](#results-log) — Dated manual results. A record of runs, not a plan.

---

## Overall plan: P0-P41

This document describes the manual and assisted UI test steps for the apps in `testapp`. The goal is to quickly reproduce and verify backend-specific issues across WinUIBackend, GtkBackend, AppKitBackend, UIKitBackend, and AndroidBackend.

### Preparation

1. Go to the project root:

   ```zsh
   cd /c/Users/lowei/proj/swift-cross-ui
   ```

2. Compile the test apps:

   ```zsh
   zsh testapp/compile.zsh
   ```

3. Go to the output directory:

   ```zsh
   cd testapp/output
   ```

4. Confirm that the runtime resource exists:

   ```zsh
   test -f swift-winui_CWinAppSDK.resources/Microsoft.WindowsAppRuntime.Bootstrap.dll && echo ok
   ```

   Expected result: `ok`.

### Executable Names on Windows

Every Windows test binary carries its backend as a filename suffix:
`Pn-WinUI.exe` is the WinUIBackend build, `Pn-gtk4.exe` is the GtkBackend build.
The unsuffixed `Pn.exe` no longer exists, so every run command below names one.

The suffix is not cosmetic. On 2026-09-02 a screenshot matched by window title
photographed the wrong backend's window: both builds register the same title, and
once the two `Pn.exe` files had been copied side by side nothing in the filename
told them apart. The suffix puts the backend in the run command, the process list
and the file name itself, where a mismatch is visible instead of silent.

Regenerate them with:

```zsh
cd testapp && zsh compile.zsh          # -> testapp/output/Pn-WinUI.exe
cd testapp && zsh compile.zsh -gtk4    # -> testapp/output/Pn-gtk4.exe
```

Two apps have only one build, by design: `P6` is the D3D11 video test and links
the WinUI products, so there is no `P6-gtk4.exe`; `P6-v2` is a pure GTK app, so
there is no `P6-v2-WinUI.exe`.

### Cross-Platform Flow

- For Linux / GtkBackend issues, test WSLg first, then Windows only as a comparison if the app supports it.
- Do not compile from `/mnt/c` inside WSL. Sync the `testapp` Swift/zsh files first, then build under `~/proj/swift-cross-ui`.
- Use zsh scripts only. The current helper scripts are `compile.zsh`, `rsync_WSL.zsh`, `screenshot.zsh`, `videoshot.zsh`, and `test.zsh`.
- Automated dry-runs through `zsh testapp/test.zsh Pn --both` run WSLg first, then Windows. They keep each platform window open for 30 seconds after render by default, then take a final screenshot so the tester can inspect the app and report what changed.
- Screenshots are written to `testapp/output/screenshots` with platform and phase in the filename, such as `p8-wslg-1s-...png`, `p8-wslg-final-...png`, `p8-windows-1s-...png`, and `p8-windows-final-...png`.

### Android: Four Things To Check, And What Each One Proves

Android is driven by `test_android.zsh` for a single app and `sweep_android.zsh`
for the whole set. Neither of those, on its own, answers "did the test run".
They stack, and the reason this section exists is that on 2026-09-05 a sweep
reported 46 of 46 apps passing while the strongest claim the evidence supported
was that 46 processes had started.

| Stage | Script | What it proves | What it does **not** prove |
| --- | --- | --- | --- |
| Build and launch | `sweep_android.zsh` | The APK built, installed, and the activity started | Nothing about the action file |
| The file arrived | the same run's log | `==> Pushing …csv -> /data/local/tmp/…` and the intent extra was sent | That a single event was replayed |
| The replay ran | `verify_replay_android.zsh` | `-actionfile: replayed <name>` reached logcat, naming this app's file | That the events landed on anything |
| Something changed | `verify_effect_android.zsh` | The app looks different from the same app launched with no action file | Which widget changed, unless you read the diff |

**The third does not imply the fourth.** `FAQ.md` records a run that logged
`action file replayed` while the screen still read `last action -> nothing yet`.
Two attempts to check the fourth stage were written before one worked:

- grepping logcat for `last action ->` matched zero apps, because that text is
  drawn on screen and never logged;
- comparing each app's `-1s-` and `-final-` captures gave exactly zero differing
  pixels for 40 of 45, because under `--no-showtime` those two captures are
  taken back to back and carry the same timestamp and the same md5.

Both are the same failure: **a check that cannot produce a positive is not a
check.** Before trusting one, make it fail on purpose.

#### Reading a "no effect" result

Twelve of the 46 action files are not supposed to change anything -- they press
an inert label or a disabled control and require the process to survive. For
those, zero changed pixels is the pass. The verdict has to come from the action
file's own `note`, and even that has to be read rather than pattern-matched: a
note can say "the process must survive" in one clause and require a counter to
increment in the next, which is why six apps were misfiled the first time a
regular expression was pointed at those notes.

#### Thresholds

The effect check counts changed pixels, and its threshold has to sit in a gap in
the measured distribution rather than on a round number. The scenarios that
change nothing report exactly 0 with no bounding box; the smallest real change
is 517 pixels, because P28 turns `received: 0` into `received: 1` and a digit is
small. A threshold of 2000 called two passes failures. It is 100.

#### The screenshots

The first capture is taken **five seconds** after launch, not one. A cold
Android start loads the JVM, libswiftCore, Foundation and ICU before
`AndroidBackend_entrypoint` runs, and these apps log RENDER COMPLETE at about
six seconds; one capture in 174 on 2026-09-05 photographed the launch splash
instead of the app. Override with `ANDROID_FIRST_CAPTURE_SECONDS`.

#### The frame is not the app

Twenty-seven of the 46 scenarios lay out content wider or taller than the phone
-- P6 reaches 2.65 times the viewport width. A screenshot at the default scroll
position is a photograph of part of the page, and reading absence from it is
wrong: P3's test image measured **zero** coloured pixels in the visible frame and
**4,735** with the page scaled to fit. It had rendered all along. Use
`SCUI_RWD=1` on the effect check, or tap the `actualView` control, to photograph
the whole page.

### Android：要檢查的四件事，以及每一件各自證明了什麼

Android 的驅動,單一 app 用 `test_android.zsh`,整組用 `sweep_android.zsh`。這兩者單獨都回答不了
「這個測試到底有沒有跑」。它們是疊起來的;而本節之所以存在,是因為 2026-09-05 有一次 sweep 回報
46 支全數通過,而當時證據所能支持的最強主張,只是「有 46 個行程啟動過」。

| 階段 | 腳本 | 它證明了什麼 | 它**沒有**證明什麼 |
| --- | --- | --- | --- |
| 建置與啟動 | `sweep_android.zsh` | APK 建好、安裝、activity 啟動 | 關於動作檔的任何事 |
| 檔案送達 | 同一次執行的日誌 | `==> Pushing …csv -> /data/local/tmp/…`,且 intent extra 已送出 | 有任何一個事件被重放 |
| 重放執行了 | `verify_replay_android.zsh` | `-actionfile: replayed <名稱>` 抵達 logcat,且指名的是本 app 的檔案 | 那些事件落到了任何東西上 |
| 有東西改變了 | `verify_effect_android.zsh` | 該 app 與「不帶動作檔啟動的同一支 app」看起來不同 | 是哪個 widget 改變了——除非去讀那個差異 |

**第三件不蘊涵第四件。** `FAQ.md` 記錄過一次執行:它記錄了 `action file replayed`,而畫面仍寫著
`last action -> nothing yet`。在寫出一個可用的第四階段檢查之前,有兩次嘗試是失敗的:

- 在 logcat 中 grep `last action ->`,零支命中——因為那段文字是畫在畫面上的,從不記錄;
- 比對各 app 的 `-1s-` 與 `-final-` 兩張擷取,45 支中有 40 支的差異恰好是零像素——因為在
  `--no-showtime` 之下,那兩張是連續拍下的,帶有相同的時間戳與相同的 md5。

兩者是同一種失敗:**一個產生不出正面結果的檢查,不是檢查。** 在信任它之前,先讓它刻意失敗一次。

#### 如何解讀「無效果」

46 份動作檔中有 12 份本來就不該改變任何東西——它們按的是一個惰性標籤或一個已停用的控制項,要求的是
行程存活。對那些而言,零像素改變就是通過。判定必須來自動作檔自己的 `note`,而且那也必須用讀的、
不能用樣式比對:一則備註可以在前半句寫「the process must survive」、後半句要求某個計數器增加——
這正是第一次拿正規表示式去掃那些備註時,有六支被歸錯類的原因。

#### 門檻

效果檢查計算的是改變的像素數,而它的門檻必須落在實測分佈的空隙裡,而不是落在一個整數上。不改變任何
東西的情境回報的是恰好 0 且沒有 bounding box;而最小的真實改變是 517 像素,因為 P28 把
`received: 0` 變成 `received: 1`,而一個數字就是這麼小。2000 的門檻曾把兩次通過判成失敗。現在是 100。

#### 那些截圖

第一張擷取是在啟動後**五秒**,不是一秒。Android 的冷啟動會在 `AndroidBackend_entrypoint` 執行之前
先載入 JVM、libswiftCore、Foundation 與 ICU,而這些 app 大約在六秒記錄 RENDER COMPLETE;
2026-09-05 的 174 張擷取中有一張拍到的是啟動畫面而非 app。以 `ANDROID_FIRST_CAPTURE_SECONDS` 覆寫。

#### 畫面不等於 app

46 個情境中有 27 個的內容比手機更寬或更高——P6 達到視口寬度的 2.65 倍。在預設捲動位置拍的截圖,
是「整頁的一部分」的照片,而從中讀出「不存在」是錯的:P3 的測試圖在可見畫面中量到**零**個彩色像素,
把整頁縮放到塞得下之後則是 **4,735** 個。它自始至終都算繪出來了。請在效果檢查上使用 `SCUI_RWD=1`,
或點擊 `actualView` 控制項,以拍下整頁。

### Common Checks

- The app can open its main window.
- The console does not show a fatal error or stack trace.
- The window remains interactive; buttons, inputs, and menus respond.
- The process exits normally after closing the app.
- If a crash occurs, record:
  - Which exe was running
  - Which control was clicked
  - The last log line before the crash
  - Swift / WinUIBackend file names and line numbers from the stack trace

### P0: Critical Lifecycle

Run:

```zsh
./testapp/output/P0-WinUI.exe      # WinUIBackend, on Windows
```

Covered issues:

- #493 (Fixed): WinUIBackend may crash when an environment action is called too early
- #548 (Fixed): `@AppStorage` crashes on Windows
- No dedicated issue (Fixed): WinUIBackend `setSizeLimits` unimplemented log
- No dedicated issue (Fixed): WinUIBackend `setIncomingURLHandler` unimplemented log

Test steps:

1. Launch `P0-WinUI.exe`.
2. Confirm that the main window `P0 WinUI critical checks` appears.
3. Confirm that the console does not show these unimplemented logs:
   - `setSizeLimits(ofWindow:minimum:maximum:) unimplemented`
   - `setIncomingURLHandler(to:) not implemented`
4. Click `Increment @AppStorage` several times to verify #548 (Fixed).
5. Click `Reset` to verify #548 (Fixed).
6. Close the app, launch it again, and confirm that the launch count still updates normally to verify #548 (Fixed).
7. Click `Show AlertScene`; confirm that the alert appears and can be closed with OK to verify #493 (Fixed).
8. Click `Present environment alert after 1 second`; confirm that the alert appears after 1 second to verify #493 (Fixed).
9. Click `Present environment alert now`; confirm that the alert appears to verify #493 (Fixed).

Expected results:

- The app should not crash at launch.
- The `@AppStorage` buttons should not crash; if they do, #548 (Fixed) regressed.
- AlertScene and environment alerts should display normally.
- If an alert crashes and the error contains `XamlRoot`, #493 (Fixed) regressed.

### P1: Dialogs And Sheets

Run:

```zsh
./testapp/output/P1-WinUI.exe      # WinUIBackend, on Windows
```

Covered issues:

- #523 (Fixed): Windows file open/save dialogs are slow to appear
- #659 (Fixed): Nested sheets are not supported
- #660 (Fixed): Sheets have default padding

Test steps:

1. Launch `P1-WinUI.exe`.
2. Click `Open file dialog`.
3. Select any file or cancel; record how long the dialog takes to appear and return to verify #523 (Fixed).
4. Click `Open folder dialog`.
5. Select any folder or cancel; record how long the dialog takes to appear and return to verify #523 (Fixed).
6. Click `Save file dialog`.
7. Select a save destination or cancel; record how long the dialog takes to appear and return to verify #523 (Fixed).
8. Click `Open root sheet`.
9. Observe the padding around the root sheet content to verify #660 (Fixed).
10. Click `Open nested sheet`.
11. Confirm whether the nested sheet appears and closes correctly to verify #659 (Fixed).

Expected results:

- File, folder, and save dialogs should open without crashing.
- Dialogs should not visibly take more than 2 seconds to appear; if one does, record it as a #523 (Fixed) regression.
- If the nested sheet cannot appear or crashes, record it as a #659 (Fixed) regression.
- If the red bar in the root sheet is still clearly surrounded by padding, record it as a #660 (Fixed) regression.

### P2: Controls And Styling

Run:

```zsh
./testapp/output/P2-WinUI.exe      # WinUIBackend, on Windows
```

Covered issues:

- #449 (Fixed): Picker options do not update correctly
- #471 (Fixed): TextEditor has a thin border when unfocused
- #401 (Fixed): Full screen button is not disabled when window resizing is disabled
- #390 (Fixed): Disabled buttons do not look visibly disabled

Test steps:

1. Launch `P2-WinUI.exe`.
2. Open the Picker and confirm that the initial options are only `Vanilla` and `Chocolate` to verify #449 (Fixed).
3. Check `Use expanded Picker options` to verify #449 (Fixed).
4. Open the Picker again and confirm that `Strawberry`, `Mint`, and `Coffee` were added and selectable to verify #449 (Fixed).
5. Click the TextEditor and type `12345`; confirm that no keystrokes are dropped to verify #471 (Fixed).
6. Click another control so the TextEditor loses focus; confirm that there is no unfocused thin border to verify #471 (Fixed).
7. Compare the disabled button and enabled button; confirm whether the visual difference is clear to verify #390 (Fixed).
8. Toggle `Enable button row` and confirm that the disabled state updates visually to verify #390 (Fixed).
9. Toggle `Allow window resizing` to verify #401 (Fixed).
10. Observe the window resize / full screen button behavior to verify #401 (Fixed).

Expected results:

- Picker options should update when state changes, and the dropdown should not immediately disappear; if it fails, record it as a #449 (Fixed) regression.
- Clicking the Picker should not print WinUI/Composition rendering diagnostic logs such as `BVI-*`, `rcBackdropLocal`, or `CachedNewBlur`; if it does, record it as a #204 (Fixed) regression.
- TextEditor input should not drop keystrokes, and the unfocused TextEditor should match the expected borderless appearance; if it fails, record it as a #471 (Fixed) regression.
- Disabled controls should clearly look disabled; if not, record it as a #390 (Fixed) regression.
- When window resizing is disabled, the user should not be able to resize or full screen the window normally; if it is still possible, record it as a #401 (Fixed) regression.

### P3: Layout And Clipping

Run:

```zsh
./testapp/output/P3-WinUI.exe      # WinUIBackend, on Windows
```

Covered issues:

- #389 (Fixed): Images are not clipped
- P3 three-column test board initial layout regression (Fixed)

Test steps:

1. Launch `P3-WinUI.exe`.
2. Before resizing the window, confirm that the sidebar, middle, and detail columns are fully visible.
3. Confirm that the image detail column does not cover the sidebar or middle column.
4. Click `Force state update` and confirm that the three columns do not jump or suddenly correct themselves.
5. Resize the window and confirm that the three columns remain reasonable.
6. Click `Small`, `Medium`, and `Large` in the image size controls.
7. Observe the test image on the black background to verify #389 (Fixed).
8. Confirm whether the Large image is clipped by the 220x140 frame to verify #389 (Fixed).
9. Switch back to Small / Medium and confirm that the image updates normally and remains inside the frame to verify #389 (Fixed).

Expected results:

- The initial three-column layout should be correct without waiting for a state update or resize.
- The oversized image should not spill outside the black frame.
- If the image overflows the frame, record it as a #389 (Fixed) regression.
- If the initial layout is wrong but fixes itself after resize, record it as a P3 three-column layout (Fixed) regression.

### P4: WinUI Native And Callback Stress

Run:

```zsh
./testapp/output/P4-WinUI.exe      # WinUIBackend, on Windows
```

Covered issues:

- #190 (Fixed): Callbacks are stored in backend-wide hashmaps
- #156 (Fixed): WinUI-specific escape hatch / native API access
- #204 (Fixed): Update to latest stable WinUI / WinUI console noise
- #470 (Fixed): Regenerate WinUI bindings with latest swift-winrt

Test steps:

1. Launch `P4-WinUI.exe`.
2. Confirm that the native WinUI banner is displayed to verify #156 (Fixed).
3. Type text into `Native inspection text` to verify #156 (Fixed).
4. Confirm that the native banner content updates to verify #156 (Fixed).
5. Click `Force update` several times to verify #190 (Fixed).
6. Click several `Run N` callback buttons to verify #190 (Fixed).
7. Confirm that the `callbacks` count increases and `Selected row` updates to verify #190 (Fixed).
8. Click `More rows` several times to verify #190 (Fixed).
9. Scroll the row list to the bottom; confirm that the row window slides forward (the displayed range advances) while the scroll position stays visually continuous.
10. Click `Rows 250`, then `Run last`; confirm that the final row window is shown and the UI does not stall for a long time.
11. Click `Run 249`; confirm that `callbacks` and `Selected row` quickly update to 249 to verify #190 (Fixed).
12. Click `Fewer rows` several times to verify #190 (Fixed).
13. Click an existing row button again to verify #190 (Fixed).
14. Open the Picker or trigger a WinUI backdrop update; confirm that the console no longer prints `BVI-*`, `rcBackdropLocal`, or bare matrix/size noise to verify #204 (Fixed).

Expected results:

- Callbacks should not become incorrect, disappear, or crash.
- Scrolling near the bottom/top of the row list should slide the row window forward/backward while keeping at most 50 rows rendered (Windows only; use `Load next rows` on other platforms).
- After changing the row count, both old and new buttons should trigger the correct row.
- WinUI native inspection should be able to change the style of the underlying control.
- `Force update` and editing `Native inspection text` should update the native banner.
- When the row count is large, visible row callbacks should still update quickly.
- If callbacks point to the wrong row after many updates, record it as a #190 (Fixed) regression.
- If WinUI backdrop diagnostic noise appears in the console again, record it as a #204 (Fixed) regression.

### P5: Multi-Window Alerts

Run:

```zsh
./testapp/output/P5-WinUI.exe      # WinUIBackend, on Windows
```

Covered issues:

- #675 (Fixed): WinUIBackend could only show one dialog at a time app-wide (alerts queued across windows and couldn't stack within a window)

Test steps:

1. Launch `P5-WinUI.exe`.
2. Confirm that the main window `P5: Main window` appears.
3. Click `Open another window` to open a secondary window; confirm that a second window `P5: Secondary window` appears.
4. In the main window, click `Show Alert A`; confirm that `Alert A (Main)` appears.
5. While `Alert A (Main)` is still open, switch to the secondary window and click `Show Alert A`; confirm that `Alert A (Secondary)` appears immediately, without waiting for the main window's alert to close, to verify #675 (Fixed).
6. Dismiss both alerts.
7. In the main window, click `Show Alert A`, then click `Show Alert B (stacks on A)` without dismissing Alert A; confirm that `Alert B (Main)` replaces `Alert A (Main)` on screen to verify #675 (Fixed).
8. Click `Show Alert C (stacks on A+B)` without dismissing Alert B; confirm that `Alert C (Main)` appears on top to verify #675 (Fixed).
9. Dismiss `Alert C (Main)`; confirm that `Alert B (Main)` reappears to verify #675 (Fixed).
10. Dismiss `Alert B (Main)`; confirm that `Alert A (Main)` reappears to verify #675 (Fixed).
11. Dismiss `Alert A (Main)`; confirm that no alert remains and the window is interactive again.
12. Repeat steps 7-11 in the secondary window to confirm the same stacking/restoring behavior on a non-main window.
13. Click `Open another window` again from either window; confirm that a third window opens and all three windows can independently show/stack alerts at the same time.

Expected results:

- Alerts on different windows should be able to show at the same time; if the second window's alert does not appear until the first window's alert is dismissed, record it as a #675 (Fixed) regression.
- Stacking Alert B (or C) on the same window while an earlier alert is still open should hide the earlier alert and show the new one on top; if both appear at once in the same window, or the app crashes, record it as a #675 (Fixed) regression.
- Dismissing a stacked alert should restore the alert underneath it in the same window, in the correct order (C -> B -> A); if a restored alert is skipped or restored out of order, record it as a #675 (Fixed) regression.
- Closing one window should not affect alerts in other windows.

### P7: Lists And Split Views (Linux)

Run:

```zsh
./P7
```

Assisted WSLg/Windows comparison:

```zsh
zsh testapp/test.zsh P7 --both
```

Covered issues:

- #476 (Fixed): The List control starts with the first item already selected on the GTK backend
- #556 (Monitoring): Gtk List NavigationSplitView makes weird size decisions

Test steps:

1. Launch `P7`.
2. **Before clicking anything**, look at the plain List and the status line. The selection binding starts as nil, so no row should be highlighted and the status should read `Selection: none`, to verify #476.
3. Click `Cherry` in the plain List; confirm the status updates and only that row is highlighted.
4. Click `Clear selection`; confirm both lists show nothing selected.
5. Click `Select Cherry`; confirm the List highlights it when the selection is set from code.
6. Look at the NavigationSplitView: the sidebar and the detail pane should each keep a sensible share of the 420 px width, to verify #556.
7. Click `Add a fruit's worth of text`, which grows the text above the split view; confirm the split view does not jump to a different division.
8. Resize the window and confirm the split stays proportionate.

Expected results:

- Nothing is selected at launch. A highlighted first row is a #476 regression. Verified fixed on GTK4 and GTK3 under WSLg.
- The detail pane is visible and does not collapse to nothing, and the division does not change when unrelated text changes. As of 2026-09-01, P7 reports the same measured split ratio on WSLg and Windows: sidebar 200 / total 420, or 47.6%. Treat future failures as a new #556 repro and capture the diagnostic numbers before changing backend code.

### P8: Scroll Views (Linux)

Run:

```zsh
./P8
```

Assisted WSLg-first flow:

```zsh
zsh testapp/test.zsh P8 --both
zsh testapp/test.zsh P8 --both --showtime 60
zsh testapp/test.zsh P8 --both --no-showtime
```

The assisted flow waits for P8's `RENDER COMPLETE` marker, keeps the WSLg
window open for 30 seconds by default, captures a final screenshot, then repeats
the same sequence on Windows. Use this when the tester needs to inspect the
window live and report the visible problem.

Covered issues:

- #417 (Open): Giving a ScrollView a cornerRadius does not affect its children
- #426 (Open): Horizontal ScrollView swallows scroll wheel inputs for parent vertical ScrollView

Test steps:

1. Launch `P8`.
2. Look at the four corners of the red block in the first ScrollView. The frame has `cornerRadius(20)`, so the red should be rounded off at each corner, to verify #417.
3. Put the pointer over the second ScrollView, away from the horizontal strip, and scroll. Confirm the outer rows move.
4. Put the pointer **over the horizontal strip** and scroll vertically. Confirm the outer view still scrolls, to verify #426.
5. Over the strip, scroll horizontally; confirm the strip itself moves.
6. Scroll the strip to its right-hand end, then keep scrolling; confirm the outer view takes over rather than everything stopping.

Expected results:

- Red does not reach a square corner. If it does, that is #417.
- Vertical scrolling works with the pointer anywhere, including over the horizontal strip. If the outer view freezes there, that is #426.

### P9: Text And Field Sizing (Linux)

Run:

```zsh
./P9
```

Covered issues:

- #504 (Open): GtkBackend TextField/SecureField shrinks in height after first update
- #295 (Open): Clip Text when necessary to reach zero width

Test steps:

1. Launch `P9`. Note the height of the text field, the secure field and the `Reference` button next to them; at launch they should match.
2. Click `Force update` once. The button only increments a counter and does not touch the fields.
3. Compare the field heights against the `Reference` button again, to verify #504.
4. Click `Force update` several more times and confirm the heights do not keep shrinking.
5. Type into both fields and confirm text is still fully visible.
6. In the lower section, click `Narrower` repeatedly. The blue band marks the frame the label was given; the text must stay inside it, to verify #295.
7. Click `Zero width`; confirm the label takes no width rather than refusing to shrink.
8. Click `Wider` and confirm the text reappears as the frame grows.

Expected results:

- Field heights are unchanged by an unrelated update. Any shrink is #504.
- Text never spills past the blue band, and reaches zero width when asked. Spilling is #295.

### P10: Hit Testing And Shortcuts (Linux)

Run:

```zsh
./P10
```

Covered issues:

- #454 (Open): Transparent containers consume click events (AppKitBackend, GtkBackend)
- #478 (Open): GtkBackend Ctrl-Q/Cmd-Q does not quit application

Test steps:

1. Launch `P10`.
2. Click `Click me` several times and confirm `Direct clicks` increments.
3. With `Transparent overlay present` checked, click `Click me too`, which sits under a transparent `Color.clear` layer. Confirm `Covered clicks` increments, to verify #454.
4. Uncheck `Transparent overlay present` and click it again; confirm it increments now.
5. Compare: if the covered button only responds with the overlay removed, that is #454.
6. Click the middle of the orange block on the right and confirm `Hidden clicks` rises. The block is fully **opaque** and hides the button completely; only `allowsHitTesting(false)` can let the click through, which is what makes this a test of the modifier rather than of transparency.
7. Press Ctrl-Q (Cmd-Q on macOS), to verify #478.

Expected results:

- A transparent overlay does not block clicks. If the covered button only works once the overlay is removed, that is #454.
- An opaque layer with `allowsHitTesting(false)` does not block clicks either. If `Hidden clicks` stays at 0, the modifier is not reaching the backend.
- Ctrl-Q quits the app. If the window stays open, that is #478.

### P11: AppKit Sliders, Scrollbars And Pickers (macOS)

Run:

```zsh
./P11
```

Covered issues:

- #82 (Open): AppKitBackend sliders jitter when two sliders constrain each other
- #485 (Open): AppKitBackend scrollbar renders in the wrong direction
- #473 (Open): compact DatePicker sizing is off with Liquid Glass
- #404 (Open, noted only): View > Show Tab Bar affects window content size
- #425 (Open, noted only): window focus at launch is intermittent

Test steps:

1. Launch `P11`.
2. Drag the minimum slider past the maximum slider and watch whether both write counters climb while the values barely move, to verify #82.
3. Press `Separate them`, drag each slider normally, then press `Collide them` and drag again to compare the stable and constrained paths.
4. Inspect the vertical scrollbar in the scroll section and confirm the thumb direction is visually correct, to verify #485.
5. Compare the compact DatePicker height against the neighbouring reference button, to verify #473.
6. For #404, use the app menu manually: View > Show Tab Bar, then note whether the content size changes unexpectedly.
7. For #425, relaunch several times and record whether the window starts unfocused.

Expected results:

- Slider writes should track the slider being dragged, not enter a visible feedback loop.
- The scrollbar thumb should point and move in the expected direction.
- The compact DatePicker should align visually with neighbouring controls.
- #404 and #425 are noted as manual observations rather than strict pass/fail checks.

### P12: Android Margins, Rotation State And Toggles (Android)

Run on Android after building/deploying the app target for the Android backend.
The host build can still be used for a quick layout sanity check.

Covered issues:

- #632 (Open): AndroidBackend buttons have unnecessary margins
- #580 (Open): rotating the screen resets `@State`
- #544 (Open): button-style Toggle does not indicate on/off state visually
- #610 (Open, noted only): sheet sizing needs deeper measurement

Test steps:

1. Launch `P12` on an Android device or emulator.
2. Change the selected tab and increment the counter, then rotate the device to verify #580.
3. Compare the button backgrounds against the green reference bands; any visible gap is #632.
4. Compare the forced-on and forced-off button-style toggles side by side, to verify #544.
5. Press the toggle state buttons and confirm the visual state follows the forced values.
6. Note #610 separately if sheet sizing is being investigated; P12 does not turn it into a simple pass/fail check.

Expected results:

- Rotation should not reset the selected tab or counter.
- Button backgrounds should reach the button bounds without extra margins.
- On and off toggle states should be visually distinct.

### P13: Layout And View Graph (AppKit/Gtk)

Run:

```zsh
./P13
```

Covered issues:

- #415 (Open): non-Identifiable `ForEach` elements can crash AppKitBackend
- #595 (Open): Text inside a ScrollView is cut off
- #291 (Open): NavigationSplitView minimum width is deduced but the split is not moved to honour it
- #158 (Open): Group inside ZStack lays children out in the wrong axis

Test steps:

1. Launch `P13`; do not press the crash path first.
2. Compare the Identifiable list and hidden non-Identifiable section. Press `Show unidentified list (may crash)` only when ready to test #415.
3. In the ScrollView text section, compare the plain text and `.fixedSize()` control, to verify #595.
4. Adjust the split width and confirm the sidebar minimum width is honoured rather than letting the pane collapse, to verify #291.
5. Inspect the Group-in-ZStack section and confirm children overlap on the z axis rather than stacking vertically or horizontally, to verify #158.

Expected results:

- The Identifiable list should remain stable; the non-Identifiable path documents #415 if it crashes.
- ScrollView text should wrap without being clipped.
- Split view minimum widths should be reflected in the visible divider position.
- Group content inside ZStack should overlay, not stack along the container orientation.

### P14: UIKit Rotation And Theme (iOS)

Build and run:

```zsh
zsh testapp/compile.zsh -ios P14
xcrun simctl install swift-cross-ui testapp/output/P14-ios.app
xcrun simctl launch swift-cross-ui dev.swiftcrossui.testapp.P14
```

Covered issues:

- #324 (Open): rotation temporarily gives content a wrong size proposal
- #254 (Open): UIKitBackend restyles controls after a system theme change but leaves the app background behind

Test steps:

1. Launch `P14` in an iOS simulator.
2. Rotate the device and read the width history immediately after rotation, to verify #324.
3. Press `Clear history`, rotate once, and confirm whether a transient too-wide proposal appears before the final width.
4. Switch system appearance while the app is open, using the simulator menu or `xcrun simctl ui <device> appearance dark`.
5. Compare the app background, controls, and explicit adaptive colour block, to verify #254.

Expected results:

- Width history should not show a transient proposal wider than the settled layout after rotation.
- The app background should update together with controls and adaptive colours when the system theme changes.

### P15: Colour Scheme And Window Height (Linux)

Run:

```zsh
./P15                                   # inherit the system theme
GTK_THEME=Adwaita:dark ./P15            # the real test for #386
```

Covered issues:

- #386 (Open): GTK dark mode is unsupported; text keeps its light-mode colours
- #289 (Open): the window's minimum height is wrong where Gtk draws its own title bar (client-side decorations)

Checked in the source before writing these steps: `GtkBackend.swift` declares
`canOverrideWindowColorScheme = false`, and line 200 carries a
`TODO(stackotter): Support preferredColorScheme`. The scheme buttons are
therefore expected to do nothing on GtkBackend. They are the control group: the
same build on WinUIBackend does honour them, which separates "the override is
missing" from "the colours are computed wrongly".

Test steps:

1. Launch with `GTK_THEME=Adwaita:dark ./P15`.
2. Look at "Plain text on the default background" and the labels around it, to
   verify #386. Check whether text stays dark on a dark background.
3. Compare the foreground colours of the `TextField`, `Toggle` and `Button`
   against the theme.
4. Note the `Requested` and `Resolved` values shown on screen.
5. Press `Dark`, `Light` and `System`, and watch `Resolved`. It is expected not
   to change on GtkBackend.
6. Run the same binary on Windows under WinUIBackend and repeat step 5 as the
   control.
7. Drag the bottom edge of the window up until it stops shrinking, to verify
   #289.
8. Note the `Content area` size, and check whether anything is cut off at that
   smallest height.
9. Press `Use tall content` and repeat steps 7-8: the minimum height should
   grow with the content.
10. Press `Use short content` and confirm the window shrinks again.

Expected results:

- Text and controls follow the theme in dark mode. Keeping light-mode colours
  is #386.
- Nothing is clipped at the smallest height the window allows. A minimum that
  does not account for Gtk's own title bar is #289.
- WSLg is Wayland and Gtk uses client-side decorations there, so #289's
  precondition holds. That is not the same as Fedora with GNOME, so a negative
  result bounds the bug rather than closing it.

### P16: Split View Initial Layout (Windows)

Run:

```zsh
./P16-WinUI.exe
```

Covered issues:

- #160 (Fixed): WinUIBackend lays out NavigationSplitView incorrectly on the
  initial load, and it snaps to a correct layout on any state change or resize

**Read the numbers before touching anything.** The bug is defined by the first
render, and resizing the window is one of the two things that fixes it, so any
interaction destroys the evidence.

Test steps:

1. Launch `P16-WinUI.exe`. Do not move or resize the window.
2. Immediately note the sizes reported by the `sidebar` and `detail` panes.
3. Judge by eye whether the layout is visibly wrong -- sidebar filling the
   window, detail squeezed out, and so on.
4. Press `Force update`, which changes a counter unrelated to the layout.
5. Note the two pane sizes again. The difference between step 2 and step 5 is
   #160.
6. Relaunch and trigger the snap by resizing the window instead, to confirm
   both routes fix it.
7. Relaunch, press `Switch to 3 column`, and repeat steps 2-5 for the
   three-column layout.
8. Run the same app on Linux under GtkBackend as the control.

Expected results:

- The pane sizes at first render are already correct, and match the sizes after
  a forced update.
- 2026-09-01 verification: after initializing WinUI `createSplitView` with a
  sidebar width, P16 first render reports `sidebar: 180 x 22` and
  `detail: 660 x 22`; row text is no longer squeezed into wrapped text.
- Different numbers at step 2 and step 5 are #160, and the difference is how
  wrong "very incorrectly" actually is.
- Actionfile-driven interaction may still depend on Windows desktop /
  foreground / elevation state. If the Force update counter does not change,
  verify state-update stability manually.
- Sizes are displayed live rather than captured into state at first render:
  writing state during a layout pass feeds back into the layout it is
  measuring, and `GeometryReader`'s own documentation warns that content may be
  evaluated several times with different sizes before the layout settles.

### P17: Cross-Backend Layout Comparison (Linux and Windows)

Run:

```zsh
./testapp/output/P17          # GtkBackend, in WSL
./testapp/output/P17-WinUI.exe      # WinUIBackend, on Windows
```

Covered issues:

- #264 (Open): `frame(idealWidth:idealHeight:)` does not set
  `idealWidthForHeight` / `idealHeightForWidth`, which is what
  `fixedSize(horizontal:vertical:)` reads
- #161 (Open): backends disagree on whether a `Picker` is sized from its
  selected item or its largest item
- #266 (Open): two layout edge cases upstream wrote down while specifying the
  layout algorithm

Unlike P7-P16 this app is not aimed at one backend. **Every check is a
comparison**: run the same build under both backends and compare the numbers.
For #161 the comparison is the issue itself -- it is about backends disagreeing,
so a single-backend result cannot answer it.

Each measured view reports its own size, drawn on top of a blue box that shows
the view's extent. The readout deliberately covers the subject: what is under
test is the subject's box, not its contents.

Test steps:

1. Launch `P17` under one backend and record every reported size before
   changing anything.
2. Compare `subject` against `control` in the first section, to verify #264.
   Both are the same text with `idealWidth: 160`; only the subject also has
   `fixedSize(horizontal: true, vertical: false)`.
3. A subject width near 160 means the ideal width reached `fixedSize`. A width
   matching the control, or the full natural width of the text, is #264.
4. Note the `picker` width, then press `Shortest`, `Medium` and `Longest`,
   noting the width after each, to verify #161.
5. A width that changes with the selection means the picker is sized from the
   selected item; a constant width means it is sized from the largest item.
   Record which, because the issue is that the two backends differ.
6. Step the aspect-ratio scroll view through its heights with `Shorter` and
   `Taller`, to verify #266a. The content is a 2:1 box, so showing a scroll bar
   narrows it and therefore shortens it.
7. Watch for the height at which the scroll bar appears and disappears. It may
   do either, but it must settle. Flickering between the two states without
   settling is the failure.
8. In the last section, compare the three coloured bands, to verify #266b. They
   are a `VStack` of three different natural widths given a fixed height.
9. Press `Less height` and `More height` and check the bands stay equal in
   width at each step.
10. Repeat every step on the other backend and compare the two records.

Expected results:

- #264: the subject is about 160 wide. Matching the control instead means the
  ideal width never reached `fixedSize`.
- #161: whichever sizing rule applies, both backends apply the same one.
  Different rules on the two backends is the issue.
- #266a: the scroll bar settles at every height.
- #266b: all three bands share the widest child's width, at every stack height.

### P6: Zstd Stream Player

Build and run:

```zsh
zsh testapp/compile.zsh P6
./testapp/output/P6-WinUI.exe      # WinUIBackend, on Windows; P6 has no -gtk4 build
```

On macOS the output binary name may be `P6` instead of `P6-WinUI.exe`:

```zsh
zsh testapp/compile.zsh P6
./testapp/output/P6
./testapp/output/P6 -core
./testapp/output/P6 --debug
./testapp/output/P6 --frame-drop
./testapp/test_P6.zsh /path/to/video.webm
./testapp/test_P6.zsh -rss --debug /path/to/video.webm
```

Metal is the default macOS renderer. Pass `-core` to use the Core Animation
fallback, or `-metal` to select Metal explicitly. If both flags are present,
the last renderer flag wins.
The default output rate is 30 FPS. Pass `--debug` to enable full-frame duplicate
comparisons and detailed frame diagnostics; normal playback omits both costs.
Late-frame dropping is disabled by default. Pass `--frame-drop` to start with it
enabled, or use the runtime `Frame drop` toggle button to change it. During
playback, changing the toggle restarts video and audio from the current timestamp
so the new setting takes effect immediately.
For unattended runs, `-f` selects the input without the file dialog: `-f` alone
picks the first media file whose name contains `恩典365`, `-f <substring>`
matches any other name, and `-f <path>` takes a path directly. The search covers
the current directory, the directory holding the executable, and the default
input directory. `-autoplay` starts playback immediately and
`-enable-dropframe` turns on frame dropping, so
`P6-WinUI.exe -f -autoplay -enable-dropframe` needs no clicks at all.
`test_P6.zsh -win` and `P6-test.zsh` both wrap that combination;
`P6-test.zsh [file-pattern]` is the shorter form.
`compile.zsh` builds release by default so GUI timing reflects normal usage. Use
`BUILD_CONFIG=debug` only when unoptimised compiler-level debugging is needed;
app diagnostics should be controlled by app flags such as `--debug`.

`test_P6.zsh` prints its usage when no arguments are provided and otherwise
forwards renderer flags, `--debug`, `--frame-drop`, and the media path to the
compiled P6 binary. Its wrapper-only `-rss` option samples the P6 process RSS
once per second and appends `rss_kb`, `peak_rss_kb`, and the final exit status to
the separate `p6-debug-events-rss.log`; every `-rss` launch clears that file
before recording the new run, and `-rss` is not forwarded to P6.

Runtime tools:

- `ffmpeg` and `ffprobe` must be available on `PATH`.
- `zstd` must be available on `PATH` when selecting a `.zst` file.
- `ffplay` must be available on `PATH` for audio playback.
- LZFSE2/swift_tar `.zst` storybook streams are treated as zstd level 9 sources.
- macOS tool lookup also checks `/opt/homebrew/bin`, `/usr/local/bin`,
  `/opt/local/bin`, `/usr/bin`, and `/bin`, covering Apple Silicon Homebrew,
  Intel Homebrew, MacPorts, and system tools even when the app launches with a
  minimal GUI environment.
- The default file dialog directory checks both `~/proj/LZFSE2/swift_tar/images`
  and `~/proj/lzfse2/swift_tar/images`.

Diagnostics:

- P6 writes lifecycle and error messages only to `p6-debug-events.log` in the
  current working directory, keeping normal terminal output quiet. Detailed frame
  upload, presentation, and per-frame timing messages require `--debug` and are
  also written only to that file.
- `testapp/.compile-work-<backend>/` and `testapp/output/` are scratch:
  `compile.zsh` copies the selected source to
  `.compile-work-<backend>/TestApps/Sources/<name>/main.swift` and generates its
  `Package.swift`, so neither directory belongs in a commit. The suffix names the
  backend -- `-winui`, `-gtk4`, `-appkit`, `-android`, `-ios` -- and there is no
  suffix-less tree.

Test steps:

1. Launch `P6-WinUI.exe` and click `Choose file`.
2. Select `storybook-1min-4k60.mp4`, a WebM input, or `storybook-1min-4k60.y4m.zst`.
3. Confirm that the first frame appears and the selectable progress text uses the `Current: 01:17 / 04:02 (32%)` format when duration is available. Drag across the text and copy it to confirm text selection works.
4. Click `Show resolution`; confirm that its button background changes to the active state and a separate bottom line reports input resolution, output resolution, and the 960x540 viewport. Click it again and confirm that the bottom line disappears and the button returns to its inactive background.
5. Click `Play`; confirm that video playback starts and that audio starts too for inputs with an audio track when `ffplay` is available. Confirm that the log reports `playback clock token <n> started <time> speed <s>x fps <f> frame-drop <on|off>`, matching the token and captured settings of the preceding `session token <n> start` line.
6. Click the fixed-label `Sound` toggle during playback; confirm that its background is blue while enabled and uses the normal button appearance while disabled. Confirm that enabling sound restarts decoding from the current media timestamp so audio and video share one starting point, and that playback continues from where it was rather than jumping to zero.
7. With an audio track playing, let a direct MP4/WebM input run for at least three minutes; measure and record whether video progressively falls behind audio at each output resolution.
8. Click `Stop`; confirm that Stop preserves the current position and Play resumes it.
9. Drag the timeline slider through several positions and stop at a specific time. Confirm that `Seek target` updates continuously but only one decoder session starts 200 ms after the final slider change.
10. Click `Seek`; confirm that the displayed frame/time jumps to the slider target, and that playback continues from that target when playback was already running.
11. With the specified WebM sample, seek to 00:50 and confirm that the visible subtitle and spoken audio are both around `卻看我是祂的孩子`. Confirm from a standalone ffplay diagnostic that `-seek2any 1 -ss 50` starts the audio clock near 50.01 seconds instead of falling back near 46.05 seconds.
12. Click `-5s` and `+5s`; confirm that the displayed frame and time move by five seconds and clamp at zero/end.
13. Select `1x`, `2x`, and `3x`; confirm that selecting a speed does not switch focus to another terminal and does not immediately restart the decoder. Press Play or Seek to apply the new speed.
14. Confirm that `30` FPS is selected by default. Select `45` and `60` FPS; confirm that selecting FPS does not switch focus to another terminal and does not immediately restart the decoder. Press Play or Seek to apply the new presentation rate.
15. Select `Preview 960x540`, `1080p 1920x1080`, and `4K 3840x2160`; confirm that selecting resolution does not switch focus to another terminal and does not immediately restart the decoder. Press Play or Seek to apply the new output mode.
16. On macOS, confirm that all selectable playback controls, including `Sound`, `Frame drop`, and `Show resolution`, appear in one row and never add `on` or `off` to their button labels. Click each toggle and confirm that its background is blue while enabled and returns to the normal button appearance while disabled. Enable `Frame drop`; confirm that `Show resolution` is enabled automatically and cannot be turned off until Frame Drop is disabled. Confirm that the status line reports the Frame Drop state. During playback, confirm that toggling Frame Drop restarts one decoder/audio session from the current timestamp.
17. Relaunch with `--debug --frame-drop`, select `4K 3840x2160` and `60` FPS, and confirm that Frame Drop and Show Resolution both start enabled, the preview remains 960x540, the bottom information line reports dropped frames per second, and detailed logs report 3840x2160 frame uploads and cumulative late-frame drops.
18. Load a file, then seek or load another file; confirm that the terminal shows no `Broken pipe`, `Error muxing a packet`, or `Error writing trailer` output from ffmpeg when the previous decoder is stopped.
19. Close the window during playback, confirm the close prompt, and confirm that FFmpeg/Zstd/FFplay child processes exit and that the `P6` process itself also exits, returning the shell prompt.
20. Start playback from `test_P6.zsh`, obtain the ffplay PID from `p6-debug-events.log`, and press Ctrl-C in that terminal. Confirm in the log file that P6 received the signal, waited for ffplay to exit, and left no matching ffplay process running. Confirm that P6 diagnostic lines were not printed in the terminal. Because the script no longer uses `exec`, its observed exit status is shell-dependent when both zsh and P6 receive Ctrl-C.
21. Put a recognizable old line in `p6-debug-events-rss.log`, then relaunch through `test_P6.zsh -rss`, play and seek for at least one minute, and close P6 or press Ctrl-C. Confirm that the old line was cleared and the file contains only the new run's start line, one RSS sample per second, final sample count, peak RSS in KiB, and P6 exit status. Confirm that the terminal contains no RSS diagnostic lines and `p6-debug-events.log` remains reserved for P6 diagnostics.

Expected results:

- MP4, WebM, Y4M, and Y4M.ZST inputs decode at the selected output resolution.
- Direct inputs with audio tracks can play sound through `ffplay`; Y4M / `.zst` video-only paths should not crash.
- The timeline slider can quickly choose a target time, and `Seek` displays or plays from that target.
- Elapsed time, duration, and percentage share one selectable `Current` progress text; there is no separate percentage field in the options row.
- All selectable playback controls appear together in one options row.
- Continuous slider changes are debounced for 200 ms so intermediate drag positions do not repeatedly restart FFmpeg and ffplay.
- Selecting speed, FPS, or output resolution should not switch focus to another terminal, steal focus, or immediately restart the decoder.
- The visible viewport remains 960x540 and scales the decoded frame down for operation in a normal test window.
- `Sound`, `Frame drop`, and `Show resolution` use fixed button labels. Each toggle independently selects blue through `.toggleColor(.blue)`, uses that background while enabled, and returns to the normal button appearance while disabled; state is not appended to its label.
- `Frame drop` is a runtime toggle whose state appears in the status line; enabling it also enables and locks `Show resolution` on so the dropped-frames-per-second value remains visible. `--frame-drop` selects both initial on states.
- `Show resolution` uses an active button background while enabled and adds a separate information line at the bottom of the window; while frame dropping is enabled, that line also shows the sampled dropped-frames-per-second value.
- macOS renders decoded RGBA frames through a reusable three-texture Metal pool instead of allocating a texture or rebuilding a SwiftCrossUI image for every frame.
- Audio starts only after the first video frame is decoded, and video pacing uses an absolute monotonic clock to reduce accumulated per-frame timing drift.
- Each session log records its token, seek time, captured speed, FPS, resolution, and mode; the audio and playback-clock logs retain the same token and captured speed.
- Enabling sound mid-playback restarts decoding at the current media timestamp so the new `ffplay` process and the video stream share one starting point instead of running on unrelated clocks.
- Audio seeking enables non-keyframe demuxer targets so WebM playback starts near the requested slider time instead of falling back several seconds to the preceding video keyframe.
- Playback controls remain responsive while decoding runs off the UI thread.
- Normal playback does not scan complete RGBA frames for equality or synchronously log every frame; `--debug` enables those diagnostics when needed.
- By default, every decoded frame remains eligible for presentation. With `--frame-drop`, frames older than the audio-anchored monotonic deadline are discarded before reaching the UI and Metal renderer; combining it with `--debug` reports cumulative late-frame drops.
- Stopping a decoder early is a normal operation and must stay silent: child stderr is buffered rather than forwarded to the terminal, so ffmpeg's expected EPIPE reports do not appear. A genuine decode failure still surfaces the buffered tool output in the status line.
- Closing the window terminates the `P6` process itself, not just its child processes, so the shell prompt returns without a manual `Ctrl-C`.
- Terminal SIGINT and SIGTERM handlers terminate and synchronously reap the retained ffplay process before P6 exits. Without `exec` in the wrapper script, the final shell-visible Ctrl-C status is not guaranteed to be P6's internal status 130.
- `test_P6.zsh -rss` clears `p6-debug-events-rss.log` at launch, then measures only the P6 process resident memory once per second and records samples and peak RSS there; FFmpeg, ffplay, and zstd child RSS are not included.
- Missing tools or malformed input produce an error in the status line instead of crashing.

Verification status:

- The previously reported A/V desynchronization after timeline seeking is confirmed resolved with the supplied WebM sample. At a requested 00:50 seek, default ffplay demuxer seeking started audio near 46.05 seconds, while `-seek2any 1` starts it near 50.01 seconds. The visible subtitle and spoken phrase around that point are both `卻看我是祂的孩子`.
- The confirmation covers normal playback and timeline seeking without `--debug`. Extended 4K playback at every speed and Frame Drop combination remains a separate stress-test scenario rather than a confirmed regression.
- 2026-08-11: fixed a reproducible Windows-only crash (exception `0xc000001d`, illegal instruction in `dispatch.dll`) that occurred at first-frame publish, most reliably when a single-frame seek immediately terminates the decoder session. Root-caused via a `cdb` crash-dump stack trace to `P6DecoderSession.terminate()` closing `outputHandle` synchronously from inside its own `readabilityHandler` callback, a same-queue `dispatch_sync` self-deadlock that `dispatch.dll` traps instead of hanging. Fixed by moving the close onto a different queue (`DispatchQueue.global().async`). Confirmed fixed by repeated single-frame seeks and normal playback launches with no further crash or new crash dump.
- 2026-08-11: normal playback at default settings (30 FPS, Frame Drop off) was observed dropping approximately 17 frames/sec on Windows, rising to roughly 25 frames/sec at 4K where playback nearly stops. Investigation results:
  - ffmpeg is **not** the bottleneck. Running P6's exact 4K filter chain standalone decoded 20 seconds of video in 5 seconds (about 4x realtime).
  - A release build (`BUILD_CONFIG=release`) did not fix it, so the cost is not merely unoptimised code.
  - The bottleneck is the Windows display path. Each 4K frame previously cost: a 33 MB pipe read, a 33 MB `Array` copy, an `ImageFormats.Image`, a fresh 33 MB `WriteableBitmap` allocation, a 33 MB `memcpy`, an 8.3-million-iteration per-pixel RGBA→BGRA loop, and a SwiftCrossUI view-graph update -- roughly 4 GB/s of memory traffic at 30 FPS.
- 2026-08-11: a GPU presentation path was built for Windows, mirroring the macOS Metal design (`D3D11VideoSurface` in `Sources/WinUIBackend/D3D11VideoInterop.swift`): a D3D11 swap chain plus a rotating pool of three staging textures, presentation driven by frame arrival, with frames written straight into mapped GPU memory. No `Array`, no `ImageFormats.Image`, no `WriteableBitmap`, and no pixel conversion (ffmpeg's `rgba` output is byte-identical to `DXGI_FORMAT_R8G8B8A8_UNORM`). One `memcpy` remains, because `FileHandle.fileDescriptor` is unavailable on Windows; removing it needs a named pipe read via `ReadFile` in place of Foundation's `Pipe`.
- 2026-08-11: **the GPU path is not yet usable.** Two hosting approaches were tried and both are blocked:
  - `SwapChainPanel`: not projected by swift-winui. Activating it via `RoActivateInstance` works (`GetRuntimeClassName` confirms the correct runtime class, and `ISwapChainPanelNative` QI succeeds), but the generated wrapper classes resolve their COM interface lazily through a `try!`, so the process traps with an illegal instruction the moment a wrapped property is touched.
  - Child `HWND` + `CreateSwapChainForHwnd`: the swap chain is created and `Present` succeeds, yet nothing is visible. Since the child window overlaps the visible client area even when mispositioned, the video being entirely absent points to WinUI 3's airspace behaviour -- XAML composes through DirectComposition and occludes plain child windows.
  - Remaining options: host the swap chain on a DirectComposition visual, or create the `SwapChainPanel` and attach it to the visual tree from a C++/WinRT shim so no Swift wrapper is ever constructed.
- 2026-08-11: **the black screen is fixed and the GPU path displays.** No C++ shim was needed: the `SwapChainPanel` is driven entirely through raw COM (added to a projected `Canvas` via `IPanel::get_Children` + `IVector<UIElement>::Append`, sized through `IFrameworkElement::put_Width/put_Height`), so no Swift wrapper is ever constructed and the lazy-QI `try!` is never reached. The swap chain is created with `CreateSwapChainForComposition` and bound with `ISwapChainPanelNative::SetSwapChain` on the UI thread (that API is UI-thread only); the decode thread still only maps, copies, and presents.
- 2026-08-11: **the video appearing in the bottom-right corner was caused by `WinUI.Canvas` always reporting a zero DesiredSize.** A Canvas never measures its children, and `WinUIElementRepresentable`'s default `sizeThatFits` asks the element for exactly that, so the view was treated as 0x0, the layout centred it, and the swap chain drew from the middle of the video area outwards with the rest clipped away. The fix is for the representable to implement `sizeThatFits` itself. **This is a general upstream trap**: any representable rooted at a `Canvas` is mispositioned.
- 2026-08-11: **scaling is solved for 960x540, 1080p and 4K.** A SwapChainPanel composes one swap chain pixel per DIP, so the buffer is sized in physical pixels (which keeps the video sharp) and mapped back with `IDXGISwapChain2::SetMatrixTransform(viewport DIPs / buffer pixels)`. A frame smaller than the viewport is stretched by DXGI via `SetSourceSize`; a larger one (4K) is scaled down by the matrix. Neither needs a shader pass. Every geometry change goes through one API, `D3D11VideoSurface.setViewport(_:frameWidth:frameHeight:)`, which rebuilds the swap chain and texture pool only when their sizes actually change.
- 2026-08-11: the geometry is verified with `-calib`, which fills the swap chain with a red border, a green centre cross and corner blocks, and is then measured by scanning the screenshot's pixels rather than by eye. Both 960x540 and 4K measure as `x=360..1559` = 1200 px = the 960 DIP viewport, with the borders and centre cross where they should be.
- 2026-08-12: **the Windows bottleneck was the pipe, not the GPU, and it is now measured rather than inferred.** Per-stage timings are logged once a second (`stage timings:` lines). At 1080p the read stage cost 102-164 ms per frame against a 33 ms budget, while presenting cost 0-4 ms. The cause is Foundation's `Pipe`: swift-corelibs-foundation calls `CreatePipe(..., 0)` on Windows, so the buffer is the system default of a few kilobytes and an 8 MB frame arrives in thousands of reads, each allocating a `Data` that is then appended into a growing 8 MB buffer and copied a second time into the mapped texture. There is no API to configure that buffer size.
- 2026-08-12: P6 now creates its own Win32 pipe with an 8 MB buffer and reads frames with `ReadFile` straight into the mapped staging texture, in one call when the mapped row pitch matches the frame's rows. The read stage dropped to 0-17 ms per frame and **1080p reports 0 dropped frames/sec in every GPU mode**.
- 2026-08-12: GPU selection flags (`-amd`, `-nvidia`, `-both-gpu`, `-no-gpu`; `-both-gpu` decodes on the Nvidia card and presents on the display's adapter, `-no-gpu` presents through Microsoft's Basic Render Driver as a CPU baseline) plus `testapp/gpu-matrix.zsh`, which runs every mode and reports dropped frames/sec and stage timings. This machine has an AMD Radeon iGPU as adapter 0 and an Nvidia RTX 4060 as adapter 1. Measured over 25 s per mode:

  | Mode | 1080p read | 1080p dropped/s | 4K read | 4K dropped/s |
  |---|---|---|---|---|
  | default | 0-17 ms | 0.0 | 36-40 ms | 0.0 |
  | `-amd` | 1-14 ms | 0.0 | 42-47 ms | 0.0 |
  | `-nvidia` | 3-12 ms | 0.0 | 38-41 ms | 0.0 |
  | `-both-gpu` | 7-16 ms | 0.0 | 33-47 ms | 0.0 |
  | `-no-gpu` (WARP) | 2-3 ms | 0.0 | 43-51 ms | 0.0 |

  Presenting measured 0-6 ms in every mode at every resolution and frame rate. **The GPU choice makes no measurable difference, and neither does using no GPU at all.** Full results, including 60 FPS and the exact ffmpeg arguments per run, are in `testapp/P6_findings/gpu-modes.csv` (written by `gpu-matrix.zsh`); see `testapp/P6_findings/README.md`.
- 2026-08-12: **the decoder is not the bottleneck either.** Running the same filter chain standalone (`ffmpeg ... -f rawvideo -pix_fmt rgba -y NUL`) produced 4K60 frames at about 123 fps, roughly 2.1x realtime, while P6 consumed 1.1-2.3 fps. The same 33 MB frame reads in 58 ms at 4K30 and ten times slower at 4K60, which points at CPU contention: ffmpeg saturates the machine producing frames nothing is waiting for. Pacing the decoder to the playback rate (`-re` / `-readrate`) is the next thing to try.
- 2026-08-12: **the real ceiling was publishing, not the pipe.** After the pipe fix every configuration still sat at 7-8 frames/sec regardless of resolution or frame rate, which is the signature of a fixed per-frame cost rather than a bandwidth limit. Timing the main-actor hop showed it: `acceptFrame` sets `currentTime`, `seekPosition` and `status`, all `@Published`, so **every frame rebuilt the view graph and ran a WinUI layout pass, measured at 97 ms per frame** against budgets of 16-33 ms. The video never goes through the view graph, so the timeline and status text are now published at 2 Hz instead of per frame. Results, 20 s per configuration:

  | Configuration | Before | After |
  |---|---|---|
  | 1080p @ 30 | 7.8 fps | **26.6-29.2 fps**, 0.7-2.9 dropped/s |
  | 1080p @ 60 | 7.7 fps | **49.5-50.8 fps**, 7.9-10.1 dropped/s |
  | 4K @ 30 | 6.9 fps | **27.5-28.2 fps**, 1.2-2.1 dropped/s |
  | 4K @ 60 | 1.1 fps | 0.9-25.7 fps, 33-57 dropped/s |

  A single state update costing ~100 ms is a WinUIBackend finding in its own right and is worth investigating separately.
- 2026-08-12: two corrections to earlier entries. The dropped-frame figures reported as 0.0 were a bug in `gpu-matrix.zsh`, which summed the wrong awk field; drops were always in the tens per second at 4K. And pacing the decoder with ffmpeg's `-readrate` (the `-pace` flag) made no measurable difference, so the CPU-contention theory was wrong.
- 2026-08-12: **4K @ 60 is transport-bound and stays broken.** It needs about 2 GB/s of RGBA through the pipe, and frame dropping cannot help because a pipe cannot seek -- every frame to be dropped must still be read in full. 4K @ 30 is 1 GB/s and reaches 28 fps, which puts the measured ceiling near 1 GB/s. Across three repeats the five GPU modes vary wildly (`-both-gpu` measured 25.7, 10.2 and 5.6 fps) with no reproducible ordering, except that `-no-gpu` is consistently worst because CPU rasterising competes with the reader. The way out is fewer bytes: NV12 is 12 bpp against RGBA's 32, taking 4K @ 60 from 2 GB/s to 750 MB/s.
- 2026-08-12: **4K@60 is fixed by decoding to NV12 and converting on the GPU.** ffmpeg now emits `-pix_fmt nv12` (12 bpp against RGBA's 32), and a D3D11 video processor converts and scales it into the back buffer, replacing the `SetSourceSize` stretch on that path. NV12 has nothing to do with Nvidia -- "NV" is the FourCC -- so the choice is made by probing whether the presenting adapter can create the conversion, not by looking for a vendor. `-rgba` forces the old path as a control. Measured at 4K@60, 20 s per mode:

  | Mode | Format | fps | dropped/s | read |
  |---|---|---|---|---|
  | default | nv12 | **52.1** | 8.0 | 2.6 ms |
  | `-amd` | nv12 | **51.3** | 7.8 | 2.8 ms |
  | `-nvidia` | nv12 | **49.4** | 9.5 | 3.5 ms |
  | `-both-gpu` | nv12 | **51.3** | 7.8 | 4.3 ms |
  | `-no-gpu` | rgba (fell back) | 13.4 | 53.3 | 62.1 ms |

  Against 0.9-25.7 fps and 33-57 dropped/s on the RGBA path. The one mode that falls back is its own control within the same run: the pixel format is what matters, not the GPU. Verified visually as well -- colours are correct with `DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709` in and `RGB_FULL_G22_NONE_P709` out, and the picture still lands on exactly the 1200 px viewport (`x=173..1372` in a non-maximised window).
- 2026-08-12: three bugs found while building that path, all worth remembering:
  - The chroma plane's offset in a mapped NV12 texture **is `rowPitch * height`**, and must not be derived from the mapped size. This driver reports `DepthPitch` as `rowPitch * height` (2048 x 1080), not `rowPitch * height * 3/2`, so subtracting the chroma half landed chroma in the middle of the luma plane. The picture came out bright green with a corrupted lower half.
  - A video processor input texture needs `D3D11_BIND_DECODER`, not `D3D11_BIND_SHADER_RESOURCE`: the video engine reads it, the shader units do not. Otherwise `CreateVideoProcessorInputView` fails with `E_INVALIDARG`.
  - The NV12 capability probe has to run on the adapter that will present. Probing the default adapter and then presenting from the software one chose NV12 on a device that cannot convert it, and the NV12 bytes then reached the RGBA image fallback and trapped. The probe is adapter-aware now and the fallback never builds an RGBA image from NV12 bytes.
- 2026-08-12: a bigger decoder pipe buffer does not help. At 4K@60: 25 MB (two frames, the default) gave 49.9 fps, 128 MB gave 51.6, 512 MB gave 48.2, and **2 GB gave 45.3** -- slightly worse than the default. `CreatePipe` accepts 2 GB, but a pipe buffer absorbs jitter rather than raising throughput, and letting the decoder run seconds ahead only wastes memory and has to be discarded on a seek. The earlier 8 MB fix mattered only because the buffer was smaller than a single frame. `-pipe-mb <n>` re-runs this.
- 2026-08-13: **the decoder no longer opens console windows.** P6 spawns ffmpeg, ffplay, zstd and two ffprobes, and restarts the decoder on every resolution or frame-rate change; each spawn opened a console window whenever P6 had no console to inherit, which is the case when it is launched from Explorer or from a pty-based terminal. Foundation's `Process` passes only `CREATE_UNICODE_ENVIRONMENT` and offers no way to add `CREATE_NO_WINDOW`, so all five spawns now go through `P6WindowlessProcess`, which calls `CreateProcessW` directly. That also meant reimplementing argument quoting, handle inheritance, termination and exit codes; other platforms keep the Foundation path. See `testapp/todo-foundation.md`.
- 2026-08-13: linking the apps as GUI-subsystem executables was tried and reverted. It removes the console Explorer opens, but with children still spawned through Foundation it makes things worse: with no console to inherit, ffmpeg and ffplay get a console window each for as long as they run. The reasoning is recorded in `compile.zsh` so it is not attempted again without fixing the spawning first.
- 2026-08-13: **`-maximized` and bringing the window to the front now work**, and the fix was to identify the window by its title. The previous lookup took the calling thread's first visible window and fell back to `GetForegroundWindow()`, so before the XAML window existed it maximised and activated whatever the user was using -- the terminal that launched P6. It also timed the retry window from process start, which had already expired by the time the window appeared several seconds later. Both are fixed: matched by title, retried for five seconds from the moment the window is first found.
- 2026-08-13: **960x540 was cropped on the NV12 path** while 1080p and 4K were correct. The two paths present different regions: RGBA copies the frame into the buffer's corner and lets DXGI stretch that region, so the source is the frame; NV12 goes through the video processor, which scales the frame across the whole buffer, so the source is the whole buffer. Asking for the frame region there presented only its top-left corner, stretched. It is invisible whenever the frame is at least as large as the viewport, because the buffer is then the frame size -- which is why only the smallest preset showed it. Re-calibrated after the fix: the video spans `x=360..1559`, 1200 px, at every preset.
- Windows P6 follow-ups (not implemented yet):
  - The video area is fixed at 960x540 and **does not resize with the window**. `setViewport` is already the entry point for that -- it just needs the window size wired into it -- and the test steps should gain a "drag the window edge; the video area scales with it without distortion" check.
  - **4K playback still does not advance on its own** (about 20 dropped frames/sec, the progress bar stalls). Dragging the progress bar shows the frame correctly, so the bottleneck is not the presentation path but the 33 MB per frame read through Foundation's `Pipe`. Fixing it needs a named pipe read via `ReadFile`, or hardware decoding/CUDA.
  - CUDA is not implemented; the path is pure D3D11/DXGI today.

RSS stress record:

- `p6-debug-events-rss-8845476c-speed3x,fps60,4k_3840x2160_sound_on_frame_drop.log` records P6 commit `8845476c` at 3x speed, 60 FPS, 3840x2160 output, Sound On, and Frame Drop enabled.
- The run lasted from 2026-08-04 18:25:39 UTC through 18:28:58 UTC, collected 196 valid one-second samples, and exited successfully with status 0.
- P6 peak RSS was 2,398,896 KiB (approximately 2.29 GiB), and average sampled RSS was approximately 1.92 GiB. These values exclude FFmpeg, ffplay, and zstd child processes.

### P18: File Dialogs (Linux and Windows)

Run:

```zsh
./testapp/output/P18          # GtkBackend, in WSL
./testapp/output/P18-WinUI.exe      # WinUIBackend, on Windows
```

Not tied to an issue. GtkBackend moved off `GtkFileChooserNative`, which the
GIR marks `deprecated="1"` and which did not close its dialog on Wayland
without an xdg-desktop-portal, onto `GtkFileDialog`. The migration rewrote four
paths and only a plain single-file open had ever been run. This app runs the
rest and compares them against WinUIBackend.

Not covered: multiple selection. `PresentSingleFileOpenDialogAction` hardcodes
`allowMultipleSelections: false`, so `gtk_file_dialog_open_multiple` cannot be
reached from any application.

Test steps:

1. Launch P18 under one backend. Each button opens one dialog and reports what
   came back on the line beneath it.
2. Press `Open a file`, choose any file, and confirm the dialog closes and the
   line shows the path. **The dialog closing is itself part of the result** --
   the original defect was a dialog that stayed on screen after delivering the
   file.
3. Repeat with Cancel and confirm the dialog closes and the line reads
   `cancelled`.
4. Press `Choose a folder`, select a directory, and confirm the same two things.
   This is a different GTK call from the file open.
5. Press `Choose a save destination`. Confirm the name field is prefilled with
   `p18-example.txt`, which is the only path that exercises the initial name.
6. Repeat every step under the other backend and compare. What matters is
   whether both deliver a path and both dismiss the dialog, not that the
   dialogs look alike.

### P19: Flat Menus (Linux and Windows)

Run:

```zsh
./testapp/output/P19          # GtkBackend, in WSL
./testapp/output/P19-WinUI.exe      # WinUIBackend, on Windows
```

The two backends render the same `Menu` through different mechanisms and the
app cannot choose between them. GtkBackend conforms to `PopoverMenus`, creating
and positioning a separate menu widget; WinUIBackend conforms to
`AttachedMenus`, handing a menu to a button and letting the platform build it.
These are two implementations of one feature, not a capability either lacks.

P19 keeps to a single flat level so that any difference is unambiguously about
how items render. Nesting is P20.

Test steps:

1. Launch P19 and press `Open the menu`.
2. Confirm all five entries appear: two buttons, a non-clickable text item, a
   separator, and a toggle.
3. Note whether the text item and the separator render at all. A backend that
   drops either is the finding.
4. Press `Button item` and confirm `last action` updates.
5. Open the menu again, use the toggle, and confirm `toggle item` reflects the
   new state. Note whether the menu stays open or closes when a toggle is used.
6. Note where the menu appears relative to the button, and record it. The two
   mechanisms position menus differently and this is the comparison.
7. Repeat under the other backend.

### P20: Nested Menus (Linux and Windows)

Run:

```zsh
./testapp/output/P20          # GtkBackend, in WSL
./testapp/output/P20-WinUI.exe      # WinUIBackend, on Windows
```

Separate from P19 on purpose. Nesting is where the two mechanisms have the most
room to diverge: one gets the whole tree from the platform, the other builds and
positions every level itself.

Every level carries a clickable item, so `level 2 opens but its button does
nothing` can be told apart from `level 3 never appears`.

Test steps:

1. Launch P20 and press `Open the menu`.
2. Press `Level 1 item` and confirm `last action` reads `level 1`.
3. Open the menu again and hover or click `Level 2 submenu`. Record which one
   opens it -- hover and click are both legitimate and the backends may differ.
4. Press `Level 2 item` and confirm `last action` reads `level 2`.
5. Open `Level 3 submenu` and confirm it appears at all. This is the step most
   likely to fail on one side.
6. Press `Level 3 item`, then use `Level 3 toggle`, and confirm both reach the
   app: `last action` reads `level 3` and `level 3 toggle` flips.
7. Note where each submenu lands relative to its parent, especially near a
   screen edge.
8. Repeat under the other backend.

### P6-v2: Video Playback on GtkBackend (Linux and Windows)

Run:

```zsh
./testapp/output/P6-v2 -i <file> -autoplay              # GtkBackend, in WSL
./testapp/output/P6-v2-gtk4.exe -i <file> -autoplay          # GtkBackend, on Windows
```

Build it with `-gtk4`. P6 is **not** the comparison target on Windows in the
usual sense: P6 is the WinUI/D3D11 implementation and `compile.zsh -gtk4`
refuses to build it, because a SwapChainPanel and a D3D11 composition swap chain
have no GtkBackend equivalent. P6-v2 is the GTK answer to the same question,
written fresh, keeping P6's measurement vocabulary so the numbers line up.

Flags that matter:

| flag | effect |
|---|---|
| `-cpu` | force software decode |
| `-gpu` | force hardware decode; refuses to start if none is available |
| (default) | try hardware, fall back to software, and say which ran |
| `-mute` | no ffplay; use this for measurement runs |
| `-seconds N` | exit after N seconds and print the summary |
| `-speed` `-fps` `-res` | preset the pickers so a run needs no clicking |

Test steps:

1. Launch with `-autoplay -seconds 20 --debug` and confirm the window renders.
   On Windows the window does not respond to AppActivate, so capture it with
   `zsh testapp/screenshot.zsh -w "P6-v2 GTK playback" <label>`, which reads the
   window directly rather than the desktop.
2. Read the status line. It states the decode path and the presentation path
   separately -- `decode d3d11va, present memory-texture (CPU)`. Presentation is
   the CPU path in every mode today; the flag switches decode only.
3. Confirm audio. It is a separate ffplay process, so sync is not enforced: at
   1x it tracks well enough to watch, at 3x it drifts. That is expected.
4. Run `-cpu` and `-gpu` back to back at the same speed, fps and resolution, and
   compare the summary lines. On this machine they came out within noise of each
   other, because the bottleneck is the RGBA pipe read, not decode.
5. Push the speed to `3x` and watch `dropped/sec`. Dropping only happens when
   frames arrive faster than they can be shown; a decoder that is simply slower
   than the target presents everything and reports a lower fps instead.
6. Repeat on the other platform and compare. WSL has no GPU path at all -- no
   render node, so GTK is on llvmpipe -- so a Windows-against-WSL comparison here
   measures two different rendering stacks, not two operating systems.

### P21: Input Controls (Linux and Windows)

Run:

```zsh
./testapp/output/P21          # GtkBackend, in WSL
./testapp/output/P21-WinUI.exe      # WinUIBackend, on Windows
```

The widest uncovered surface. ToggleSwitch, ToggleButton and Checkbox appear in
no other test app. Every control appears twice, enabled and disabled.

Test steps:

1. Press `Enabled` under Button and confirm `clicks` rises.
2. Press `Disabled` and confirm `clicks` does **not** rise. A disabled control
   that still accepts input is the finding here, and it looks correct in a
   screenshot.
3. Work down each toggle style -- plain, `.switch`, `.button`, `.checkbox` --
   operating the enabled one and confirming the disabled one refuses.
4. Compare how each backend renders the disabled state: greyed label, dimmed
   widget, or no change at all.
5. Drag both sliders; the disabled one must not move.
6. Type into `TextField`, `SecureField` and `TextEditor`, then try their
   disabled counterparts.
7. Confirm `ContentUnavailableView` shows both its title and description.
8. Repeat under the other backend.

### P22: Text Styles (Linux and Windows)

Run:

```zsh
./testapp/output/P22 --debug          # GtkBackend, in WSL
./testapp/output/P22-WinUI.exe --debug      # WinUIBackend, on Windows
```

Worth doing early, because font metrics are the measuring stick for every other
layout comparison. A backend whose text is systematically wider will produce
different results in P17's sizing checks and P7's split ratios, and without this
app that difference gets attributed to the layout code instead of the font.

Test steps:

1. Run with `--debug` and collect the reported sizes for each of the eight
   samples. These are numbers, not impressions of a screenshot.
2. Compare the two backends sample by sample. A consistent ratio across all
   eight is a font difference; a difference at one size only is a layout bug.
3. Press `Narrower` and `Wider` and record where the wrap lands at each width.
4. Check the three alignment rows inside their fixed 320pt frames.
5. Repeat under the other backend.

### P23: Tables (Linux and Windows)

Run:

```zsh
./testapp/output/P23 --debug          # GtkBackend, in WSL
./testapp/output/P23-WinUI.exe --debug      # WinUIBackend, on Windows
```

Column width is the interesting part. Nothing in the API states a width, so each
backend picks: from the header, from the widest cell, from the first screenful,
or by dividing the available space. Column 2 is deliberately wider than its
header and column 3 narrower, so which rule is in use is visible at a glance.

Test steps:

1. Note where each column boundary lands, and which of the four rules that
   implies.
2. Look at row 3, whose cell is far longer than any header. Record whether it
   widens its column or is truncated.
3. Press `More rows` past the window height and confirm whether the table
   scrolls or clips.
4. Press `Fewer rows` and confirm the layout recovers rather than leaving a gap.
5. Repeat under the other backend.

### P24: Navigation Stack (Linux and Windows)

Run:

```zsh
./testapp/output/P24 --debug          # GtkBackend, in WSL
./testapp/output/P24-WinUI.exe --debug      # WinUIBackend, on Windows
```

`NavigationStack` and `NavigationLink` appear in no other test app. This gap was
once dismissed on the grounds that P7 and P16 cover navigation, which was wrong:
those exercise `NavigationSplitView`, a different type with a different layout
model. A sidebar-and-detail split is not a push-and-pop stack.

What a stack has that a split view does not is history.

Test steps:

1. Push three levels with `Push level N` and confirm each screen appears.
2. Go back through them and confirm they return in order.
3. At each level press `Record a push` and compare `pushes recorded` against the
   level shown. The counter lives outside the stack on purpose: if the screen
   says level 2 while the counter says 3, that disagreement is the finding.
4. Press `Increment counter` at depth, then go back, and confirm the path
   survived the state change.
5. Press `Pop to root` and confirm both the screen and the counter reset.
6. Repeat under the other backend.

### P25: Drag and Drop (Linux and Windows)

Run:

```zsh
./testapp/output/P25 --debug          # GtkBackend, in WSL
./testapp/output/P25-gtk4.exe --debug      # -gtk4 build, on Windows
```

Drag and drop appears in no other test app because SwiftCrossUI had no API for it
until `onDrop(of:isTargeted:perform:)` was added. The questions worth asking are
the ones where the platforms have room to disagree, not whether a drop arrives:
Windows delivers a path through `CF_HDROP` and X11 delivers a `text/uri-list`, so
`received` is printed verbatim and never normalised.

Test steps:

1. Drag a file from the file manager over the accepting area and confirm it
   highlights **before** the button is released. A backend that only reacts on
   release is usable but wrong, and invisible without somewhere to look.
2. Drop the file and confirm `state` reads `accepted`, `count` is 1, and
   `received` shows the payload as the platform delivered it.
3. Drag the same file over the refusing area and confirm it does **not**
   highlight and reports nothing. This is why there are two areas: a drop zone
   that silently swallows what it cannot handle looks identical to one that
   rejects it, until they are side by side.
4. Drop several files at once and record whether they arrive as several items or
   as one string.
5. Repeat on the other platform and compare the two `received` values.

Note: this cannot be driven by an action file. Drag and drop is an OS-level
negotiation, not a sequence of mouse events, so `InputEvent` cannot synthesise
it; step 1 onwards needs a real drag.

### P26: Networking and the App Cache (Linux and Windows)

Run:

```zsh
./testapp/output/P26 --debug
zsh testapp/test.zsh P26 --cache-only   # cache assertions without the window
```

Covers `AsyncImage`, the `appCache` and the networking comparison table. Unlike
every other Pn, half of this is observable only across runs -- a cache proves
itself by the second fetch not downloading anything.

Test steps:

1. Launch with no cache present and confirm the images load and the cache
   directory is created on first fetch.
2. Relaunch and confirm nothing is downloaded and the images still appear.
3. Check the `not_latest` column reports staleness rather than deleting the
   entry -- a cached copy has to survive a failed fetch, or going offline loses
   the content it was meant to protect.
4. Switch to the SwiftUI tab and confirm it renders nothing on Linux, which is
   correct: SwiftUI is not available there.
5. Confirm the Summary table's cells can be selected and copied.

### P27: Backend Feature Coverage (Linux and Windows)

Run:

```zsh
zsh testapp/test.zsh P27 --both
```

Covers backend features whose absence should be exposed as visible fallback or
diagnostic behaviour rather than a silent no-op or hard crash.

A missing backend conformance goes through `@CastBackend`, which turns it into
`fatalError("'GtkBackend' does not implement ...")`. So an app containing a
`WebView` aborts on GTK the moment that view is laid out, and `AngularGradient`
does the same -- both on Linux and on Windows `-gtk4`. AppKit implements both.

Test steps:

1. Show a `WebView` and confirm the app does not abort.
2. Show an `AngularGradient` beside a `LinearGradient` and a `RadialGradient`
   and confirm all three render.
3. Repeat under WinUIBackend and AppKit and compare.
4. Confirm that a feature a backend genuinely cannot provide degrades visibly
   (a blank area) rather than aborting -- the decision this app exists to force.

### P28: Control Styles (Linux and Windows)

**Planned, not yet written.** Covers styles that assert in a debug build and
silently downgrade in release.

`supportedPickerStyles` is `[.menu]` on GtkBackend against `[.menu, .segmented,
.radioGroup]` on AppKit, and `supportedDatePickerStyles` lacks `.compact`. The
style modifiers hit `assertionFailure` and fall back to `.automatic`, so
`.pickerStyle(.segmented)` crashes a debug GTK build and quietly becomes a
dropdown in release -- a different-looking control from every other platform.

Planned test steps:

1. Show one picker per style -- `.menu`, `.segmented`, `.radioGroup`, `.palette`
   -- and record which render as asked and which silently become a dropdown.
2. Same for `.datePickerStyle(.compact)` against `.graphical`.
3. Confirm a debug build does not abort on an unsupported style.
4. Set `displayedComponents: .hourAndMinute` and confirm time entry appears.
   GtkBackend currently logs `time picker is unimplemented` and shows a bare
   month grid, in the wrong calendar and timezone.
5. Compare all of the above against WinUIBackend.

### P29: Visual Fidelity (Linux and Windows)

Run:

```zsh
zsh testapp/test.zsh P29 --both
```

Covers output that can be wrong on one backend with no diagnostic at all -- the
failures a log will never reveal.

Test steps:

1. Show an indeterminate `ProgressView()` with no value. GtkBackend sets the
   fraction to zero and never pulses, so it renders as a static empty bar and
   reads as "stuck"; AppKit and WinUI animate it.
2. Put an oversized image inside `.cornerRadius(20)`. The clip is rectangular on
   GtkBackend, so the corners stay square underneath a rounded border; AppKit
   and WinUI clip to the rounded shape.
3. Show a `List` whose rows have an explicit `.frame(height:)` and compare the
   rendered heights against the layout. GtkBackend discards the row heights it
   is handed and reports zero base padding while the theme adds real padding, so
   the list is measured differently from how it draws.
4. Put a `TextEditor` inside `.disabled(true)` and confirm it cannot be typed
   into. GtkBackend never sets `sensitive` on it.
5. Compare `.fontWeight(.semibold)` against `.bold`; they map to the same CSS
   weight on GtkBackend.

### P30: Effects and Animation (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** Covers the
largest protocol-level gap: SwiftCrossUI has no animation layer at all, and only
the effect modifiers currently available in the project can be exercised.

There is no `Animation`, `withAnimation`, `.animation(_:value:)`, `.transition`
or `Namespace`, and no backend protocol for any of them. ~~Visual effects and
geometric effects now have partial coverage, but backend parity is
incomplete:~~ GtkBackend renders blur and colour filters, while ~~WinUIBackend
currently applies opacity only~~ — **superseded 2026-09-02** (kept, not deleted,
so the stale claim stays on record): WinUIBackend now renders all seven through
a Win2D effect graph, verified 2026-09-02 with `applied=8 failed=0 total=8`
(`cd testapp/output && SCUI_DEBUG_VISUAL_EFFECTS=1 ./P39-WinUI.exe`, then read
`winui-visual-effects-debug.log`). **Also superseded 2026-09-02: the visual and
geometric effect families now have full backend parity on the shipped desktop
and mobile targets.** AppKitBackend implements both — a `CIFilter` chain and a
`CATransform3D` — and UIKitBackend implements both as well, its visual effects
through Core Image over a `CALayer.render(in:)` bitmap rather than through
`CALayer.filters`, which does not composite on iOS. Verified on P39 and P40; see
those sections. `.shadow`, `.zIndex`, `.clipShape` and `.mask` are still
absent.
Every SwiftUI state change is implicitly animatable, so animation remains the
widest behavioural divergence in the toolkit.

This app started as a pre-feature boundary document and now serves as a
compileable baseline for the effect APIs that exist. Keep using it to separate
"API does not exist" from "API exists but a backend renders it as a no-op".

Current automated flow:

```zsh
zsh testapp/test.zsh P30 --both
```

The app shows compileable visual/geometric effect samples and keeps the missing
animation APIs visible as text. It also writes `p30-debug-events.log` when run
with `--debug`. ~~Current WinUI support is partial: opacity is implemented, while
blur, grayscale, saturation, brightness, contrast and hue rotation are confirmed
no-ops until the backend builds a real Composition / Win2D effect graph.~~
**Superseded 2026-09-02:** the struck-through sentence is kept rather than
deleted, because it was true of the binary of its date and shows what a
plausible-but-now-false claim looks like. WinUI now implements all seven:
`WinUIBackend+VisualEffects.swift` builds a real Win2D effect graph
(`Win2DEffectGraph`) and `Microsoft.Graphics.Canvas.dll` ships in
`testapp/output/`. Verified 2026-09-02: `applied=8 failed=0 total=8` —
regenerate that number with
`cd testapp/output && SCUI_DEBUG_VISUAL_EFFECTS=1 ./P39-WinUI.exe`, then read
`winui-visual-effects-debug.log`.

Test steps:

1. Toggle a `@State` value that changes a frame and confirm whether the change is
   instant (current behaviour) or animated.
2. Compare opacity, blur and grayscale samples against the control.
3. Compare offset, scale and rotation samples against the control.
4. Confirm that animation-only APIs remain documented as missing rather than
   being represented by broken sample code.
5. Compare each against the same code under AppKit when that backend is in
   scope.

### P31: Focus and Keyboard (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** Roughly half of
what this app has to check can be written today; the other half remains a list
of calls that do not compile.

Nothing in SwiftCrossUI names focus. There is no `@FocusState`, no
`.focused(_:)` and no `.focusable()`, so an app cannot say which field starts
focused, cannot move focus after a button is pressed, and cannot read where
focus currently is. Whatever the platform does by default is the entire
behaviour.

Keyboard shortcuts have the same shape. There is no `.keyboardShortcut`, no
`KeyEquivalent` and no `EventModifiers`. `Commands` and `CommandMenu` do build a
menu bar, but they resolve to `ResolvedMenu.Item`, whose `button` case carries a
label and an action and nothing else -- there is no field a key equivalent could
travel in, so the gap is in the data structure, not only in the modifier.
`CommandGroup` does not exist at all.

Two backend behaviours are worth measuring on their own. GtkBackend installs
exactly one accelerator, `<Control>q` bound to `app.quit`, in
`installQuitShortcut()`; it is the only key binding the toolkit creates.
`createAlert()` then attaches a shortcut controller that consumes `Escape` so it
cannot close the dialog, and the response handler discards GTK's delete-event
response. Both are deliberate, and both are invisible until an app presses the
key and reports what happened.

Test steps:

1. Tab through a window holding a `TextField`, a `Button`, a `Toggle` and a
   `Slider`, and record the order focus visits them and whether the focused
   control is visibly marked. This is entirely the platform's doing, so a
   difference here is a GTK-against-WinUI difference and not a SwiftCrossUI one.
2. Press Space and Return on each focused control and record which ones
   activate. A control that is reachable but not operable from the keyboard
   looks correct in a screenshot.
3. Press Ctrl+Q. Under GtkBackend the app must exit. Under WinUIBackend nothing
   should happen, because no equivalent binding is installed; that asymmetry is
   the finding, not a bug in either backend.
4. Open an alert, press Escape, and confirm the dialog stays open. Then press
   one of its buttons and confirm the response arrives. Escape doing nothing and
   Escape dismissing while reporting no response are different failures, and
   only pressing a button afterwards separates them.
5. Reach a `CommandMenu` item using the keyboard alone, through the menu bar's
   own traversal, since no item can declare a shortcut. Record how many
   keystrokes it takes.
6. Keep the list of calls that do not compile in the app itself: `@FocusState`,
   `.focused($field)`, `.focusable()`,
   `.keyboardShortcut("s", modifiers: .command)`,
   `CommandGroup(replacing: .newItem) { ... }`. Each line that starts compiling
   is the progress report.
7. Repeat under the other backend.

Automated flow:

```zsh
zsh testapp/test.zsh P31 --both
```

The automated run verifies launch, render marker, final screenshot and the
visible baseline controls. Real focus traversal, Escape handling and Ctrl+Q
still require manual keyboard interaction.

#### Measured 2026-09-03 on Windows / GtkBackend — steps 1 and 2 pass, step 4 cannot be run

Driven by `testapp/actions/win/P31-tab-and-escape.csv`, which is the first
action file in this tree to press a key at a dialog at all.

Regenerate with `zsh testapp/run.zsh P31 -actionfile testapp/actions/win/P31-tab-and-escape.csv`,
then read `p31-debug-events.log` **in the directory you ran it from** — see the
note below, it is not in `testapp/output/`.

- **Steps 1 and 2 pass.** `key tab` moved focus out of the `TextField` and the
  following `key space` activated the button: `p31-debug-events.log` records
  `button clicked count=1`. Tab traversal and Space activation are therefore
  *present* on Windows/GtkBackend. Since SwiftCrossUI names no focus API at all,
  this is entirely the platform's own behaviour — which is what step 1 says to
  expect, and it is the first time it has been measured rather than assumed.
- **Step 4 cannot be performed by an action file, and this is not a P31 result.**
  Escape did not dismiss the alert, but the run cannot tell you whether GTK
  consumed the key as `createAlert()` intends, because **the key never reached
  the dialog**. `Win32Synthesiser.ownWindow()` picks this process's
  largest-area visible top-level window, and a `Gtk.MessageDialog` is a smaller
  separate top-level window, so it can never be selected; the synthesiser then
  calls `SetForegroundWindow` on the main window, taking focus off the modal.
  Full write-up in `bugs/Gtk4-bugs.md` §6. **Until that is fixed, step 4 stays a
  manual step, and a replay reporting no error is not evidence either way.**
- **Steps 3, 5, 6 and 7 remain unmeasured** on this platform.

**Escape is not a portable way to dismiss a modal.** `testapp/actions/mac/README.md`
recommends Escape precisely because it "reaches a key window without a
coordinate", and on macOS that is true. **On Windows it is false** for the reason
above: the key is addressed to a window chosen by area, not to the window that
is modal. Do not port a mac action file's Escape row to `win/` and read a
non-error as a pass.

**Where P31's log goes.** P31 builds its path from
`FileManager.default.currentDirectoryPath`, so `p31-debug-events.log` lands in
whatever directory launched it — the repo root when driven through
`testapp/run.zsh`, not `testapp/output/`. This is not specific to P31:
**every one of the 35 `testapp/P*.swift` apps that writes a debug log uses
`currentDirectoryPath`**, and so does `splitview-debug.log`
(`Sources/SwiftCrossUI/Views/SplitView.swift:215`). The remaining 12 write no
log at all. Re-derive with
`grep -c currentDirectoryPath testapp/P*.swift`. There is therefore **one**
convention, not two — the mac docs saying `testapp/output/p28-debug-events.log`
are right only because that flow `cd`s into `testapp/output` first, whereas
`run.zsh` launches by absolute path and never changes directory.

### P32: Accessibility (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** The app calls
nothing that is missing. It exists to be inspected from outside.

SwiftCrossUI has no accessibility API. There is no `.accessibilityLabel`,
`.accessibilityHint`, `.accessibilityValue`, `.accessibilityAddTraits`,
`.accessibilityHidden`, `.accessibilityElement` or `.accessibilityIdentifier`,
and no backend protocol for any of them, so no backend can be asked to set one.
The nearest thing is `.help(_:)`, which goes through `BackendFeatures.Tooltips`
and sets a hover tooltip; UIKitBackend also assigns `accessibilityHint` from it,
and GTK and WinUI do not.

That does not mean the tree is empty. GTK exposes AT-SPI, WinUI exposes UI
Automation and AppKit exposes NSAccessibility, and each hands a widget a default
role and often a default name taken from its label. So the question here is not
whether accessibility exists but how much of it survives without an API: which
elements appear, which carry a usable name, and which are anonymous boxes. That
baseline is what any future labelling API gets measured against, and it has to
be recorded before the API exists or there is nothing to compare against.

Test steps:

1. Build a window holding a labelled `Button`, an icon-only `Button` with no
   text, a `TextField` with placeholder text, a `Toggle`, a `Slider`, a
   `ProgressView` and an `Image`.
2. On Linux, read the tree with Accerciser and record each element's role and
   name.
3. On Windows, read the same window with Accessibility Insights or
   `inspect.exe` and record each element's control type and Name.
4. Compare the two lists element by element. An element present on one platform
   and absent on the other is a backend gap; an element present on both with an
   empty name is the API gap this section is about, and the two want different
   fixes.
5. Apply `.help("...")` to the icon-only button and record whether the text
   reaches the accessibility tree, the tooltip only, or neither. Check both
   platforms; the code paths are not shared.
6. Drive the window with a screen reader -- Orca on Linux, Narrator on Windows
   -- and write down verbatim what it announces for the icon-only button. "Button"
   with no name is the expected result today; record the exact announcement
   rather than a summary of it.
7. Confirm the announced order matches the visual order. A layout container can
   reorder its children in the tree without changing what is drawn, and nothing
   on screen would show it.

Automated flow:

```zsh
zsh testapp/test.zsh P32 --both
```

The automated run verifies that the baseline controls render. Role/name
inspection still requires Accerciser on Linux and Accessibility Insights or
`inspect.exe` on Windows.

### P33: Missing Views (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** Covers the
SwiftUI views with no SwiftCrossUI equivalent at all, where ported code fails to
compile rather than rendering differently.

~~None of `Form`, `Section`, `Label(_:systemImage:)`, `Stepper`, `Gauge`,
`DisclosureGroup`, `LabeledContent`, `ColorPicker` or `Link` exists under
`Sources/SwiftCrossUI/Views`.~~

**ALL NINE EXIST. Re-derived 2026-09-09** with the shape-agnostic loop recorded
in `todo.md` under "Re-derived 2026-09-09", which reports 16 of 17 common views
present and controls itself (`VStack` must return 1, `ZZZNotARealType` must
return 0). The only absent name in that survey is `LazyHGrid`.

This is the largest single stale claim found in this tree so far — nine names,
every one of them wrong, in the direction of work already done. Struck through
rather than deleted because what it teaches is not "these nine exist" but how a
list like this rots: it was true when written, nothing re-ran it, and each of the
nine landed separately without anyone opening the document that said it had not.

The reasoning kept, because it is still correct about `Section` and is why
`Section` was worth doing first: in SwiftUI it is less a view in its own right
than the structuring element `List`, `Form`, `Picker` and `Menu` all accept, so
its absence broke call sites that do not look like they are about sections. The
others each cost one call site.

**What this step is now.** Not "record nine gaps" — verify that the nine RENDER
on this backend. Existing and drawing are different claims, and the second is
the one a test plan is for.

Current automated flow:

```zsh
zsh testapp/test.zsh P33 --both
```

The app renders a missing-view list and hand-written approximations for Stepper,
DisclosureGroup and LabeledContent. The intentionally missing SwiftUI call sites
remain documented in text rather than being kept as uncompilable code.

Test steps:

1. Show one instance of each missing view and record which compile. The app
   begins as a file that does not build, and the list of lines that had to be
   commented out is the measurement.
2. For `Section`, test all four containers separately -- `List`, `Form`,
   `Picker`, `Menu`. A `Section` that works in one and not the others is a
   different result from one that works nowhere.
3. Where a view can be approximated by hand -- a `Stepper` as two buttons and a
   label, `LabeledContent` as an `HStack` -- build the approximation beside the
   gap and record how many lines it takes and what it still fails to do:
   keyboard reachability, alignment with neighbouring rows, disabled state.
4. ~~`Label(_:systemImage:)` needs a system image, and `Image(systemName:)` does
   not exist either (see P36). Record whether a text-only fallback is acceptable
   or whether the two gaps have to be closed together.~~
   **BOTH EXIST, checked 2026-09-09:** `Label`'s
   `public init(_ title: String, systemImage: String)` is at
   `Views/Label.swift:143` and `Image(systemName:)` at `Views/Image.swift:62`.
   So this step is no longer "record a gap" — it is "verify the two actually
   draw a symbol on this backend", which is a different job and one that has to
   be RUN rather than looked up.
5. Compare each against the same code under AppKit.

### P34: Lazy Containers and Large Collections (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** Covers what
happens when a collection is larger than the window that shows it.

~~There is no `LazyVStack`, `LazyHStack`, `LazyVGrid`, `LazyHGrid` or `Grid`, and
no `ScrollViewReader` or `ScrollViewProxy`.~~ **Six of those seven now exist.
Re-checked 2026-09-09; the only one still absent is `LazyHGrid` (task #118).**
`LazyVStack`, `LazyHStack`, `LazyVGrid` and `Grid` all landed by 2026-09-08, and
`ScrollViewReader`/`ScrollViewProxy` on 2026-09-09 — driven and verified on
Win-gtk4 by `actions/win/P34-scroll-to-row-50.csv`, whose log reads
`scrollTo row 50 requested, anchor top` and whose capture shows the top visible
row going from `Row 0` to `Row 50`. So the last sentence of the struck-through
text — "nor is there a way to scroll to a particular row programmatically" — is
now false, and it was the paragraph's whole conclusion.

**The struck-through text is kept because of how it stayed wrong.** P34's own
on-screen label carried the same list and the same error, so a reader who
checked the running app against this document found them agreeing. Two copies of
one stale claim do not corroborate each other; they only make the claim harder
to doubt. It was caught by asking the source tree, one name at a time, with a
control (`VStack` found, `ZZZNotARealType` absent, so the search itself works).

What remains true: `VStack` and `HStack` build every
child, and `ScrollView` scrolls whatever it was handed, so a collection inside a
`ScrollView` is fully realised: 10,000 rows means 10,000 widgets, whether or not
any of them is on screen. **`LazyVStack` and `LazyHStack` do not change this** —
they exist, and they are not lazy; the layout matches `VStack`/`HStack` exactly
and every child is still built up front. See task #85, where that was decided
as a documented divergence rather than a bug, and #117 for virtualising `List`,
which is where the platform widgets already recycle.

"Feels slow" is not a finding. The app takes a row count on the command line and
prints numbers, so the result is a table rather than an impression.

Current automated flow:

```zsh
zsh testapp/test.zsh P34 --both
```

The loader currently runs with `--debug -rows 100` for a quick smoke pass. Larger
row counts should be run explicitly when measuring first-paint time and memory.

Test steps:

1. Run with 100, 1,000, 10,000 and 100,000 rows and record the time from launch
   to first paint at each. Four points are enough to see the shape: growth
   proportional to row count is full realisation, flat is laziness that has come
   from somewhere unexpected and should be located.
2. Record peak resident set size on the same runs. Time alone cannot separate
   "builds everything slowly" from "builds everything and keeps it", and the
   memory figure is what distinguishes them.
3. Measure scroll latency at 10,000 rows -- the time from a scroll event to the
   frame that reflects it -- and compare it against 100 rows. Eager building
   costs launch time; it does not necessarily cost scrolling, and conflating the
   two assigns the cost to the wrong cause.
4. Find the row count at which the app fails, and record how it fails: refusing
   to start, an allocation failure, a widget-count limit in X11 or WinUI, or a
   launch time long enough to be unusable. The remedies differ, so the mode
   matters as much as the number.
5. Write `ScrollViewReader { proxy in ... }` and record the compiler error, then
   jump to row 5,000 by whatever means the toolkit does offer and record what
   that costs.
6. Repeat under the other backend. GTK and WinUI have different widget-creation
   costs, so the two curves are expected to differ in slope, not only in offset.

### P35: State and Scene Composition (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** Covers the gaps
that stop a SwiftUI app's structure from being expressed, as distinct from its
appearance.

`@State`, `@Binding`, `@Environment` and `ObservableObject` all exist.
`@StateObject` and `@ObservedObject` do not, so a reference-type model has no
property wrapper to be observed through. Neither does `@SceneStorage`, nor
`Binding.constant(_:)`, and `.environmentObject(_:)` is not offered as an alias
for the environment modifier.

The scene side is more structural. `Scene` declares only `associatedtype Node`
-- there is no `var body: some Scene`, so a scene cannot be composed out of other
scenes the way a view is composed out of views. `SceneBuilder` provides
`buildBlock` only: no `buildIf`, no `buildOptional`, no `buildEither`. An `if`
inside `App.body` therefore does not compile, which rules out the ordinary
SwiftUI pattern of opening a window conditionally. `ViewBuilder` does have
`buildIf` and `buildEither`, but no `buildLimitedAvailability`, so `if #available`
does not work inside a view body either.

Current automated flow:

```zsh
zsh testapp/test.zsh P35 --both
```

The app exercises a simple `@State` counter/toggle and lists the state/scene APIs
that still cannot be represented. Scene composition remains a compile-time gap,
so this test is mainly a tracked baseline.

Test steps:

1. Declare a class conforming to `ObservableObject` with a `@Published`
   property and try to hold it with `@StateObject`, then with `@ObservedObject`.
   Record what compiles and, for anything that does, whether changing the
   published property redraws the view.
2. Write an `App` whose `body` contains `if showSecondWindow { WindowGroup ... }`
   and record the compiler error. The failure is in `SceneBuilder`, not in the
   window type, and the error text should be checked to say so -- an error that
   blames the wrong type sends the next person to the wrong file.
3. Write `if #available(macOS 14, *) { ... }` inside a view body and record that
   error too. It is a different missing requirement from step 2's, in a
   different builder, and the two should not be filed as one issue.
4. Pass `Binding.constant(true)` to a `Toggle` and record the error, then pass
   `Binding(get: { true }, set: { _ in })` and confirm it works. The second is
   the workaround, and its existence is what makes this a convenience gap rather
   than a functional one.
5. Set a value, close the window, reopen it, and record whether the value
   survives. With no `@SceneStorage` nothing restores it; confirm that is what
   actually happens rather than assuming it from the missing API.
6. Repeat under the other backend. These are compile-time gaps, so the results
   should be identical. A difference means something here is conditional on the
   backend, which is worth locating.

### P36: API-Shape Compatibility (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** Covers views that
exist but whose SwiftUI call sites do not compile. Every gap in this section is
invisible on a feature checklist, because the type is present and only the
initialiser is missing.

- `Picker` is `Picker(of: [Value], selection: Binding<Value?>)`. There is no
  label argument, no `@ViewBuilder` content and no `.tag`, and the selection
  must be `Optional`, so a picker over a non-optional `@State` needs a bridging
  binding.
- `Button` is `Button(_ label: String, action:)`. There is no trailing-closure
  label, so `Button { ... } label: { Image(...) }` cannot be written.
  ~~"and there is no `ButtonRole`, so `.destructive` cannot be expressed at
  all"~~ — **false, re-derived 2026-09-09.** `ButtonRole` is at
  `Values/ButtonRole.swift`, `Button` takes `role:`, and `EnvironmentValues`
  carries it.
- `Text` takes a `String`. There is no `LocalizedStringKey`, therefore no
  markdown, and no `Text` + `Text` concatenation. (`.textCase` DOES exist, at
  `Modifiers/Style/TextCaseModifier.swift`, and has been struck from the longer
  list this paragraph used to carry.)
- `Image` takes a `URL` or an `ImageFormats.Image<RGBA>`, ~~and there is no
  `Image(systemName:)`~~ — **false, 2026-09-09: `public init(systemName:)` is at
  `Views/Image.swift:62`.** There is still no bundle asset lookup, so a ported
  app's file-based images need a path.
- `List` requires `selection:` on every initialiser and constrains
  `Data.Index == Int`. ~~There is no `Section`~~ — **false, `Views/Section.swift`
  exists.** There is still no `.onDelete` and no `.swipeActions`.

> **Four claims in this section were false when re-checked on 2026-09-09, all in
> the "already implemented" direction, and `testapp/plan/parity-gaps-survey.md`
> had already recorded three of them correctly with file and line. One document
> in this tree had the right answer while this one had the wrong answer, and
> nothing marked which was older.** Struck through rather than deleted, because
> what a plausible stale claim looks like is the useful part. When correcting a
> claim, grep for it — the copy in front of you is rarely the only one.
- `TextField` has no `axis:`, no `prompt:` and no `value:format:`.
- Geometry is `Int`: `padding(_ amount: Int?)`, `cornerRadius(_ radius: Int)`,
  `HStack(spacing: Int?)`. SwiftUI uses `CGFloat` throughout, so `.padding(8.5)`
  in ported code is a compile error rather than a rounding difference.

Current automated flow:

```zsh
zsh testapp/test.zsh P36 --both
```

The app renders the SwiftCrossUI spelling that works today next to a text list of
SwiftUI-shaped calls that still fail to compile. This keeps the porting-cost
surface visible without breaking normal test builds.

Test steps:

1. Put each SwiftUI declaration above into the app verbatim and record the
   compiler error it produces. The error text is the deliverable; "does not
   compile" is not specific enough for anyone to act on.
2. Beside each, write the SwiftCrossUI form that does compile and gets nearest
   to the same result, and record the line-count difference. That difference is
   the porting cost, and it is the number this section exists to produce.
3. For `Picker`, hold a non-optional selection in `@State` and record what the
   bridging binding has to do when the picker's selection becomes `nil`. With no
   `.tag`, confirm what identity the selection is actually matched on -- the
   `Equatable` conformance of the value itself.
4. For the integer geometry, set a spacing of `8` and one of `9` and measure the
   rendered gap under each backend. If a backend scales by a display factor then
   the integer is not a pixel count and the rounding is happening somewhere
   else; record where, because a test that only checks `8 < 9` would pass either
   way.
5. Record whether `Image(systemName: "gear")` is a compile error or a runtime
   blank. A checklist cannot tell the two apart, and the silent blank is the
   worse of them.
6. Repeat under the other backend. Anything that compiles under one and not the
   other is a backend-conditional API, which is a separate finding from
   everything else in this section.

### P37: Window Level (Linux and Windows)

Run:

```zsh
zsh testapp/run.zsh P37                    # GtkBackend on Windows
./testapp/output/P37-WinUI.exe                   # WinUIBackend on Windows
./testapp/output/P37                       # GtkBackend, in WSL
```

The one Pn that cannot be judged from a picture of its own window. Every other
app is assessed by what its window contains; this one is assessed by what is
*not* covering it. So the test needs a second window, and the interesting
outcome is the boring one, where nothing changed.

The app applies `.topmost()`, which is `.windowLevel(.floating)` under the name
the platform APIs use. Both go through `BackendFeatures.WindowLevels`, and a
backend that cannot honour a level falls back to `.normal` and logs it once
rather than crashing or going quiet.

The two platforms genuinely differ, and a tester who does not know that will
file the Linux result as a defect:

- **Windows** supports it on both backends. WinUIBackend uses
  `OverlappedPresenter.isAlwaysOnTop`; GtkBackend goes through
  `SetWindowPos(HWND_TOPMOST, SWP_NOACTIVATE)` on the `HWND` underneath the GTK
  window. `SWP_NOACTIVATE` matters: this must not steal focus, and taking the
  foreground is a separate thing Windows only allows the process already in
  front.
- **Linux does not.** GTK 4 removed `gtk_window_set_keep_above` and has no
  replacement, so the answer would have to come from the window manager. Under
  Wayland a client cannot raise itself above another application by design. X11
  has `_NET_WM_STATE_ABOVE`, but WSLg's window manager does not advertise it:
  measured 2026-08-26, its root `_NET_SUPPORTED` lists only
  `_NET_WM_MOVERESIZE`, `_NET_WM_STATE`, `_NET_WM_STATE_FULLSCREEN` and the two
  `MAXIMIZED` atoms. Re-check with `xprop -root _NET_SUPPORTED` before treating
  that as still true, and expect a different answer on a desktop Linux, where
  `_NET_WM_STATE_ABOVE` usually is implemented.

Test steps:

1. Launch P37 and read the `supported levels` line it prints in its window.
   On Windows it should list `automatic, normal, floating`; in WSL, only the
   first two. That line is the app telling you which of the next two steps
   applies.
2. Where floating is supported: click another application's window so that
   application takes focus, then look again. P37 must still be visible on top
   of it. Capture the desktop, not the window -- a window capture cannot show
   what is *not* covering it.
3. Where floating is unsupported: P37 goes behind, which is the correct result
   there. Confirm the app said so in step 1 rather than leaving you to guess.
4. Check the log for the fallback line. On a backend without floating,
   SwiftCrossUI should have logged `window level floating is not supported by
   ... using .normal` exactly once, not once per layout pass.
5. Close P37 and confirm nothing else on the desktop has been left pinned above
   its neighbours. A window level that outlives its window would cover whatever
   the user does next.

### P38: WebView (Linux and Windows)

Run:

```zsh
zsh testapp/test.zsh P38 --both
```

Covered issues:

- WinUI WebView async / render delay behaviour.
- GtkBackend WebView coverage and graceful fallback behaviour.

Test steps:

1. Launch P38 on WSLg first, then Windows.
2. Confirm the app window appears and does not hang before the final screenshot.
3. Check whether the WebView area renders usable content, a deliberate fallback,
   or a blank area.
4. Check the log for navigation or async completion messages.
5. On Windows, keep the run open for the default 30 seconds and confirm the app
   remains responsive while the WebView is loading.

Expected results:

- The test should not crash or block the loader.
- If the initial screenshot is blank but the final screenshot is visible, record
  it as startup/render timing, not as a UI failure.
- If Windows never reaches the final screenshot or cannot close cleanly, record
  it as the WinUI async WebView issue.

### P39: Visual Effects (Linux, Windows, macOS and iOS)

Run:

```zsh
zsh testapp/test.zsh P39 --both
```

Covered issues:

- Visual-effect rendering differences across GtkBackend and WinUIBackend.
- Unexpected diagnostic noise or silent no-op effects.

Test steps:

1. Launch P39 on WSLg first, then Windows.
2. Confirm all effect samples are visible in the final screenshot.
3. Use image measurement for color/visibility checks when judging a rendering
   issue; do not rely only on visual inspection.
4. Compare WSLg and Windows captures for obvious missing effects, clipped
   content, or theme-driven contrast problems.

Expected results:

- The app should render visible samples on both platforms.
- Backend-specific theme differences are acceptable.
- On GTK, blur and colour effects should visibly differ from the control.
- ~~On WinUI, opacity should differ from the control; blur, grayscale,
  saturation, brightness, contrast and hue rotation are currently expected
  no-ops and should remain documented until implemented.~~
  **Superseded 2026-09-02** (kept, not deleted, so the shape of the stale claim
  stays on record): on WinUI, all seven should visibly differ from the control,
  same as GTK. Verified 2026-09-02 with `applied=8 failed=0 total=8`
  (`cd testapp/output && SCUI_DEBUG_VISUAL_EFFECTS=1 ./P39-WinUI.exe`, then read
  `winui-visual-effects-debug.log`), and at pixel level from a wincap
  screenshot: mean HSV saturation per cell reads 0.000 / 0.515 / 0.818 /
  0.992 for saturation 0, 0.5, control (=1) and 2.5 — a monotonic ladder.
- **On macOS/AppKit, all nine cells should differ from the control**, measured
  2026-09-02. `AppKitBackend+VisualEffects.swift` is one `CIFilter` chain on a
  layer-backed container, with opacity on `alphaValue` so the subtree composites
  as a group. If every cell including the identity control comes back blank,
  suspect `layerUsesCoreImageFilters` being set when there is no filter to run —
  that is what it looks like.
- **On iOS/UIKit, all nine cells should differ from the control**, measured on
  the iPhone 16 simulator 2026-09-02. Read the mechanism before judging a
  failure here: `CALayer.filters` does **not** composite on iOS — that was
  measured twice and is still true, `opacity 0.35` faded while `blur 3`,
  `saturation 2.5`, `brightness 0.4`, `grayscale 1` and `hueRotation 120` came
  back pixel-identical to the control. The effects work anyway because they are
  no longer done that way: they run over a `CALayer.render(in:)` bitmap through
  Core Image, with the result laid over the child and the child masked out by an
  empty `CALayer` mask so it stays hit-testable. The consequence to expect is
  that a filtered cell is a rendering refreshed on layout, not the live subtree,
  so a Core Animation-driven animation inside one would appear frozen; `opacity`
  does not take that path.

### P40: Geometric Effects (Linux, Windows, macOS and iOS)

Run:

```zsh
zsh testapp/test.zsh P40 --both
```

Covered issues:

- Geometric effect rendering.
- Hotpink fallback / incorrect geometry detection.

Test steps:

1. Launch P40 on WSLg first, then Windows.
2. Confirm transformed shapes are visible in the final screenshot.
3. Measure the final screenshot with PIL before claiming the hotpink fallback is
   absent or fixed.
4. Measure color-component bounding boxes for the orange/blue test tiles. A
   pass requires scale, offset, rotation and shear samples to differ from the
   control in the expected direction; zero hotpink alone is not sufficient.
5. Record the screenshot dimensions, non-black pixel ratio, and exact/near
   hotpink pixel count.
6. Record the platform theme/background separately. WSLg may default to light
   Adwaita while WinUI follows the Windows theme; this is not geometry failure.

Expected results:

- The app should produce a visible non-black capture on both platforms.
- Exact hotpink pixels should be zero unless the app intentionally displays the
  fallback color for a test case.
- The transformed samples should not all have the same bounding box as the
  control tile.
- **On macOS/AppKit and iOS/UIKit, all seven cells should render correctly**,
  measured 2026-09-02 — on the Mac and on the iPhone 16 simulator. The check
  that matters most is not "something moved": compare `rotate 30 centre` against
  `rotate 30 topLeading`, which must **differ**. Wrong anchor arithmetic makes
  those two identical, or throws the tile off screen, and either failure looks
  like the transform working. A blank cell means the container's child was not
  pinned on all four edges — the modifier's commit sizes the container and
  nothing sizes what is inside it.

### P41: Date Picker Styles (Linux and Windows)

Run:

```zsh
zsh testapp/test.zsh P41 --both
```

Covered issues:

- WinUI `.graphical` DatePicker blank sliver / binding behaviour.
- Cross-backend DatePicker style fallback behaviour.

Test steps:

1. Launch P41 on WSLg first, then Windows.
2. Confirm every DatePicker section occupies visible space.
3. On Windows, inspect `.graphical` specifically and confirm it is not rendered
   as a blank sliver.
4. Change the date where possible and confirm the displayed binding value
   updates.
5. Record style-specific fallback messages from the log.

Expected results:

- The final screenshot should show visible DatePicker content on both
  platforms.
- If `.graphical` is blank or updates the wrong binding value on Windows, record
  it as the WinUI DatePicker issue.

### Test Record Template

Use this format after each test run:

```text
Date:
Commit:
OS:
Swift:
App:
Result: Pass / Fail
Steps:
Observed:
Expected:
Logs:
Screenshots:
Notes:
```

---

## Bug plan: AppKit, UIKit and AndroidBackend

Covers the open upstream bugs reachable from the macOS workstation. The
selection comes from `issues.csv`: 33 rows are tagged `bug` and are not yet
fixed, and these are the ten whose backend is reachable there. Gtk, Gtk3 and
WinUI bugs belong to the Windows workstation instead.

`#platform-matrix` is the cross-platform view of the same data, and is the
place to look for which app covers which issue on which platform.

The count is checkable rather than remembered:

```sh
awk -F, 'NR>1 && $2 ~ /bug/ && $4 !~ /^fixed-p/' testapp/issues.csv | wc -l
```

Same working style as the WinUI and Linux plans: reproduce first, measure
rather than infer, and record what was actually observed.

### Scope

| App | Backend | Issues | Where it runs |
| --- | --- | --- | --- |
| P11 | AppKitBackend | #82, #485, #473 | macOS, natively |
| P12 | AndroidBackend | #632, #580, #544 | Android device or emulator |
| P13 | core layout / view graph | #595, #291, #158 | any backend |
| P13 | AppKitBackend | #415 | macOS, natively |
| P14 | UIKitBackend | #324, #254 | iOS Simulator |

P13 is split across two rows on purpose. `issues.csv` files #595, #291 and #158
under `core/unspecified`, not under a backend, so they are testable wherever the
app runs; only #415 is reported against AppKitBackend. Measured, not assumed:
P13 builds and links under GtkBackend in WSL, so those three can be checked
without waiting for a Mac, and a backend that does *not* show them is a useful
result too.

Bugs from the same set that are deliberately excluded appear under "Not
covered" in each section, with the reason.

#### Not reachable from the macOS workstation

Recorded so the gaps are visible rather than forgotten. "Blocked" here means
blocked *from macOS* -- the first two rows are routine work on the Windows
workstation, and #289 and #160 already have repro apps there:

| Issues | Where it belongs instead |
| --- | --- |
| #289, #594 | The Windows workstation, under WSLg. #289 is covered by P15 |
| #160, #231 | The Windows workstation. #160 is covered by P16 |
| #286, #166, #179 | Gtk3Backend, which is out of scope everywhere |
| #189 | GtkBackend *on macOS*, which neither workstation runs -- the Gtk3 half is out of scope as well |
| #227 | A Mac Catalyst build target, not yet set up |
| #226 | tvOS |
| #645 | Comparison against several platforms at once, so it needs the others first |

---

### P11: Sliders, Scrollbars And Pickers (macOS)

Build and run:

```sh
zsh testapp/compile.zsh P11
./testapp/output/P11
```

Covered issues:

- #82 (Open): Sliders jitter in RandomNumberGeneratorExample when two sliders
  constrain each other
- #485 (Open): Scrollbar renders pointing the wrong way
- #473 (Open): Compact DatePicker sizing is off with Liquid Glass

Test steps:

1. Launch `P11`.
2. Click `Separate them`, so minimum is 20 and maximum is 80 and neither clamp
   is active. Click `Reset counters`.
3. Drag the **minimum** slider slowly upward past 80. Watch the two write
   counters, to verify #82.
4. Release and read the counters. One drag should advance `min` roughly in step
   with the pointer, and should not advance `max` at all while the sliders are
   apart.
5. Click `Collide them`, then `Reset counters`, then drag the minimum slider
   further right. Both values are now pinned together, so this is where the
   clamp feeds back.
6. Watch the slider handle while dragging: it must stay where the pointer put
   it rather than snapping back and forth.
7. Scroll the row list with the scroll wheel and watch the vertical scrollbar,
   to verify #485. Note which end of the track the thumb sits at when the list
   is at row 1.
8. Scroll to the bottom and note where the thumb sits now.
9. Compare the compact `DatePicker` against the `Reference` button beside it,
   to verify #473. Check the heights match and that neither the date text nor
   the stepper is clipped.
10. Click into the DatePicker and change the date; confirm the control does not
    resize as its contents change.

Expected results:

- Dragging one slider does not write to the other while they are apart. Both
  counters climbing together, or a handle that jumps back after release, is #82.
- The scrollbar thumb is at the **top** when the list is at row 1, and at the
  bottom when scrolled to the end. Reversed is #485.
- The DatePicker matches the reference button's height and clips nothing. Being
  visibly taller, shorter or clipped is #473.

Not covered by P11:

- **#404** (window content size after `View > Show Tab Bar`) needs a system menu
  item that the app cannot drive from its own view tree. Reproducing it means
  toggling the menu by hand and watching whether the content area follows;
  worth doing manually, but not something P11 can assert.
- **#425** (window not focused at launch) is described upstream as intermittent
  -- "every once in a while". A pass/fail step would report success almost every
  time regardless of whether the bug is fixed. If it appears, record the launch
  method, whether Swift Bundler was used, and whether the sidebar had
  transparency.

---

### P12: Button Margins, State And Toggles (Android)

Build and run:

```sh
cd Examples
SCUI_ANDROID=1 swift build --swift-sdk aarch64-unknown-linux-android28 --product P12
```

Or bundle and install it as an APK, following
`Scripts/build-tool-install-android-on-Mac.sh`. P12 also renders on the host
platform, which is useful for checking the layout before deploying, but only
the Android run can verify these issues.

Covered issues:

- #632 (Open): Buttons have an unnecessary margin
- #580 (Open): Rotating the screen resets `@State`
- #544 (Open): Toggle button state is not indicated visually

Test steps:

1. Launch `P12` on a device or emulator with auto-rotate enabled.
2. In the margins section, look at the two blue buttons between the green
   bands, to verify #632. The blue background should reach each button's edges.
3. Measure or eyeball the gap between the blue and the green above and below.
   Any consistent strip of background colour between them is the margin.
4. Tap `Second` or `Third` so the selected tab is not the default, then tap
   `Increment counter` a few times. Note both values.
5. Rotate the device to landscape without touching anything else, to verify
   #580.
6. Read the tab and counter again. Both must be unchanged.
7. Rotate back to portrait and read them once more.
8. In the toggle section, compare the `Forced on` and `Forced off` toggles side
   by side, to verify #544.
9. Tap `Set both on`; confirm the two now look identical to each other.
10. Tap `Set opposite`; confirm they now look different from each other.
11. Compare against the `switch` style toggle below, which uses a different
    component, to see whether the problem is specific to the button style.

Expected results:

- The blue background reaches the button edges. A gap between blue and green is
  #632.
- Tab selection and counter survive rotation unchanged. Reverting to the first
  tab, or the counter returning to 0, is #580.
- The two button-style toggles look different when in opposite states. Looking
  identical is #544.

Not covered by P12:

- **#610** (sheet sizing on Android) is two coupled defects upstream: the layout
  system not respecting the size backends report for sheets, and AndroidBackend
  reporting the wrong size in the first place. Distinguishing them needs
  measured sizes from both layers rather than a visual check, so it needs its
  own instrumented app rather than a step here.

---

### P13: Layout And View Graph (any backend, plus one macOS-only check)

Build and run:

```sh
zsh testapp/compile.zsh P13
./testapp/output/P13          # .exe on Windows
```

Covered issues, by where they have to be checked:

Any backend:

- #595 (Open): Texts inside a ScrollView get unnecessarily cut off
- #291 (Open): NavigationSplitView minimum width sizing
- #158 (Open): Group behaviour in ZStacks

macOS only:

- #415 (Open): Message list benchmark crashes with AppKitBackend

#415 crashes on purpose, so it is behind a button. Do the other three checks
first, then trigger it last. Steps 1-8 are worth running on every backend
available, recording each separately: #291 in particular is reported upstream as
affecting AppKitBackend and not GtkBackend, so agreement between the two is
itself the finding.

Test steps:

1. Launch `P13`. Confirm the window opens and the identifiable list on the left
   renders three identical rows.
2. Compare the two ScrollViews. The left one is plain, the right one applies
   `.fixedSize(horizontal: false, vertical: true)`, which upstream reports as
   the workaround, to verify #595.
3. Confirm the plain ScrollView shows the whole wrapped sentence. If its last
   line is clipped while the `.fixedSize()` one is not, that is #595.
4. Look at the ZStack section, to verify #158. The red, green and blue blocks
   are inside a `Group` inside a `ZStack`, at decreasing sizes.
5. Confirm they overlap, smallest on top, so all three are visible as nested
   rectangles. Laid out side by side or stacked vertically means the Group took
   the container's orientation instead of the z axis, which is #158.
6. Click `Narrower` repeatedly and watch the NavigationSplitView, to verify
   #291. The frame shrinks in 60 px steps.
7. Confirm the detail pane stays visible as the frame narrows. If the split
   stops moving and the detail pane is squeezed out or clipped while the
   sidebar keeps its width, that is #291.
8. Click `Wider` and confirm the split recovers.
9. On macOS: `More duplicates` a few times, then click `Show unidentified list`,
   to verify #415. This renders a `ForEach` over elements that are not
   `Identifiable` and all compare equal.
10. Record whether the app crashes, and if so capture the message. Upstream
    attributes it to the backend receiving duplicate child views. On other
    backends this step is not expected to crash; run it anyway and record that,
    since it bounds the bug to AppKitBackend.

Expected results:

- The plain ScrollView does not clip its text. Needing `.fixedSize()` is #595.
- The Group's children overlap along z. Any side-by-side or vertical layout is
  #158.
- The detail pane survives narrowing. Being squeezed out is #291.
- Rendering the non-Identifiable list does not crash. A crash is #415, and the
  identifiable list beside it is the control showing the same data is fine when
  identity is explicit.

### macOS feature coverage without an upstream issue

The following apps cover AppKit features that are not assigned an open issue:

| App | Feature | macOS check |
| --- | --- | --- |
| P25 | Drag and drop | Drag a file onto the accepting area; verify hover feedback and the received file URL payload. |
| P28 | Hit testing | Click the blue overlay; the click must pass through and increment the button below. |
| P29 | Visual fidelity | Compare the indeterminate progress bar, clipping and disabled editor behaviour against the stated controls. |
| P37 | Window levels | Place another window over the app and verify the selected window-level behaviour. |

For P28, the measurable result is the `Clicks received` counter and the
`underlying button clicked` entries in `p28-debug-events.log`. A visible overlay
that consumes the click is an AppKit regression even if the overlay itself is
drawn correctly.

---

### P14: Rotation Size Proposals And Theme (iOS Simulator)

Build, install and run:

```sh
zsh testapp/compile.zsh -ios P14
xcrun simctl boot swift-cross-ui
open -a Simulator
xcrun simctl install swift-cross-ui testapp/output/P14-ios.app
xcrun simctl launch swift-cross-ui dev.swiftcrossui.testapp.P14
```

`compile.zsh -ios` provisions the simulator itself via `install_tools_ios.zsh`, so
a missing device is created rather than reported.

Covered issues:

- #324 (Open): Content gets an incorrect size proposal on orientation change
- #254 (Open): App background colour is not updated when the system theme changes

Both are about a value rather than an appearance, so P14 records what it was
given instead of asking you to catch a flicker. #324 corrects itself on the next
layout pass, and #254 is one surface disagreeing with others.

Test steps:

1. Launch `P14` in portrait. Note the reported proposed width; it should match
   the device's portrait width.
2. Click `Clear history`.
3. Rotate the simulator to landscape (Cmd-Left Arrow), to verify #324.
4. Read `Width history`. It records up to eight width changes in order.
5. Confirm the history goes straight from the portrait width to the landscape
   width. An intermediate entry **wider than the landscape width**, followed by
   the correct one, is #324 -- the app was proposed more space than exists and
   then corrected.
6. Rotate back to portrait and read the history again.
7. With the app open, switch the system appearance, to verify #254. In the
   simulator use Features > Toggle Appearance, or from a terminal:
   `xcrun simctl ui swift-cross-ui appearance dark`.
8. Compare the three numbered surfaces. The text, the button and the adaptive
   colour block should all change together with the window background behind
   them.
9. Switch back to light and compare again.

Expected results:

- Width history contains only the portrait and landscape widths, in order. An
  extra oversized entry between them is #324.
- Every surface follows the theme. If the controls and the adaptive block
  change while the background behind them stays the previous theme's colour,
  that is #254. The adaptive block is the control here: it proves the theme
  change arrived, so a background that ignores it is the app's own bug.

Not covered by P14:

- **#227** (Mac Catalyst button sizing) shares UIKitBackend but needs a Catalyst
  destination rather than an iOS Simulator one, and upstream supplies only a
  screenshot with no description, so the reproduction conditions are unclear.

---

### Test Record Template

```text
Date:
Commit:
OS / device:
Swift:
App:
Result: Pass / Fail
Steps:
Observed:
Expected:
Logs:
Screenshots:
Notes:
```

---

## Linux plan: GtkBackend through WSL

Goal: reproduce the open GtkBackend/Gtk3Backend issues on this machine, fix what
we can, and submit the fixes upstream. Same working style as the WinUI work:
reproduce first, measure rather than infer, and keep the evidence.

For which app covers which issue, and whether a WSLg run settles it or only
shows the symptom, see `#platform-matrix`. The Tier 1 and Tier 2 split
below is where that distinction comes from -- but note that Tier 2 is not a
synonym for "WSLg distorts it": read the caveat column, since only #556 is
about window sizing itself.

### Environment as it stands

Checked, not assumed:

| | |
|---|---|
| WSL | Ubuntu 26.04 LTS, WSL2, running |
| WSLg | available -- `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0`, so GTK windows display natively |
| Swift | **6.3.3**, installed from the official tarball into `/usr/local/swift` |
| GTK 4 | **4.22.4** (`libgtk-4-dev`, installed) |
| GTK 3 | not installed, and deliberately so |

WSLg presents a Wayland compositor. Anything about window sizing, minimum
sizes or resizing behaves differently there than on a real desktop session, so
those issues need a caveat (see Tier 2).

### Phase 0 -- toolchain

Done. `testapp/install_tool_wsl.sh` does all of it and is the record of what was
needed; run it as root, since `sudo` in this distribution asks for a password:

```sh
wsl -d Ubuntu -u root -- bash testapp/install_tool_wsl.sh
```

What it resolved, none of it guessed:

1. swift.org publishes **no** Ubuntu 26.04 build -- the 26.04 tarball URL 404s
   while the 24.04 one returns 200 -- so the 24.04 build is installed, from the
   official tarball into `/usr/local/swift`. Not Swiftly.
2. That build then fails to start on 26.04, twice over: 26.04 ships
   `libxml2.so.16` where Swift wants `.so.2`, and ICU 78 where it wants ICU 74.
   Both are extracted from the 24.04 `.deb` packages into
   `/usr/local/lib/swift-compat`.
3. GTK 4 is installed: `libgtk-4-dev` 4.22.4, with pkg-config 2.5.1.
4. Verify: `pkg-config --modversion gtk4` and `swift --version`.

**Scope: GtkBackend only.** Gtk3Backend is out of scope, so GTK 3 is not
installed and issues that only affect it are not being pursued. That drops #286
and #166 outright, and means #426 is only tested against GTK 4.

GTK 4.22.4 is recent, which decides #702 (about *older* GTK 4) before it starts:
it cannot be reproduced here.

### Phase 1 -- prove the toolchain end to end

Build and run one of the repo's own examples under WSLg before touching any
issue. If a window does not appear, that is an environment problem, not a bug in
the code being tested, and every later result would be suspect.

```sh
./Scripts/test.sh                    # unit tests
swift build --target GtkBackend      # not --product
```

`--target GtkBackend` is not a preference. A plain `swift build`, or
`--product SwiftCrossUI`, makes SwiftPM build the default target set, which
includes the `WinUIInterop` C target, and that fails on Linux with
`'Windows.h' file not found`. Naming the target directly is the way past it.

Measured on this machine: 61.7 s from clean for `--target GtkBackend`, and
`testapp/compile.zsh` builds a repro app in 5-15 s once that is warm.

### Phase 2 -- free coverage from the existing test apps

Every app in `testapp` uses `DefaultBackend`, which selects GtkBackend on Linux,
and `testapp/compile.zsh` already handles non-`.exe` output. P0-P3 and P5 should
build and run unchanged; P4 and P6 contain Windows-specific sections behind
`#if os(Windows)`.

This matters because **P2 and P3 already have test steps for two of the open
issues**, written when the WinUI versions were fixed:

- P2 step 7-8 covers #390, disabled buttons not appearing disabled
- P3 step 6-9 covers #389, images not being clipped

So the first real test run costs nothing to write. Run P0-P3 and P5, and record
which of the WinUI-fixed behaviours are still broken on GTK. Extend
`UI-test-plan-zhTW.md#整體計畫p0-p41` / `#overall-plan-p0-p41` with a Linux column or section rather
than starting a separate document.

Since this plan was written, P7-P10 have been added for the Tier 1 and Tier 2
issues below, and P13 for three core-layout issues that are not GTK-specific but
are reachable from here. All of them build and link under GtkBackend in WSL, so
the only thing left for them is a human at the screen.

### Phase 3 -- triage of the open issues

Twelve open issues match Linux/GTK, as of this plan. Two of them (#286, #166)
are Gtk3Backend-only and are dropped with it, leaving ten. Tier 2 has since
picked up three more from `issues.csv` that are filed as `core/unspecified`
rather than against GtkBackend: they are not GTK bugs, but they are reachable
from here, and checking a core layout bug on a second backend is worth more
than checking it on one.

**Tier 1 -- plain widget behaviour, should reproduce under WSLg**

| # | Title | App | Notes |
|---|---|---|---|
| 389 | Images aren't clipped | P3 | already exercised; WinUI half fixed, GTK half open |
| 390 | Disabled buttons don't appear disabled | P2 | already exercised; WinUI half fixed, GTK half open |
| 417 | ScrollView cornerRadius doesn't affect children | P8 | |
| 426 | Horizontal ScrollView swallows parent's scroll wheel | P8 | nested-scroll case |
| 454 | Transparent containers consume click events | P10 | also affects AppKitBackend |
| 476 | List starts with the first item selected | P7 | Fixed on GTK4 and Gtk3 under WSLg |
| 478 | Ctrl-Q does not quit | P10 | keyboard handling, WSLg passes keys through |
| 504 | TextField/SecureField shrinks in height after first update | P9 | |

**Tier 2 -- layout and window sizing, WSLg may distort the result**

| # | Title | App | Caveat |
|---|---|---|---|
| 556 | List NavigationSplitView makes weird size decisions | P7 | |
| 295 | Clip text when necessary to reach zero width | P9 | Gtk3Backend half is out of scope |
| 595 | Text inside a ScrollView is cut off | P13 | not GTK-specific; compare against other backends |
| 291 | NavigationSplitView minimum width sizing | P13 | reported as AppKit-affected and Gtk-unaffected |
| 158 | Group behaviour in ZStacks | P13 | not GTK-specific |

Reproduce these, but before claiming a fix, confirm the behaviour on a real
Linux desktop session or at least state that it was only checked under WSLg.

**Tier 3 -- needs something we do not have, or is not a bug**

| # | Title | Why |
|---|---|---|
| 702 | Older GTK 4 breaks button label centering | 26.04 ships 4.22.4; needs an older GTK |
| 386 | Support dark mode | feature; needs a dark theme configured |
| 594 | EventControllerKey.keyPressed cannot return Bool | binding generation, testable without a GUI |
| 52 | libadwaita support | feature request |

Start with Tier 1, cheapest first: #389 and #390 need no new test code.

### Phase 4 -- per issue

1. Reproduce, and capture what was observed (screenshot or a described symptom).
   If it does not reproduce, say so on the issue -- that is a useful result too,
   especially for the ones that predate current GTK versions.
2. Add or extend a `testapp` app that isolates it, following the existing P0-P6
   convention, and add steps to both test plan documents.
3. Fix in `Sources/GtkBackend`, keeping the change as small as the bug. Where
   an issue names both backends, fix GtkBackend and say in the pull request
   that Gtk3Backend was not tested.
4. Verify against the test app, and check the neighbouring behaviour did not
   regress.
5. One commit per issue, in the style already used here (`GtkBackend: ...`).

### Before submitting anything upstream

- `Scripts/format.sh` (SwiftFormat is installed on the Windows side; install it
  in WSL too, or format from Windows).
- The project's LLM policy applies: usage must be disclosed in the pull request
  description, the author must understand the code, and **the description must
  be written by the author, not by an LLM**.
- Prefer one issue per pull request. The contributing guide asks for focused
  changes, and the smaller ones here are exactly that.

### Risks

- **Ubuntu 26.04 has no matching Swift build**, so the toolchain here is the
  24.04 one running against 26.04's libraries, with `libxml2` and ICU shimmed in
  from 24.04 packages. It builds and links, but it is not a combination
  swift.org tests. A failure that looks like a Swift or Foundation bug should be
  suspected of being this before it is reported.
- **WSLg is Wayland**, so window-level behaviour is not identical to a normal
  desktop. Tier 2 results need that caveat.
- **GTK version skew**: 4.22.4 is recent, so bugs about older GTK cannot be
  reproduced here, and fixes verified against it cannot be assumed to help users
  on older distributions.
- Several of these issues are old. Some may already be fixed; confirming that
  and closing them is a legitimate outcome.

---

## Platform matrix

Which repro app tests which issue, and what running it on each platform tells
you. The per-app steps live in `#overall-plan-p0-p41`; the strategy behind the
Linux work lives in `#linux-plan-gtkbackend-through-wsl`. This file answers one question only:
*where do I run this, and does the answer count?*

Derived from `issues.csv`, which is the source of truth. To regenerate the
issue-to-app mapping:

```sh
awk -F, 'NR>1 && $4 ~ /p[0-9]+$|p[0-9]+;/ {print $4"  #"$1"  "$3}' testapp/issues.csv
```

### Legend

| | Meaning |
| --- | --- |
| 🎯 | Reported against this platform. A run here decides the issue. |
| 🔍 | Not reported here, but a run is a useful comparison -- agreement or disagreement is itself the finding. |
| ⬜ | Nothing to learn. The app builds and runs, but this platform cannot show this issue. |
| ✅ | Already fixed on this platform. Run it as a regression check. |
| 🚫 | No hardware, simulator or toolchain for it. Which machine that applies to is in the table below, not here. |
| 〰️ | Runs under WSLg, but the result does not settle the issue: it is one of the window-sizing cases WSLg distorts. Reproduce here, confirm on 🐧. |

Desktop columns: 🪟 Windows (WinUIBackend) · 🌊 WSLg (GtkBackend under a
Wayland compositor) · 🐧 Linux (GtkBackend on a real desktop session) ·
🍎 macOS (AppKitBackend). Mobile: 📱 iOS (UIKitBackend) · 🤖 Android
(AndroidBackend).

WSLg and Linux are separate columns because they disagree. WSLg is a Wayland
compositor rather than a desktop session, so window sizing, minimum sizes and
decorations behave differently -- the split that `#linux-plan-gtkbackend-through-wsl` already
records as Tier 1 versus Tier 2. The two rows that are 〰️ under 🌊 but 🎯
under 🐧 are the whole reason for keeping them apart: WSLg can show you the
symptom, but only a desktop session settles it. 〰️ never appears under 🐧 --
it says something about WSLg specifically, not about GtkBackend.

Only #556 and #289 carry it. Tier 2 is not a synonym for "WSLg cannot be
trusted": it collects issues that need *some* caveat, and the reasons differ.
#595 and #158 are flagged as not GTK-specific, #291 is reported as Gtk
**un**affected, and #295's caveat is that the Gtk3Backend half is out of scope.
None of those say anything about WSLg's fidelity, so marking them 〰️ would
claim the compositor distorts results it has no bearing on.

### Where each platform is reachable

This repository is worked on from two machines, so "here" depends on which
checkout you are reading. Stated per machine rather than per file:

| Platform | Windows workstation | macOS workstation |
| --- | --- | --- |
| 🪟 Windows | ✅ native | 🚫 |
| 🌊 WSLg | ✅ WSL2 + WSLg, GTK 4.22.4, Swift 6.3.3 | 🚫 |
| 🐧 Linux | 🚫 no desktop session | 🚫 |
| 🍎 macOS | 🚫 | ✅ native |
| 📱 iOS | 🚫 | ✅ Simulator, iOS 18.4 |
| 🤖 Android | 🚫 | ✅ SDK + NDK, device or emulator |

Neither machine has a real Linux desktop session, so the 🐧 column is currently
unreachable from both. It exists because several results measured under 🌊 are
explicitly provisional until someone repeats them there.

### Binaries

The current testapp set reaches P41. The desktop issue matrix below still
decides the upstream issue rows it lists, but it is no longer a complete
inventory of every local repro app. P18-P41 are covered by the overall and bug
plans where applicable.

On the Windows workstation, build the reachable desktop apps as release builds
by default: `testapp/output/PN` under 🌊 WSLg and `testapp/output/PN.exe` on
🪟 Windows. Nothing here has been built under 🐧, which is why that column
carries no results. Rebuild the matrix-era desktop set with:

```sh
zsh testapp/compile.zsh P0 P1 P2 P3 P4 P5 P6 P7 P8 P9 P10 P11 P12 P13 P14 P15 P16 P17
```

For newer local apps, build the specific app named by the test plan instead of
assuming this matrix has already classified it.

### The matrix

#### Open issues and fixed regression coverage -- desktop

| Issue | App | 🪟 | 🌊 | 🐧 | 🍎 | What it is |
| --- | --- | :-: | :-: | :-: | :-: | --- |
| #389 | P3 | ✅ | 🎯 | 🎯 | ⬜ | Images aren't clipped -- WinUI half fixed, GTK half open |
| #390 | P2 | ✅ | 🎯 | 🎯 | ⬜ | Disabled buttons don't look disabled -- same split |
| #476 (Fixed) | P7 | ⬜ | ✅ | ✅ | ⬜ | List starts with the first item selected -- verified fixed on GTK4 and Gtk3 |
| #556 | P7 | ⬜ | 〰️ | 🎯 | ⬜ | NavigationSplitView makes weird size decisions |
| #417 | P8 | ⬜ | 🎯 | 🎯 | ⬜ | ScrollView cornerRadius does not clip children |
| #426 | P8 | ⬜ | 🎯 | 🎯 | ⬜ | Horizontal ScrollView swallows the parent's scroll wheel |
| #504 | P9 | ⬜ | 🎯 | 🎯 | ⬜ | TextField/SecureField shrinks after the first update |
| #295 | P9 | ⬜ | 🎯 | 🎯 | ⬜ | Text not clipped to zero width |
| #478 | P10 | ⬜ | 🎯 | 🎯 | ⬜ | Ctrl-Q does not quit |
| #454 | P10 | ⬜ | 🎯 | 🎯 | 🎯 | Transparent containers eat clicks -- both backends |
| #386 | P15 | 🔍 | 🎯 | 🎯 | ⬜ | Dark mode unsupported |
| #289 | P15 | ⬜ | 〰️ | 🎯 | ⬜ | Window minimum height with Gtk-drawn title bars |
| #160 (Fixed) | P16 | ✅ | 🔍 | 🔍 | ⬜ | Split view laid out wrong on first render; WinUI initial layout fixed, interaction retest still useful |
| #595 | P13 | 🎯 | 🎯 | 🎯 | 🎯 | Text cut off inside a ScrollView (core) |
| #158 | P13 | 🎯 | 🎯 | 🎯 | 🎯 | Group inside ZStack lays out along the wrong axis (core) |
| #291 | P13 | 🔍 | 🔍 | 🔍 | 🎯 | NavigationSplitView minimum width -- AppKit yes, Gtk no |
| #415 | P13 | 🔍 | 🔍 | 🔍 | 🎯 | Non-Identifiable ForEach crashes on AppKit |
| #264 | P17 | 🎯 | 🎯 | 🎯 | 🎯 | frame(idealWidth:) never reaches fixedSize (core) |
| #266 | P17 | 🎯 | 🎯 | 🎯 | 🎯 | Two layout edge cases (core) |
| #161 | P17 | 🎯 | 🎯 | 🎯 | 🎯 | Picker sized from selection or largest -- needs 2+ platforms |
| #82 | P11 | ⬜ | ⬜ | ⬜ | 🎯 | Mutually clamped sliders jitter |
| #485 | P11 | ⬜ | ⬜ | ⬜ | 🎯 | Scrollbar points the wrong way |
| #473 | P11 | ⬜ | ⬜ | ⬜ | 🎯 | Compact DatePicker sizing |

#### Open issues -- mobile

| Issue | App | 📱 | 🤖 | What it is |
| --- | --- | :-: | :-: | --- |
| #595 | P13 | 🎯 | 🎯 | Text cut off inside a ScrollView (core) |
| #158 | P13 | 🎯 | 🎯 | Group inside ZStack lays out along the wrong axis (core) |
| #264 | P17 | 🎯 | 🎯 | frame(idealWidth:) never reaches fixedSize (core) |
| #266 | P17 | 🎯 | 🎯 | Two layout edge cases (core) |
| #161 | P17 | 🎯 | 🎯 | Picker sized from selection or largest -- needs 2+ platforms |
| #324 | P14 | 🎯 | ⬜ | Wrong size proposal on orientation change |
| #254 | P14 | 🎯 | ⬜ | App background does not follow the system theme |
| #632 | P12 | ⬜ | 🎯 | Buttons have an unnecessary margin |
| #580 | P12 | ⬜ | 🎯 | Rotation resets @State |
| #544 | P12 | ⬜ | 🎯 | Toggle state not shown visually |

### Android action-file follow-up TODO

The Android runner, APK delivery, emulator launch, and CSV action replay are
verified with P12 on the API 36 emulator. TODO: investigate why a P12 button
state update can leave the rendered surface blank, then add a screenshot or
state assertion to the Android action test before treating #632, #580, or #544
as a completed Android result.

Core-layout issues appear in both tables: they are backend-independent, so a
run anywhere counts, and disagreement between two platforms is the finding.

#### Fixed, kept as regression checks

| Issues | App | 🪟 | What it is |
| --- | --- | :-: | --- |
| #493 #548 | P0 | ✅ | Launch-time crashes |
| #523 #659 #660 | P1 | ✅ | Dialogs and sheets |
| #204 #401 #449 #471 | P2 | ✅ | Controls and styling |
| #156 #190 #470 | P4 | ✅ | Bindings and callback storage |

P5 and P6 carry no upstream issue numbers: P5 is multi-window alerts, P6 is the
Windows GPU video path that the NV12 work came out of.

P25 covers cross-platform drag-and-drop, P28 covers AppKit hit-testing
pass-through, P29 covers visual fidelity, and P37 covers window levels. These
feature apps are included in the macOS source matrix even though they are not
upstream issue rows.

### What to run, by machine

As of 2026-08-29, the gaps below are the ones this matrix still treats as not
settled on the Windows workstation:

- 🪟 Windows: P16 for #160; P13 for #595/#158 plus #291/#415 comparisons; P17
  for #264/#266/#161; P15 as the #386 control.
- 🌊 WSLg: P7 for #556 remains provisional because WSLg distorts window sizing;
  P15 for #289 is also provisional for the same reason. P2, P3, P8, P9, P10,
  P13, P15 and P17 remain the active WSLg matrix runs unless their per-app
  result file says otherwise.
- 🐧 real Linux desktop: not reachable on either current machine. It is still
  required to settle #556 and #289.
- P18-P41: not fully represented in this platform matrix. Use
  `#overall-plan-p0-p41`, `#bug-plan-appkit-uikit-and-androidbackend` and the per-feature
  result docs for those apps.

🌊 **WSLg**, on the Windows workstation -- 17 issues, plus #291 and #415 as
comparisons. #476 has been verified fixed on GTK4 and Gtk3. Results for the
〰️ rows stay provisional until 🐧 exists:

```sh
./testapp/output/P2                            # 390
./testapp/output/P3                            # 389
./testapp/output/P7                            # 476 556
./testapp/output/P8                            # 417 426
./testapp/output/P9                            # 504 295
./testapp/output/P10                           # 478 454
./testapp/output/P13                           # 595 158, and 291 415 as comparisons
GTK_THEME=Adwaita:dark ./testapp/output/P15    # 386 289
./testapp/output/P17                           # 264 266 161
```

🪟 **Windows** -- 6 issues, plus #291 and #415 as comparisons:

```sh
./testapp/output/P16-WinUI.exe                 # 160, WinUIBackend
./testapp/output/P13-WinUI.exe                 # 595 158, and 291 415 as comparisons, WinUIBackend
./testapp/output/P17-WinUI.exe                 # 264 266 161, WinUIBackend
./testapp/output/P15-WinUI.exe                 # 386 as the control only, WinUIBackend
```

The two lists overlap on the five core-layout issues, which is the point: they
are backend-independent, so running them on both is how a disagreement shows
up. Everything else is specific to one column.

### Three things that invalidate a result

- **P15 without `GTK_THEME=Adwaita:dark` does not test #386.** GtkBackend
  declares `canOverrideWindowColorScheme = false`, so the app's own scheme
  buttons cannot change anything. They are the control; the ambient theme is
  the test.
- **P16 after touching the window does not test #160.** Resizing is one of the
  two things that corrects the layout, so read the pane sizes before moving
  anything.
- **P17 on one platform answers nothing for #161.** The issue is that backends
  disagree, so it needs at least two runs to compare.

### Caveats on the 🌊 column

WSLg is a Wayland compositor, not a desktop session. Window sizing, minimum
sizes and decorations behave differently there, which is why 🌊 and 🐧 are
separate columns rather than one. #556 and #289 are marked 〰️ because both are
about window sizing itself; the rest of Tier 2 is caveated for other reasons
and is not affected by the compositor. Gtk does draw client-side decorations under Wayland, so
#289's precondition holds -- but this is not Fedora with GNOME, so a negative
result bounds the bug rather than closing it.

GTK here is 4.22.4, recent enough that #702 (about *older* GTK 4) cannot be
reproduced at all. Gtk3Backend is out of scope entirely, which drops #286 and
#166 and means #426 is only ever tested against GTK 4.

---

## Results log

### 2026-09-14: P57 GTK Lazy Rows (#117)

WSLg tested first, followed by Windows GTK4; release builds passed with the
row-lifetime fix. Native probes confirmed initial nil selection, selecting row
9999, clearing selection, updating both endpoint labels and changing row count
10,000 -> 1 -> 10,000. Only 205/206 containers were realized for 10,000 rows,
falling to 1 when the model shrank. Settled memory was 327-328 MB on WSL and
260-288 MB on Windows during this sequence.

Both windows stayed open for at least 30 seconds after the render marker. The
black-capture gap was resolved on 2026-09-14: wincap now uses Windows Graphics
Capture and falls back to PrintWindow. WSLg was also in stale COPY MODE; after
`wsl --shutdown` and restart, its title lost the warning and WGC captured it
directly. Final GL captures measured 92.2% non-black on WSLg and 92.1% on
Windows. PIL measured both at 668x776 with content bbox (14,12)-(654,759).
Native API probes are not pointer-input tests, and WinUI regression remains
outstanding. Evidence and remaining checks:
[backend follow-up](plan/plan-backend-followup-20260912.md).

### 2026-07-12

#### P2: Controls And Styling

- #449 Picker: When opening the `Flavor` picker, WinUI/Composition console diagnostic logs such as `BVI-*`, `rcBackdropLocal`, and `CachedNewBlur` were previously observed. WinUIBackend has been changed to override `ComboBoxDropDownBackground` with a solid brush; retest is needed to confirm whether the console noise is gone.
- #449 Picker: Previously, the dropdown disappeared immediately and another option could not be selected. The WinUI ComboBox has been adjusted so items are not updated when options are unchanged, and selection is not reset when the selected index is unchanged; retest is needed.
- #471 TextEditor: Previously, typing could drop characters; for example, quickly entering `12345` might show only `1235`. The one-shot `shouldBlockNextChangedSignal` blocking logic in TextEditor has been removed, and the implementation now tracks the last synchronized text to avoid same-value binding writes; retest is needed.
- #390 (Fixed): Disabled and enabled buttons are currently reported as having no visual-difference issue.
- #401 (Fixed): Window resizing / full-screen button behavior is currently reported as no issue.

#### P3: Layout And Clipping

- #160: Screenshots show that NavigationSplitView columns may be clipped or unstable at initial launch or at specific window sizes. Continue recording the difference before and after resize / force state update.
- #389: Screenshots show that an oversized image may still exceed the expected frame. Record this as image clipping behavior and fix later.

#### P4: WinUI Native And Callback Stress

- #156: Screenshots show that the native WinUI banner and the border modified through `TextField.inspect` are visible. The native API escape hatch appears to work initially.
- #190: Screenshots show that row buttons and the scroll view appear correctly. Still need to click each `Run N`, increase/decrease rows, and repeatedly force updates to confirm callbacks do not get mixed up.
- Row-size increase delay: Currently judged to be related to WinUIBackend. Each P4 row creates multiple native widgets such as Button/Text/Spacer. When row count increases, SwiftCrossUI `ForEach` reuses old rows and appends new rows, but ScrollView/VStack still lays out all rows. WinUIBackend previously rebuilt the button content `TextBlock` on every `updateButton`, which amplified delay during large row updates. It has first been changed so `CustomButton` reuses the label TextBlock; retest is needed to compare whether the delay decreases.

### 2026-08-16

#### P7: Lists And Split Views

- #476 (Fixed): Windows `P7.exe` starts with no selected plain-list row, and the status line shows `Selection: none` as expected.
- #476 (Fixed): WSLg/GTK4 `P7` now starts with the selection binding still `nil`; no plain-list row is highlighted and the status line shows `Selection: none`.
- #476 (Fixed): WSLg/Gtk3 was also confirmed after installing `libgtk-3-dev`; `swift build -c release --target Gtk3Backend` succeeds, and the Gtk3 P7 run no longer starts with `Apple` selected.
- #476 (Fixed): Clicking `Cherry`, `Clear selection`, and `Select Cherry` still updates or clears the selected row correctly after the fix.
- #386 / GTK theme observation: WSLg/GTK uses native GTK theme metrics and colors, so its background, text contrast, spacing, and selected-row styling differ from WinUI. Under `GTK_THEME=Adwaita:dark`, the app background becomes darker, but some text contrast remains poor in the captured screenshot and should be considered when validating GTK theme behavior.
- #556 (Superseded by 2026-09-01 measurement): The screenshots appeared to show a pane aspect / split ratio difference between Windows and WSLg/GTK. Later diagnostics showed this was a measurement mistake: content width was being read as pane width.
- #556: After clicking `Cherry` in the plain List, the NavigationSplitView detail pane still shows `No sidebar selection`. This appears expected for the current P7 test because the plain List selection is separate from the NavigationSplitView sidebar selection, but it is worth keeping in mind when reading the comparison screenshots.
- #556: Step 7 is functionally stable. After clicking `Add a fruit's worth of text`, the longer text above the split view appears and the split view does not jump or collapse. Later diagnostics show the actual pane ratio matches between WSLg and Windows for this scenario.
- #556: Step 8 is functionally stable. After resizing the windows, including a much wider horizontal resize, the detail pane remains visible on both Windows and WSLg/GTK. Later diagnostics show this scenario does not currently reproduce a pane-ratio mismatch.
- #556 / Windows Light mode: The third pane on the right does not show the expected vertical divider line (`|`) in Windows Light mode, while the WSLg/GTK comparison screenshot shows a visible pane boundary. Record this as a Windows/GTK visual parity issue for the split-view detail pane.
- WSL/Windows GUI comparison: The Windows `P7.exe` window and the WSLg/GTK `P7` window should be equal in size for the same test scenario, but the screenshot comparison shows a visible size difference. This needs investigation before treating cross-backend layout screenshots as directly comparable; confirm whether the difference comes from requested content size, backend window-sizing semantics, DPI scaling, window decorations, or WSLg compositor behavior. **(Answered on 2026-08-18 via P6: the cause is DPI scaling -- see that day's entry.)**

#### P8: Scroll Views

- #426 (Confirmed/Open, WSLg/GtkBackend only): This issue is confirmed only on WSLg / GtkBackend; the Windows / WinUIBackend comparison does not reproduce it. On WSLg, neither horizontal nor vertical scrolling moves the scroll views at all, including the case where the pointer is over the inner horizontal strip and the user attempts either horizontal or vertical scrolling; the outer vertical scroll view does not receive/take over the wheel input as expected.
- #426: Future fixes should be reproduced and verified on WSLg / GtkBackend first, then compared against Windows / WinUIBackend as a non-regression check. Use `zsh testapp/test.zsh P8 --both`; the script runs WSLg first, keeps the rendered window open for 30 seconds and captures a final screenshot, then repeats on Windows.
- #417 (Not reproduced on WSLg/GtkBackend): The red child is visibly clipped by `cornerRadius(20)` -- all four corners are rounded in the WSLg screenshot, which is the opposite of the reported symptom of content showing through the corners. Measured alongside it: `cornerScroll: 260x120` against `redChild: 260x300`, so the child does overflow its container by 180px and there is something to clip. Checked under WSLg only, from a static screenshot; Windows was not inspected for this, and neither was a real Linux desktop session.
- #266 (Reproduced incidentally, WinUIBackend only): the inner horizontal strip is measured twice on Windows, at `420x48` and then `408x48`, while WSLg measures it once at `420x48` and stays there. The 12px is the vertical scrollbar of the *outer* ScrollView: WinUI takes it out of the content width on a later layout pass, GTK overlays it and does not. This is exactly the tradeoff #266 describes -- showing a scrollbar changes the width available to the content, which can change the content's height, which can change whether the scrollbar was needed. Harmless here because nothing depends on the width, and P8 does not test #266 deliberately; recorded because it is a ready-made reproduction if #266 is picked up.

### 2026-08-18

#### P6: Stream Player

- P6 was run on WSLg for the first time. It had never been run there not because the Linux presentation path was missing, but because `testapp/output/` is excluded from both git and rsync (the directory is per-machine), so the WSL side had no media file to play. Once a media file was copied over, the ffmpeg decode pipeline, the window, the playback controls and the layout all worked; the screenshot at 00:24 is correct and complete.
- Reading note: the test clip fades in over its first few seconds, so the picture is almost entirely black with only a sliver of transition content at the right edge. A screenshot taken during that window reads as a rendering fault (this happened once during the session). Judge P6 screenshots from the middle of playback, not the start.
- `-seek` (fixed): the flag was defined in the Windows-only `P6WindowFlags` and its single use site was wrapped in `#if os(Windows)`, so on Linux and macOS it was accepted and then did nothing. After moving it to the platform-neutral `P6DecoderFlags`, with the same binary: without `-seek` the play session starts at `0.000s` and the first frame is 00:00; with `-seek 90` it starts at `90.000s` and the first frame is 01:30. Windows still reports `90.000s` after a rebuild, so there is no regression.
- `-maximized` (fixed): also Windows-only before. On GTK the backend's window is now taken from `@Environment(\.window)`, cast to `Gtk.ApplicationWindow`, and maximized through the newly added `Gtk.Window.maximize()`; a screenshot confirms the WSLg window filling the full 1920x1080 screen. SwiftCrossUI previously had no maximize concept in any backend.
- `-topmost` (stays Windows-only): GTK4 has no always-on-top API (`gtk_window_set_keep_above` was GTK3 and was dropped) and Wayland does not let a client raise itself by design, so no Linux path is provided. This is deliberate rather than an omission left for later.
- CJK fonts missing on WSL (fixed): a stock WSL image reports `fc-list :lang=zh-tw` as 0, and fc-match for zh-TW falls back to DejaVu Sans, which has no Han glyphs, so GTK draws Chinese UI text as tofu boxes. The symptom is easily misread as a backend rendering fault: in the same screenshot the video's burned-in Chinese subtitles are sharp (those are pixels) while only the UI text is boxes (that is text), and nothing errors anywhere along the way. After installing `fonts-noto-cjk` the zh-TW font count went from 0 to 30 and the filename renders in full; this is now part of `install_tool_wsl.sh`. Windows is unaffected because it uses the system fonts, which include CJK.
- Audio (resolved): P6 produced no sound under WSLg. **The only cause was the WSLg PulseAudio server having stopped listening** -- `pactl`, `paplay` and SDL all answered `Connection refused` at the same moment. Running `wsl --shutdown` on Windows and reopening WSL brought the server back (`Server Name: pulseaudio`, `Server Version: 17.0`, `Default Sink: RDPSink`, `RDP Sink - Connected to fd 20`), and playback was confirmed by ear. The Windows audio devices were healthy throughout (Realtek(R) Audio `oem10.inf`, NVIDIA HD Audio, AMD HD Audio, NVIDIA Virtual Audio Device, all Started).
- Audio misdiagnosis, recorded so it is not repeated: the 32 lines of `ALSA lib confmisc.c:855:(parse_card) cannot find card '0'` were taken for the root cause, and `SDL_AUDIODRIVER=pulse` was added to P6 because of it. They are a **symptom**: SDL falls back to ALSA only when it cannot reach pulse. Measured once the server was healthy: with no variable set at all, exit 0 and zero ALSA lines -- SDL picks pulse by itself; only forcing `SDL_AUDIODRIVER=alsa` reproduces the 32 lines. The code change has been reverted. The reason it looked like "pulse fixes it" is that the check grepped for `ALSA|error`, which cannot see the pulse path's actual failure, `Could not initialize SDL - Could not connect to PulseAudio`: ALSA failed loudly, pulse failed quietly, and neither played. **Lesson: judge success by exit code, not by a filter that matches particular strings.**
- Diagnostic note: without `pactl` this is indistinguishable from a client-side misconfiguration -- the socket exists, `PULSE_SERVER` points at it correctly, and the permissions are fine, so everything appears configured. `pactl info` is the only check that separates the two, which is why `pulseaudio-utils` is now part of `install_tool_wsl.sh`. The server can stop serving while its socket file stays in place, so the presence of the socket proves nothing.
- The WSL install script was never synced to WSL: `rsync_WSL.zsh` includes only `*.swift` and `testapp/**/*.zsh`, so `install_tool_wsl.sh` never reached the machine it exists to set up. The WSL copy was found still at its August 16 version while the local one had changed several times since. It is now in the include list with the reason recorded.
- The install script is now split: `install_tool_wsl.sh` is bootstrap only (root check, install zsh, hand off) and the real logic lives in the new `install_tool_wsl.zsh`. The `.sh` entry point cannot be avoided -- it runs against a machine that has no zsh, and installing zsh is its job, so a zsh shebang would leave the kernel unable to find an interpreter and the script unable to start at all. Same shape as a self-elevating `.ps1` launcher that hands off immediately. `--help` through either entry point answers in 0.2s and installs nothing.
- A third-party repository aborted the whole install: an NVIDIA CUDA repo was added on 2026-08-17 during the GPU investigation without its keyring, so `apt-get update` failed with `NO_PUBKEY A4B469963BF863CC` and, under `set -e`, the installer stopped before installing anything -- on a machine where every package it wanted was available. It now warns and continues, leaving the installs to fail on their own if a package is genuinely missing. The repo itself still needs attention: add the key or remove it, the GPU investigation having established that the driver was not the problem.
- GTK file chooser does not close (Open, **Wayland only**): the full 2x2, all four cells measured.

  | | Wayland | XWayland |
  |---|---|---|
  | without the fix | **stays open** | closes |
  | with `gtk_native_dialog_destroy()` | **stays open** | closes |

  So **`gtk_native_dialog_destroy()` changes nothing and the fix has been reverted.** The refcount theory proposed earlier (that `GObject.init` takes a second reference on top of the one `gtk_file_chooser_native_new` already hands over, leaving the object never finalised) is **disproven** -- if it held, an explicit destroy would have worked.
- File chooser: the response handler is confirmed to fire normally. After the user picked a file the log shows `load /mnt/c/.../20260721 …`, `session token 2`, `frame 00:00` and `Frame ready`, so the URL came back, the file loaded and frames decoded. **Only the dialog fails to disappear**, which puts the problem in the dialog window's lifetime rather than in signal delivery, and only under Wayland. The same code is fine under XWayland.
- Method note for next time: the way to decide whether this is even our defect is to run a non-SwiftCrossUI GTK4 app -- `gtk4-demo`'s file chooser, say -- under WSLg Wayland. If that also fails to close, the problem belongs to GTK or WSLg rather than GtkBackend; only if it closes cleanly is the backend worth investigating. Not yet done.
- Wayland and XWayland have to be verified separately: Wayland does not let one process drive another client by design, so xdotool sees no windows at all in a default WSLg session. They are genuinely different test targets -- a bug reproduced under one is not evidence about the other, as the file chooser above demonstrates.
- GUI automation now works on WSL: `xdotool` with `xwd`/`netpbm` can click controls and capture window contents under XWayland, without depending on the Windows session being unlocked. Coordinates must go through `xdotool mousemove --window` (window-relative); absolute coordinates are thrown off by window decorations -- measured, absolute clicks did nothing at all and the same click landed correctly once made relative. Note that `xwd` is in `x11-apps`, not `x11-utils`.
- The WSLg window did not appear at all (resolved; the cause was COPY MODE): the report was that P6 started but clicking its taskbar icon did not bring it forward, and the window could not be seen at all. The app itself was fine -- the log had `auto-load`, `frame 00:00` and `Frame ready`, so `onAppear` had run, the window had been created and frames were decoding, and `/mnt/wslg/weston.log` showed the window registered with the RDP peer (`associateWindowId: 1`, `appWindowId: 0x10`). The cause was **WSLg being in COPY MODE**: its rendering path had degraded, so the window existed but could not be raised. `wsl --shutdown` on Windows followed by reopening WSL cleared it and the window appeared immediately.
- What triggered it: WSL updated itself in the meantime (2.7.11.0 to 2.7.12.0) while the running WSLg instance stayed on the old state, and it entered COPY MODE from then on. This is the same class as the earlier PulseAudio failure -- **a WSLg bridge, whether windows or audio, can degrade while the socket or window still looks present, and says nothing at all**. Both times the remedy was `wsl --shutdown` and reopening.
- WSLg rewrites window titles, which defeats tools that find a window by name: normally `P6 stream player (Ubuntu)`, and when degraded `[WARN:COPY MODE] P6 stream player (Ubuntu)`. AppActivate matches the beginning or the end of a title, so that prefix makes a search for "P6 stream player" fail outright -- and the way it fails is a screenshot of whatever else was on screen, not a "window not found". `screenshot.zsh` now resolves the real title by substring and names COPY MODE with its remedy when it sees it.
- P6 does not reap its ffplay children on Linux: three orphaned ffplay processes, each about 8.3 hours old, were still running after P6 had exited. The `P6ChildProcessReaper` job-object mechanism is `#if os(Windows)` only and has no Linux counterpart. Not yet fixed.
- GTK file chooser (Open, not fixed): on WSLg the `Choose file` dialog does not close after a file is selected. The code is `showFileChooserDialog` in `Sources/GtkBackend/GtkBackend.swift`: it calls `gtk_native_dialog_show()`, but the response handler only handles the result and never hides or destroys the dialog. The same block in `Sources/Gtk3Backend/Gtk3Backend.swift` is structured identically. No fix has been verified on a machine yet.
- WSL/Windows GUI comparison (answer to the 2026-08-16 entry): the size difference comes from **DPI scaling**, not from requested content size, backend window-sizing semantics, window decorations or WSLg compositor behavior. Measured on the same 1920x1080 screen with both sides `-maximized`: the Windows video area is 1200x675 px and the WSLg/GTK one is 960x540 px. The Windows log records this itself as `viewport 960.0x540.0 dip (1200x675 px), panel actual 960.0x540.0 dip, rasterization scale 1.25`, alongside `window metrics: dpi 120`. So WinUIBackend applies a 1.25 rasterization scale and GtkBackend renders 1:1. Cross-backend layout screenshots therefore cannot be treated as directly comparable until the DPI scale is factored out.

### 2026-08-19

#### GTK file chooser: root cause found

- **The cause is the API in use, not how we use it.** Established by running a native GTK4 app with no SwiftCrossUI in it (`gtk4-node-editor`) in the same WSLg Wayland session: its file dialog **closes normally**. Comparing the symbols each actually links against, via `nm -D --undefined-only`:

  | | API used | Wayland |
  |---|---|---|
  | `gtk4-node-editor` | `gtk_file_dialog_new` / `gtk_file_dialog_open` (**GtkFileDialog**) | closes |
  | SwiftCrossUI GtkBackend | `gtk_file_chooser_native_new` / `gtk_native_dialog_show` (**GtkFileChooserNative**) | stays open |

  Same machine, same GTK 4.22, same compositor; the API is the only difference.
- `GtkFileChooserNative` is marked `deprecated="1"` in the GIR (`Gtk-4.0.gir`). The header carries no `GDK_DEPRECATED` macro, so checking the header alone gives the wrong answer -- the GIR is authoritative, and it is the same data `GtkCodeGen` generates the Swift bindings from.
- The replacement, `GtkFileDialog`, has been available since **GTK 4.10** (`GDK_AVAILABLE_IN_4_10`), and the system headers carry everything needed: `open`/`open_multiple`/`save`/`select_folder` with their `_finish` counterparts, plus `set_title`, `set_initial_folder`, `set_filters` and `set_accept_label`. It is an **async API** (`GAsyncResult` callbacks) rather than the `response`-signal model the current code is built around, so migrating means rewriting the flow, not renaming calls.
- Method note: three attempted fixes failed because each assumed we were using the API wrongly. What worked was **separating ownership** -- using a native app as a control to see whether anyone can do this in the same environment. That is cheaper than any further theory.

#### Dropping GTK3

- Removed `Sources/Gtk3` (179 files, 16,365 lines), `Sources/Gtk3Backend` (2,448 lines), `Sources/CGtk3`, `Sources/Gtk3CHelpers`, `Sources/Gtk3Example`, `Tests/Gtk3BackendTests`, `Scripts/generate_gtk3.sh` and the Gtk3Backend docc page.
- The real code dependencies were **only two**: `Package.swift` (products, targets and the `SCUI_TEST_GTK3BACKEND` switch) and `Sources/DefaultBackend` (the `#elseif canImport(Gtk3Backend)` fallback). Everything else scattered around was comments or conditional-compilation branches.
- The `#if canImport(Gtk3Backend)` branches in `Examples` compile out by themselves once the module is gone and would not have broken the build, but were removed anyway. `ControlsApp.swift`'s `#if !canImport(Gtk3Backend)` is the opposite case -- it becomes permanently true, so the wrapper was unwrapped and its contents now compile unconditionally.
- Cleaning up the prose turned up **two real breakages**, not just wording: `Scripts/generate_gtk.sh` still invoked the deleted `./generate_gtk3.sh`, and `GtkCodeGen`'s `gtk3AllowListedClasses` and `version == "3.0"` branch were live generation logic. The CI workflow was also still building and documenting `Gtk3Backend` across three steps and the docc merge list, and `Publisher.swift` carried a ``Gtk3Backend`` DocC symbol link that no longer resolves to anything.
- Three places were **deliberately left alone**: the first-person note in `gtk_helpers.h` recounting a macOS build oddity, `AppBackend refactor.md` (which states up front that it is the change list for a particular PR, so it is a historical document), and the `populate-popup` rationale in `GtkCodeGen` -- that one was reworded to say the Gtk3 crash no longer applies but re-enabling has not been tested on Gtk4, rather than simply enabling the signal, which would be a behaviour change. Rewriting someone's account of what happened is falsifying the record, not cleaning up.
- **rsync does not propagate deletions, and a passing build hides it**: `rsync_WSL.zsh` deliberately omits `--delete`, so that the WSL side keeps its `output/`, build caches and local edits. The result is that after 193 GTK3 files were deleted here, **every one of them was still in WSL**; and because SwiftPM ignores directories `Package.swift` no longer declares, all four targets kept building there -- on a tree that no longer matched this one, looking entirely healthy. The WSL copy was cleaned by hand and re-verified, and the consequence is now written into `rsync_WSL.zsh`'s header.
- Verified: the `Gtk`, `GtkBackend`, `DefaultBackend` and `GtkExample` targets all build, and every edited file passes `swiftc -parse`. A whole-package `swift build`, and the `Examples` package, still stop on `WinUIInterop`/`swift-winui` missing `Windows.h` and `wtypesbase.h` -- a pre-existing platform limit on Linux, unrelated to this removal.

#### GtkBackend now builds on Windows

- The motivation is compile time: P6 takes 95-103s to build on Windows against WinUIBackend and 13-22s in WSL against GtkBackend, and the cost is WinAppSDK. WinUIBackend **stays as the baseline** and is not removed.
- The ABI decides the source: Swift on Windows targets the MSVC ABI and links the UCRT. MSYS2's GTK 4 is MinGW-built and is not a candidate; the bundle comes from gvsbuild, which builds with MSVC (`testapp/install_gtk4_windows.zsh`, with source and licensing recorded under `Acknowledgements/gvsbuild/`).
- The path rewriting now comes from a **checked-in patch** (`testapp/patches/gtk4-pkgconfig-relocate.patch`), with line endings handled separately by a single `tr`. Splitting them is measurable: together the diff is 8397 lines and 391 KB, because the CR removal makes every line of every file differ; apart it is 2745 lines, of which roughly 600 are real changes and the rest is 302 files' worth of diff headers.
- The order is forced by the toolchain rather than chosen: **MSYS tools read in text mode and drop CR whenever they touch a file**. Measured, a `sed -i` that only edited the prefix line took gtk4.pc from 14 CR bytes to 0. So line endings cannot be left until last -- normalising first is what leaves the patch applying to content that actually matches.
- The patch is tied to one gvsbuild release, so a rule-based fallback stays: if `patch` does not apply, which is expected on a version bump, the installer says so and falls back to the same two substitutions the patch encodes. Measured: the patch applied cleanly to 302 files and `swift build --target GtkBackend` exits 0 on Windows.
- The gvsbuild bundle is **not relocatable as shipped**: 301 of its 302 `.pc` files hardcode the build machine's `C:/gtk-build/gtk/x64/release`, and all of them use CRLF.
- **SwiftPM's `.pc` parser breaks on Windows drive letters**: it splits keyword lines on the first colon, so `prefix=C:/gtk4` is read as the keyword `prefix=C`, the variable `prefix` is never defined, and it reports `Expected a value for variable 'prefix'`. Rewriting to the colon-free `prefix=${pcfiledir}/../..` parses; every other remaining path is substituted with `${prefix}` for the same reason.
- **SwiftPM does not apply a systemLibrary's pkgConfig cflags on Windows**: measured, the clang invocation for `GtkCHelpers` carried only its own include directory and nothing from `gtk4.pc`, even with `PKG_CONFIG_PATH` set and pkg-config reporting correctly. The flags have to be passed as `-Xcc -I…`; the installer prints a ready-made command.
- Two genuine portability defects, both Linux/Windows differences in how C types import, and both fixed without any `#if os(Windows)`:
  - `gulong` is 64 bits on Linux and **32** on Windows (LLP64). `connectSignal` converted it to `UInt` on the way out, after which disconnect, block and unblock all failed to compile. It now stays `gulong` throughout.
  - `gsize` imports as `UInt` on Linux and `UInt64` on Windows -- same width, different nominal types in Swift. Now converted explicitly with `gsize(...)`.
- Result: `swift build --target GtkBackend` exits 0 on Windows, with Linux re-verified for regressions. Runtime verification and the compile-time comparison are still to do; the plan is in `testapp/plan/plan-windows-gtk-backend.md`.

#### WSLg ghost windows

- After the `gtk4-widget-factory` process exited, `msrdc.exe` on the Windows side kept showing a `GTK Widget Factory (Ubuntu)` window, while `pgrep` inside WSL confirmed no such process was left.
- This is the third way a WSLg bridge fails silently, after PulseAudio ceasing to listen and COPY MODE: a window with no owner is left on screen. When reading WSL GUI test results, "the window is visible on Windows" is not evidence that the app is still running.

### 2026-08-29

#### P21-P41 Loader Coverage

- Added missing `test_support/test_Pn.zsh` loaders for P21, P22, P23, P24, P25, P27, P29, P37, P38, P39, P40 and P41. `zsh -n` passes for every new loader and for `test_support/test_common.zsh`.
- The common loader now records screenshot failures without aborting the whole run under `set -e`. This was needed because a failed 1-second capture could previously exit before the cleanup trap released `ui-lock`.
- Test order followed the current rule: WSLg first, then Windows. P27/P29/P37/P38/P39/P40/P41 were run first, followed by P21-P25.

#### Automated Smoke Results

All final screenshots below were captured with `wincap` and measured with PIL. Every final capture was visible and non-black.

| App | WSLg final screenshot | Windows final screenshot | Notes |
| --- | --- | --- | --- |
| P21 | 848x749, 93.0% non-black | 836x759, 93.2% non-black | Windows render marker arrived after 8s; WSLg marker arrived immediately. |
| P22 | 788x729, 92.6% non-black | 776x739, 93.0% non-black | Wrapped text diagnostic differs: WSLg `300 x 46`, Windows `300 x 32`. |
| P23 | 848x649, 92.4% non-black | 836x659, 92.5% non-black | Both platforms built and reached the final capture. |
| P24 | 748x589, 91.5% non-black | 736x599, 91.8% non-black | Both platforms built and reached the final capture. |
| P25 | 748x549, 91.2% non-black | 736x559, 91.3% non-black | Automated run verifies launch/capture only; live drag/drop still needs manual interaction. |
| P27 | 788x726, 92.6% non-black | 776x702, 92.8% non-black | Both platforms built and reached the final capture. |
| P29 | 796x657, 82.8% non-black | 736x599, 91.7% non-black | WSLg `P29-texteditor-disabled.csv` was added and verified: final capture shows the editor enabled after replay. Windows smoke final is visible, but WinUI actionfile replay produced no `-actionfile` report in this run and remains unresolved. |
| P37 | 788x569, 91.5% non-black | 776x579, 91.6% non-black | WSLg reports supported levels `automatic, normal`; Windows reports `automatic, normal, floating`. Window-level behaviour still needs a second-window foreground/topmost challenge; this run only verifies baseline launch/capture and backend capability reporting. |
| P38 | 848x692, 92.6% non-black | 836x699, 92.8% non-black | WSLg 1-second and final captures were both visible in the latest run and show the expected GtkBackend placeholder. Windows final capture is visible, but the WebView area is still an empty grey frame with `Navigations reported: 0`. |
| P39 | 888x649, 92.5% non-black | 876x659, 92.5% non-black | WSLg shows visible opacity, blur, saturation, brightness, contrast, grayscale and hue-rotation effects. ~~Windows shows opacity, but blur and most colour effects appear identical to the control, so WinUI visual effects remain suspect.~~ **Superseded 2026-09-02** (struck through, not deleted, so the stale claim stays on record): Windows now applies all seven through a real Win2D effect graph. Verified 2026-09-02, `applied=8 failed=0 total=8`; regenerate with `cd testapp/output && SCUI_DEBUG_VISUAL_EFFECTS=1 ./P39-WinUI.exe` then read `winui-visual-effects-debug.log`. |
| P40 | 928x736, 93.1% non-black | 916x708, 93.0% non-black | Fixed WSLg geometry no-op/clipping: PIL now finds seven transformed color components with scale/rotate/shear bounding boxes comparable to WinUI. Exact/near hotpink pixels: 0 on both platforms. Background differs by platform theme: WSLg default is light; WinUI is dark here. |
| P41 | 968x649, 92.5% non-black | 956x659, 92.7% non-black | Windows `.graphical` DatePicker is visible in the latest screenshot, not a blank sliver. WSLg `.wheel` is visually distinct; Windows `.wheel` still appears as a segmented date input and should be treated as a style parity/fallback observation. |

#### Timing Observations

- On WSLg, release builds for these apps completed in roughly 12-13s after source sync.
- On Windows, P27 took 231.84s in an earlier build; later P37-P41 builds generally completed in about 38-75s. Windows builds still print `pkg-config` / `gtk4.pc` warnings even when the WinUI app builds successfully.
- Several Windows apps did not have a visible window for the 1-second capture, but became visible for the final capture. Treat this as startup/window-discovery timing unless the final capture also fails.
- `--actionfile <relative path>` exposed a loader bug on Windows: the path containment check compared the relative path against the absolute `testapp` path. Using bare `--actionfile` avoided it for WSLg; `test_common.zsh` now has a local path converter so Windows no longer depends on `cygpath`.

### 2026-08-30

#### P30-P36 Loader And Baseline Coverage

- Added compileable baseline apps and `test_support/test_Pn.zsh` loaders for P30, P31, P32, P33, P34, P35 and P36.
- `testapp/compile.zsh` now defaults to release builds on Windows as well as WSLg. A debug build still requires `BUILD_CONFIG=debug`.
- Test order followed the current rule: WSLg first, then Windows. WSLg was synced through `testapp/rsync_WSL.zsh` before compiling under `/home/lowei/proj/swift-cross-ui`.

#### Automated Smoke Results

All final screenshots below were measured with PIL. Every final capture was visible and non-black.

| App | WSLg final screenshot | Windows final screenshot | Notes |
| --- | --- | --- | --- |
| P30 | 888x649, 92.5% non-black | 876x659, 92.6% non-black | WSLg shows visible blur/grayscale-style effects. Windows shows opacity and geometric transforms, but blur/grayscale appear to behave like no-ops; record as WinUI visual-effect parity still needing investigation. |
| P31 | 808x589, 91.8% non-black | 796x599, 91.9% non-black | Baseline focus/keyboard controls render on both platforms. ~~Real Tab order, Space/Return activation, Escape and Ctrl+Q still need manual keyboard testing.~~ **Superseded 2026-09-03 for two of the four:** Tab order and Space activation are now measured on Windows/GtkBackend and both work — see the 2026-09-03 entry. Escape and Ctrl+Q are still unmeasured, and Escape *cannot* be measured by action file at all. |
| P32 | 788x589, 91.7% non-black | 776x599, 91.8% non-black | Accessibility baseline controls render on both platforms. Role/name verification still needs Accerciser on Linux and Accessibility Insights or `inspect.exe` on Windows. |
| P33 | 848x649, 92.4% non-black | 836x659, 92.5% non-black | Missing-view list and hand-written approximations render on both platforms. This is a compileable baseline, not evidence that the missing SwiftUI views now exist. |
| P34 | 808x649, 92.2% non-black | 796x659, 92.4% non-black | Smoke run used `--debug -rows 100`. Larger row-count/performance testing is still separate. |
| P35 | 788x589, 91.7% non-black | 776x599, 91.8% non-black | State baseline renders on both platforms. Scene composition gaps remain compile-time issues. |
| P36 | 848x649, 92.4% non-black | 836x659, 92.5% non-black | SwiftCrossUI-compatible API shapes render, while SwiftUI-shaped missing calls are listed as text so normal test builds keep compiling. |

#### Timing Observations

- WSLg release builds completed quickly after sync: P30 took 13.66s, then P31-P36 each took about 6-10s.
- Windows release rebuild was much slower, especially the first target after changing build configuration: P30 took 900.34s, while P31-P36 then took roughly 11-29s each.
- On Windows, several 1-second screenshots captured only a nearly blank first frame, while the final 10-second screenshots were normal. Treat this as WinUI first-paint/window-capture timing unless a final screenshot also fails.
- The WSLg runs reported `[WARN:COPY MODE]` in the window title even though the final captures were visible. These runs are useful for UI layout smoke testing, but not for validating GPU rendering performance.

### 2026-08-31

#### P16: WinUI NavigationSplitView Initial Layout (#160)

- Windows `P16.exe` was rebuilt and run with the existing diagnostic app. The final screenshot was visible at 916x639 with 92.5% non-black pixels.
- Initial diagnostics still show an unstable first measurement path: `sidebar: 0 x 22`, `detail: 0 x 22`, then `detail: 734 x 22`. The screenshot visually shows the left pane present, but the sidebar probe does not report a stable non-zero width.
- Root cause found for one runner bug: `compile.zsh` accepted `SCUI_DEBUG=1` but did not pass `-Xswiftc -DSCUI_DEBUG` to `swift build`. This has been fixed in the working tree, and the build-plan hash now includes `SCUI_DEBUG` so a stale SwiftPM plan is not reused after toggling debug features.
- The actionfile hook is now observable: WinUI `show(window:)` schedules replay, and `ActionFileReplay` writes geometry plus replay status to `actionfile-replay.log`, which avoids a false negative caused by WinUI console redirection.
- P16 actionfile replay still has not produced the expected UI state changes: the Force update counter, sidebar selection and column switch were not confirmed in the final screenshot. The remaining issue is therefore more likely Win32 synthetic input hitting / focus / activation of WinUI controls, not simply loading the action file.
- A clean `P16 --windows --no-build --showtime 10` run with a cleared `actionfile-replay.log` reported `SendInput` as `ERROR_ACCESS_DENIED`. This run is not evidence about app behavior; rerun on an unlocked desktop with no elevated foreground window.
- After initializing WinUI `createSplitView` with an `openPaneLength`, P16's final screenshot now reports `sidebar: 180 x 22` and `detail: 660 x 22`; `Science` / `Humanities` are no longer squeezed into wrapped text. This matches GTK's initial 200px sidebar guess and prevents core `SplitView.computeLayout` from reading a 0-width sidebar on the first pass.
- Current verdict: the initial-layout repro for #160 is fixed. What remains unverified is actionfile-driven interaction for Force update / sidebar selection / column switch. The latest actionfile report can say `replayed`, but the visible counter still does not change, so this part still needs manual verification or more reliable WinUI control activation.

#### P7: NavigationSplitView Pane Ratio (#556)

- P7 was run WSLg first, then Windows. Both final screenshots were visible at 748x509.
- WSLg diagnostics: `[SplitView] total=420.0 minLeading=31.0 minTrailing=36.0 -> bounds min=31 max=384 currentSidebar=200`.
- Windows diagnostics: `[SplitView] total=420.0 minLeading=31.0 minTrailing=35.0 -> bounds min=31 max=385 currentSidebar=200`.
- Both platforms therefore use the same actual split ratio in this run: sidebar 200 / total 420, or 47.6%.
- The earlier 87px-style conclusion was a measurement mistake: it read content width as pane width. P7's own comment now calls this out; content probes can be much narrower than the pane that contains them.
- Current verdict: #556 does not reproduce as a pane-ratio mismatch in the current P7 run. Keep it open only if a different resize/content scenario still shows a mismatch; otherwise update the plan from "ratio mismatch" to "measurement guard / regression coverage".

#### P30/P39: WinUI Visual Effects

- P30 and P39 were run on Windows, and P39 was rerun on WSLg for comparison.
- PIL crop comparison on Windows P39 shows only opacity changes pixels. The control crop compared with blur, saturation, brightness, contrast, grayscale and hue-rotation all returned `mean_diff=0.00`; the blur text edge metric was also identical to control.
- PIL crop comparison on WSLg P39 shows the expected non-zero changes: saturation 0 and grayscale 1 have chroma 0, hue rotation has a large mean diff, and blur has a measurable diff.
- ~~Code review confirms the screenshot result: `WinUIBackend+VisualEffects.swift` currently sets only `widget.opacity`; the other visual effects are intentionally reported as requiring a Microsoft.UI.Composition effect graph that is not implemented yet.~~ (Superseded 2026-09-02 — see the last bullet in this section.)
- ~~Current verdict: this is not a weak test sample. WinUI visual effects other than opacity are real no-ops today.~~ (Superseded 2026-09-02 — see the last bullet in this section.)
- 2026-09-01 rerun: WSLg and Windows P30/P39 all launched, reached final screenshots and closed cleanly. Latest P39 PIL comparison matches the earlier result: Windows `opacity mean_diff=59.73`, while blur, saturation, brightness, contrast, grayscale and hue rotation all remain `mean_diff=0.00`; WSLg reports non-zero differences for every non-control sample.
- 2026-09-01 follow-up: `WinUIBackend+VisualEffects.swift` now reports unsupported effects only once per effect name, reducing repeated console warnings during normal update passes. ~~This does not change rendering semantics: opacity is still the only implemented WinUI visual effect.~~ (Superseded 2026-09-02 — see the last bullet in this section.)
- Latest P39 final screenshots after that change: WSLg `p39-wslg-final-20260901-071259.png`, Windows `p39-windows-final-20260901-071318.png`. PIL comparison still reports Windows `opacity mean_diff=69.20`; blur, saturation, brightness, contrast, grayscale and hue rotation remain `mean_diff=0.00`. WSLg reports non-zero differences for every non-control sample.
- **Superseded 2026-09-02: WinUI implements all seven visual effects.** The struck-through bullets above are kept rather than deleted — they were an honest and correctly measured reading of the binary of that date, and a record of what a plausible-but-false verification looks like is worth more than a clean page. What changed is the code, not the measurement method. `WinUIBackend+VisualEffects.swift` now builds a real Win2D effect graph (`Win2DEffectGraph`): `GaussianBlurEffect` for blur, `ColorMatrixEffect` for saturation and brightness, plus `ContrastEffect`, `GrayscaleEffect` and `HueRotationEffect`, with opacity kept as a `needsOnlyOpacity` fast path that skips the graph. It is Win2D, not the `Microsoft.UI.Composition` graph the older bullets predicted, and `Microsoft.Graphics.Canvas.dll` ships in `testapp/output/`. Verified 2026-09-02: `applied=8 failed=0 total=8` — regenerate that number with `cd testapp/output && SCUI_DEBUG_VISUAL_EFFECTS=1 ./P39-WinUI.exe`, then read `winui-visual-effects-debug.log`. Verified 2026-09-02 at pixel level from a wincap screenshot, mean HSV saturation per cell: saturation 0 → 0.000, saturation 0.5 → 0.515, control (=1) → 0.818, saturation 2.5 → 0.992 — a monotonic ladder, which the earlier all-zeros result could not have produced. One effect WAS genuinely broken until 2026-09-02: `saturation 2.5` failed with `0x80070057` `E_INVALIDARG` because Win2D's `SaturationEffect` cannot oversaturate; it was switched to `ColorMatrixEffect`.
- 2026-09-01 P16 rerun, against a binary rebuilt the same hour: **all three clicks landed, which supersedes the earlier entry saying the state changes were not confirmed.** Read against the initial values in `P16.swift` rather than by eye: `updateCount` starts at `0` and the capture shows `Force update (1)`; `selectedArea` starts at `nil` and the capture shows `Science` selected; `columns` starts at `.two` and the button reads `Switch to 2 column`, which is the label for `.three`, with all three panes present. The earlier run that reported no state changes is the one that also reported `SendInput` as `ERROR_ACCESS_DENIED`.
- The same run reports `-actionfile: warning: the window never took the foreground. This file only moves and clicks, so it ran on the topmost pin alone`. That is not a failure: clicks are delivered by coordinate to whatever is topmost, and `SetWindowPos(HWND_TOPMOST)` puts our window there, which is why all three landed. It is worth knowing because anything focus-sensitive can differ from a run that did take the foreground.
- **The remaining #160 symptom is the height, not the width.** Final capture reports `sidebar: 180 x 22`, `middle: 180 x 22`, `detail: 460 x 22`. The widths are now right and were the visible half of the bug; a height of 22 cannot be correct, because the panes fill the window. The reported progression in the same run is `sidebar 0 -> 180`, `middle 0 -> 180`, `detail 0 -> 460 -> 660`, so the width settles and the height never moves off 22.
- 2026-09-01, correcting the entry above: **the widths are not trustworthy either, so "the remaining symptom is the height" was wrong.** The probe is a `GeometryReader` under `.frame(height: 22)` sitting inside the pane's `VStack`, so the height can only ever be 22 and the width is the content column rather than the pane. Moving the reader into `.overlay(alignment: .topLeading)`, the shape `P7SplitProbe` uses successfully, broke P16: the window never became visible, wincap found nothing to capture at one second or at the end, the action file never replayed, and the panes reported `sidebar 200 x 142` and `detail 20 x 46`. Reverted. `.overlay` does not behave here as it does in SwiftUI, and it already has history in this project -- it used to swallow pointer events.
- **#160 therefore cannot be settled from P16's numbers at all yet**, in either direction. The click results above still stand, because those are read from the app's own state rather than from the probe.
- 2026-09-01, settling the entry above: **the panes are measured now, and #160 does not reproduce on WinUIBackend.** The measurement was moved out of the view tree entirely. `SplitView.commit` already had an `SCUI_DEBUG_SPLIT` diagnostic printing the minimums and the bounds it hands the backend; it now also prints the size each pane was actually given. Nothing is added to the view tree, so nothing perturbs what is being measured -- which is what defeated every previous attempt.
- Run A, `SCUI_DEBUG_SPLIT=1 ./P16-WinUI.exe --debug`, no action file, killed after 8s. Exactly one committed layout:
  `total=880.0 minLeading=126.0 minTrailing=20.0 -> bounds min=126 max=860 currentSidebar=200 leadingPane=200.0x486.0 trailingPane=680.0x486.0`
- Run B, the same with `-actionfile actions/win/P16-force-update.csv`, killed after 12s. Five lines. **Lines 1-3 are byte-identical to run A's single line**; run A establishes that the first render is one line, so lines 2 and 3 are the layouts after the `Force update` click and the `Science` selection. Lines 4-5 are the three-column state, which is two nested split views: inner `total=680.0 minLeading=20.0 minTrailing=20.0 -> bounds min=20 max=660 currentSidebar=200 leadingPane=200.0x486.0 trailingPane=480.0x486.0`, outer `total=880.0 minLeading=113.0 minTrailing=220.0 -> bounds min=113 max=660 currentSidebar=200 leadingPane=200.0x486.0 trailingPane=680.0x486.0`.
- **The sizes the panes are given at first render are identical to the sizes after two state changes.** #160 says a split view lays out very incorrectly on first render and snaps as soon as any state changes; there is no snap here, because there is nothing to snap from.
- The negative is trustworthy because lines 4-5 differ: the diagnostic demonstrably responds to a real layout change in the same run, so "no change across lines 1-3" is a measured no-change rather than a dead log. Without that control it would be indistinguishable from a diagnostic that had stopped firing.
- Incidentally this disposes of the height question: the panes are **486** tall, not 22. The 22 was the probe's own `.frame(height: 22)`, reported for two weeks as the pane's height.
- Scope of the claim: this is what SwiftCrossUI's layout system decided, not what WinUI painted. A paint-side discrepancy would not appear here. Worth stating because the 1s capture in the same runs is **entirely black** -- WinUI has not painted at one second, which is also why the action file sleeps 1.8s before its first click -- so the harness's "1s" screenshot has never been a picture of the first render.
- Reproduce: `cd testapp/output && rm -f splitview-debug.log && SCUI_DEBUG_SPLIT=1 ./P16-WinUI.exe --debug` then read `splitview-debug.log`. Requires a binary built with `SCUI_DEBUG=1`.
- Correcting one sentence in the entry two above, which said the overlay works in P7 "because it wraps a `List`": P7's **sidebar** overlay wraps a `List`, but its **detail** overlay wraps a padded `VStack`, the same shape as P16's. The distinguishing factors are that P7's panes contain no `Spacer` and its whole split view sits inside `.frame(width: 420, height: 180)`, so nothing in it is free to grow, whereas each P16 pane ends with a greedy `Spacer` and the split view has no fixed frame.
- **Correcting the field names used above.** They were first emitted as `leadingPane` / `trailingPane`, and that was wrong: `leadingResult.size` is what the pane's *child* chose when offered the pane's width, which can be less than the pane. On P16 the two coincide, so the mistake was invisible there; P7 exposed it, with a trailing child answering **207** to an offer of **420 - 200 = 220**. Renamed to `leadingContent` / `trailingContent`. The pane widths are `currentSidebar` and `total` minus it. This is the same content-read-as-pane confusion that produced two wrong diagnoses of #556, which is why the names now say which one they are. The numbers quoted above are unchanged and the #160 comparison still holds, because it compared like with like; only the label was wrong.

#### P16 and P7 on GtkBackend (WSLg), same diagnostic

- 2026-09-01. Built on the WSL copy after `rsync`, with `grep -c lastLeadingPaneSize` on the WSL side as the control that the Windows edit actually landed there (4 hits) -- a WSL build of unsynced sources reports success against the old code.
- **P16 on GTK does not behave like P16 on WinUI.** WinUI commits the first render once. GTK commits it three times, and the height moves: `leadingContent=200x485` then `200x446` then `200x446`, widths unchanged at 200 / 680, `minLeading=104 minTrailing=33 bounds 104..847 currentSidebar=200`. Three consecutive runs produced byte-identical output, so the 485 is reproducible and not noise.
- That settle happens on its own, within the first render and before any interaction, so it is not #160 either -- #160 is a layout that stays wrong until a state change. It is a 39px transient, not "very incorrect", and the widths never move.
- **Which of the two is right: WinUI's. GTK is 39px short, and the 39 is a header bar.** P16 asks for `.defaultSize(width: 900, height: 600)`. Measuring `p16-gtk-headerbar-20260901-165737.png`: the GTK window surface is exactly **900x600**, there is a **39px** client-side-decoration header bar inside it, and the content area is **900x561**. 485 - 446 = 39 exactly. GTK's *first* pass is the one that honours the request; it then correctly re-lays out for a window that turned out smaller than asked for. The layout system is not at fault -- the window is.
- Cause: `GtkBackend.createWindow` hands the requested size straight to `window.defaultSize` (GtkBackend.swift:994-997) and so to `gtk_window_set_default_size` (Sources/Gtk/Widgets/Window.swift:63), which in GTK4 sizes the **whole window including the CSD titlebar**. On Windows the title bar is non-client area -- the same app measures a 916x639 frame around a 900x600 client -- so WinUI delivers what was asked. Filed as its own task; the widths are unaffected, both backends report `total=880` = 900 - 2x10 padding.
- What SwiftUI does here is **not verified** -- it needs a Mac, which is out of scope on this machine. The expectation to check there is that `.defaultSize` sets the *content* size, because on macOS it maps to the window's content rect and the title bar is additional, which would put SwiftUI on WinUI's side. Recorded as the thing to measure, not as a result.
- **P7 on GTK, now with content sizes:** `total=420.0 minLeading=31.0 minTrailing=36.0 -> bounds min=31 max=384 currentSidebar=200 leadingContent=200.0x140.0 trailingContent=207.0x77.0`, three identical lines. The sidebar figure of 200/420 that settled #556 is confirmed at the layout level.
- **Retracting "worth a look" from the line above.** The 207-against-220 and the 140-against-77 were called anomalies before they were checked; measuring `p7-gtk-556-20260901-165945.png` explains every one of them, and none is a defect:
  - The detail text is visibly wrapped into two lines. Their ink widths are 186 and 140, so the longest laid-out line is 186; add the `VStack`'s 10px padding on each side and the child's width is 206-207. **A wrapped `Text` reports the width of its longest line, not the width it was offered**, which is also what SwiftUI does. The offer was 220 and the answer was 207 because the text broke at a word boundary.
  - That 207 is then centred in the 220-wide pane, exactly as `SplitView.commit` says it centres pane children: (220-207)/2 = 6.5, plus 10 of padding, puts the text's left edge at 505.5 against a divider at x=488. Measured: **505**. The first line, "No sidebar selection", has its ink centre at 598 against a pane centre of 599.
  - `leadingContent` 140 is five list rows at a 28px pitch, measured off the rows themselves. Centred in the 180-tall box that gives a 20px top inset, so the first row should start 20px below the box top. Measured: first row ink at y=248, box top at 228.
  - The two heights differ because the two contents differ, and neither fills the pane. That is what non-greedy content does, and the framework centres it deliberately.
- The one question these numbers do raise is separate from #556 and should not be filed under it: **should a `List` be greedy vertically?** SwiftUI's fills its container on both axes; this one filled the 200 width but answered 140 rather than 180 for the height. Unverified against a real SwiftUI build -- that needs a Mac.

#### All three backends, after the macOS side answered

- The macOS answers are in `mac-test-results-20260901.md`, measured on AppKitBackend the same day. Summarised here because the point of the exercise was the three-way comparison; the raw lines and the method are in that file.
- **Q1 is settled and GTK was the outlier.** AppKit gives a 900x628 frame with a 28pt title bar, so **content 900x600 -- exactly the request**, taken from two independent sources (`CGWindowListCopyWindowInfo` for the frame, and the InputEvent replay reading AppKit's own frame against the client origin, 120 against 148). That matches WinUI and confirms the expectation this file recorded as unverified rather than asserting. GTK's 900x561 was the only short one, and ~~is now fixed -- see `todo.md`~~ **-- that "now fixed" did not survive re-measurement. On 2026-09-03 P16 on GTK/Windows (gvsbuild) still logs the same 39px drop, 480 / 480 / 441. `correctContentSizeIfNeeded` exists in `GtkBackend.swift` and runs from `updateWindow`, so the code landed; what has not been shown is that it delivers. See the 2026-09-03 entry, and treat the `todo.md` item as open.**
- **Q2 splits one observation into two.** AppKit commits P16's first render **three** times, like GTK and unlike WinUI's one -- but its height never moves, where GTK's went 485 -> 446 -> 446. So "commits three times" and "the height converges" are independent, and only the second was ever evidence of anything. All three agree on widths, 200 / 680. The settled heights differ by exactly what each platform puts above the content: **497 AppKit / 486 WinUI / 446 GTK before the fix**.
- **Q3 is the most useful answer.** AppKit's `List` also reports **140** in a 180-tall pane -- the same number GTK gives. Two independently written backends agreeing puts the behaviour in the **shared layout code**, not in either backend, which is exactly what the measurement was designed to distinguish. `List` not being greedy vertically is therefore a real SwiftUI parity gap in SwiftCrossUI itself.
- Worth carrying beyond this task: their file records that `AppKitBackend.createWindow` calls `setFrameAutosaveName(id)` with an `id` derived from the root view's type, so most test apps **share one key** (`"NSWindow Frame TupleView1<HotReloadableView>-0"`). A saved frame then wins over `.defaultSize` entirely -- P28 opened at 680x448 or 1076x907 from the same binary at the same commit depending on what that key held. Any earlier macOS measurement of a window size taken without clearing it is suspect.

### 2026-09-02

#### P39 and P40 on AppKitBackend and UIKitBackend: both effect families implemented

- Until this date both families **degraded** on AppKit — warn once, render the
  view unmodified — and UIKit had `GeometricEffects` only. Degrading was a real
  improvement over the `fatalError` it replaced on 2026-09-01, and it was still
  the wrong answer: it produces a truthful report of a missing feature, which
  looks exactly like a working feature in a screenshot.
- **AppKit `VisualEffects`**: one `CIFilter` chain on a layer-backed container.
  `CIColorControls` carries saturation, brightness and contrast together;
  grayscale is a separate `CIColorMonochrome` so it can land halfway and does
  not fight `.saturation`; hue is `CIHueAdjust` in radians. Opacity goes through
  `alphaValue`, not a filter, so the subtree composites as a group the way
  SwiftUI's `.opacity` does. Measured against P39: **all nine cells render and
  every effect is visibly distinct from the control.**
- One trap worth recording because it looks like a rendering failure rather than
  a configuration one: `layerUsesCoreImageFilters` set unconditionally blanked
  **every** cell, the identity control included. It is now set only when there
  is a filter to run.
- **iOS `VisualEffects` is not the same implementation, and the measurement that
  forced the difference is still true.** `CALayer.filters` does not composite on
  iOS. The property is in the headers on both platforms and only the AppKit
  compositor reads it. Measured twice on the iPhone 16 simulator rather than
  looked up: `opacity 0.35` was visibly faded, and `blur 3`, `saturation 2.5`,
  `brightness 0.4`, `grayscale 1` and `hueRotation 120` were **pixel-identical**
  to the control. One of seven.
- What was wrong was the conclusion drawn from that measurement — *therefore six
  of the seven have no path on iOS* — not the measurement. The route iOS does
  offer is to filter a **rendering** of the subtree instead of the live layer:
  `CALayer.render(in:)` into a bitmap, the `CIFilter` chain over the bitmap, the
  result as the contents of a layer laid over the child, and the child hidden by
  an **empty `CALayer` mask** rather than by `alpha` or `isHidden` — `UIView.hitTest`
  skips a view at or below alpha 0.01, and both properties live on the layer, so
  there is no way to set them for drawing only. The child stays hit-testable.
- Measured on P39, iPhone 16 simulator, iOS 18.4: **all nine cells now differ
  from the control.** Captures `p39-ios-final-20260902-143209.png` and
  `p39-ios-final-20260902-144424.png`.
- The cost is stated rather than hidden: the visible pixels are a rendering
  refreshed on every layout — which is every time the view graph writes a size
  or a position, so a state change inside a filtered container does reach the
  screen — but an animation driven by Core Animation rather than by the view
  graph would freeze at the last frame a layout caught. `opacity` does not take
  this path and stays live.
- **"This platform has no API for this" survived a real measurement here and was
  still wrong.** That is the durable finding; `bugs/bug-UIkit.md` keeps it.
- **`GeometricEffects` on both.** AppKit's is a `CATransform3D` with two
  conversions: the transform arrives top-left and y-down, a `CALayer` under a
  non-flipped `NSView` is bottom-left and y-up, and CoreAnimation applies the
  transform about `anchorPoint` rather than about the origin. UIKit needs one
  fewer, its layer already being top-left and y-down, and the same anchor
  correction.
- Measured against P40 on the Mac: offset moves right and down, rotation is
  clockwise, and **`rotate 30 centre` and `rotate 30 topLeading` differ** —
  which is the check that the anchor arithmetic is right, because a wrong one
  makes those two identical or throws the tile off screen. Measured on P40 on
  the iPhone 16 simulator: **all seven cells render correctly.** Captures
  `p40-ios-final-20260902-143258.png` and `p40-ios-final-20260902-143444.png`.
- Both containers pin their child on all four edges, and it took two wrong
  guesses to find. With no constraints every cell was blank; with left and top
  they were still blank; the probe read `container=(0,0,200,109)` against
  `child=(0,109,0,0)` with zero child constraints. The modifier's commit sizes
  the container and nothing sizes what is inside it — invisible on GTK, where a
  container sizes its child.
- **Android has since been measured, and this entry was stale.**
  `matrix_coverage/results.csv2` does hold P39 and P40 rows on AndroidBackend,
  recorded 2026-09-03, and both were driven again on 2026-09-06 with their
  action files. Both apps build, launch, replay and render; both have content
  wider than the phone -- P39's box is (-325,0)-(1407,2400) and P40's is
  (-320,0)-(1402,2400) -- which was unreachable until the root scroll host was
  fixed, and is why their earlier captures looked cut off at both edges.
  Neither action file expects a visible change: each presses one cell and
  requires the process to survive.

#### P43 gradient fills on macOS and iOS

- `BackendFeatures.Paths.renderPath(…fillStyle:)` fills or strokes a shape
  **with** a gradient instead of flattening it to the midpoint stop. The unit
  points multiply the **path's** own extents, not the widget's, which is what
  lets a gradient be clipped to a circle rather than filling the rectangle the
  gradient views own.
- The protocol's default flattens and warns once per backend. That default was
  written on a machine with no Mac and says so; implementing AppKit and UIKit
  blind would have landed as a build break for whoever pulled next. These two
  were **written and measured on a Mac**.
- Both draw in `draw(_:)` with `CGGradient`, which takes both radii. The flat
  case keeps its existing cheap path untouched. `CAShapeLayer` cannot paint a
  gradient and has no property for one, and the usual masked-`CAGradientLayer`
  workaround cannot express this feature at all: its `.radial` type is an
  ellipse between two points with no start radius, so
  `radialGradient(startRadius:endRadius:)` is unsayable.
- **The two files differ in exactly one sign, and it is forced rather than
  chosen.** AppKit's path arrives already y-flipped — `applyActions` ends with a
  `scaleByX: 1, byY: -1` and `NSBezierPathView` is not flipped — so
  `UnitPoint.top` is the **largest** y there and the **smallest** y in UIKit.
  P43's ramp runs red to blue top to bottom, which is what makes the sign
  visible: red must be at the top on both. A symmetric gradient would have
  hidden it.
- AppKit also needed an `NSBezierPath`-to-`CGPath` conversion, because clipping
  to a stroked region means `CGContext.replacePathWithStrokedPath` and
  `NSBezierPath.cgPath` is macOS 14 while this package deploys to macOS 11.
- Measured with P43 on both platforms, all four cells: **the gradient circle is
  round and not square, the flat control is unchanged, the rectangle runs red to
  blue, and the stroked circle is a ring with an empty middle** — the last being
  the case P43 notes no backend was testing, GtkBackend included. Captures
  `p43-macos-gradient-fills.png` and `p43-ios-gradient-fills.png`.
- **AndroidBackend implements it too, and this entry was stale.**
  `Sources/AndroidBackend/AndroidBackend+PathGradients.swift` overrides
  `renderPath(…fillStyle:)`; it no longer takes the flattening default. Measured
  on `p43-android-final-20260906-022713.png`: 9,885 red and 14,959 blue pixels
  in the gradient shapes, beside 19,410 green in the flat control. A flattened
  fill would have been one colour per shape and no ramp at all.

#### NavigationSplitView on iPhone

- `UISplitViewController` collapses to a navigation stack on a compact-width
  iPhone regardless of `preferredDisplayMode`; there is no configuration that
  places a sidebar beside a detail pane. `PhoneSplitWidget` is therefore not a
  wrapper around it — it lays the two panes out side by side, which is what
  `NavigationSplitView` means and what every other backend produces.
- The width is **derived, not stored**: `sidebarWidth` has to answer during
  `computeLayout`, before any layout pass has run, so it is computed from the
  `width` that `setSize(of:)` just wrote, which is the same number
  `layoutSubviews` will use.

### 2026-09-03

#### P16: the `.defaultSize` shortfall is GtkBackend's, not WSLg's

- Regenerate any number here with `SCUI_DEBUG_SPLIT=1 zsh testapp/run.zsh P16`,
  then read `splitview-debug.log` **in the repo root**.
- **The 39px content shortfall reproduces on GTK for Windows (gvsbuild).** P16
  asks for `.defaultSize(900, 600)` and logs three passes:
  `leadingContent=200.0x480.0`, again `200.0x480.0`, then `200.0x441.0`. The
  drop is **39** — the identical number WSLg gave on 2026-09-01 (485 then 446).
  WinUI/Windows reports a steady **486** in one pass with no correction.
- **This retires the WSLg framing.** Everything written on 2026-09-01, in this
  file and in `bugs/Gtk4-bugs.md` §5, described the shortfall as something
  measured on WSLg, which reads as a platform property. It is a `GtkBackend`
  property: client-side decorations put the header bar inside the window on both
  platforms. The absolute heights differ (480/441 against 485/446) only because
  the two window systems put different amounts of decoration *around* the
  surface.
- **It also means the fix has not been shown to work.** `correctContentSizeIfNeeded`
  is in `Sources/GtkBackend/GtkBackend.swift` and is called from `updateWindow`,
  so the code is present in the tree that produced these numbers, yet the drop
  is still there. The `todo.md` item is open, and the 2026-09-01 line claiming
  it "is now fixed" is annotated above rather than deleted, because a fix that
  was written and then assumed to work is the exact shape worth keeping visible.
- **Upgraded 2026-09-04 from "not shown to work" to "shown not to work."** A
  read-back was added after the correction, so there is now an *after* value and
  not only a *before* one:

  ```
  content size: requested 900x600 allocated 900x561 shortfall 0x39
  content size: grew the window to 900x639
  content size after correction (+250ms):  allocated 900x561 shortfall 0x39
  content size after correction (+1500ms): allocated 900x561 shortfall 0x39
  ```

  Two delays on purpose: one late reading cannot separate "the correction did
  nothing" from "the correction worked and I measured too early", because both
  print the old number. A timing artefact would give two *different* numbers.
  The same number twice means the assignment is a no-op.

  It hid for three days because the reading and the correction sat inside one
  once-only guard, so *ran* and *worked* printed identically. The cause is in
  the same file as the fix: `setSizeLimits` already documents that a size
  request on the toplevel is only a launch hint once the window is realised, and
  `gtk_window_set_default_size` is the same kind of hint. The correction runs
  after the window is mapped by construction — the shortfall cannot be measured
  before then — so **the one moment it can measure is the one moment it can no
  longer act.** See `bugs/Gtk4-bugs.md` section 5 and task #79.
- **Frame sizes, for the same requests, are constant per backend and differ
  between backends** — so comparing frames across backends says nothing about
  who honoured the request:

  | app | `.defaultSize` | gtk4 frame | WinUI frame |
  |---|---|---|---|
  | P31 | 780x560 | 808x589 (+28/+29) | 796x599 (+16/+39) |
  | P16 | 900x600 | 928x629 (+28/+29) | 916x639 (+16/+39) |

  WinUI's +16/+39 is Windows non-client area drawn *around* a client of exactly
  the requested size. WinUI honours the request; a larger frame is not a
  shortfall.

#### P31 on Windows/GtkBackend: Tab and Space work, Escape cannot be tested

- Driven by `testapp/actions/win/P31-tab-and-escape.csv`, a new file. Regenerate
  with `zsh testapp/run.zsh P31 -actionfile testapp/actions/win/P31-tab-and-escape.csv`
  and read `p31-debug-events.log` **in the directory you ran it from**.
- **Focus moves and Space activates.** `key tab` out of the `TextField` followed
  by `key space` produced `button clicked count=1`. SwiftCrossUI has no focus
  API — no `@FocusState`, no `.focused`, no `.focusable` — so this is entirely
  GTK-on-Windows behaviour, and it is a genuine positive for the focus half of
  the SwiftUI-parity focus/keyboard task. Steps 1 and 2 of the P31 plan are now
  measured rather than assumed.
- **Escape did not dismiss the alert, and that is not a P31 result.** The key
  never reached the dialog: `Win32Synthesiser.ownWindow()` returns the
  largest-area visible top-level window of the process, a `Gtk.MessageDialog` is
  a smaller separate top-level window, and `SetForegroundWindow` on the main
  window then pulls focus off the modal. Written up as `bugs/Gtk4-bugs.md` §6.
  Nothing can currently be tested inside a dialog from an action file.
- **Escape is not a portable dismissal.** `testapp/actions/mac/README.md`
  recommends it because "it reaches a key window without a coordinate". True on
  macOS, false on Windows. Both READMEs now say so.

#### Where the Pn debug logs actually land

- **Every `testapp/P*.swift` that writes a debug log writes it to the current
  working directory**, via `FileManager.default.currentDirectoryPath`. **38 of
  the 49** do; the other 11 write no log. `splitview-debug.log` is the same
  (`Sources/SwiftCrossUI/Views/SplitView.swift:215`). Re-derive with
  `grep -l currentDirectoryPath testapp/P*.swift | wc -l`.

  Corrected 2026-09-07, from "35 of the 47", and so was the command beside it:
  `grep -c` prints one count per file, so it never produced the total it was
  offered as the derivation of. A regeneration command that does not regenerate
  the number is worse than none, because it looks checkable.
- So there is **one** convention, not two. Docs that name
  `testapp/output/p28-debug-events.log` are right only because that flow `cd`s
  into `testapp/output` first; `testapp/run.zsh` launches by absolute path and
  never changes directory, so anything driven through it leaves its log at the
  repo root. Following a doc that names `testapp/output/` after a `run.zsh`
  launch means looking in an empty directory and reading it as "the app logged
  nothing".

