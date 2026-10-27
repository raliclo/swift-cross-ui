# GtkBackend on Windows: scale, windows, popovers, single instance

Written 2026-10-24 from Sources/GtkCHelpers/gtk_window_scale.c,
Sources/GtkBackend/GtkBackend.swift, testapp/P0-P26-windows-findings.md, commits
85942e99, 3ee6ecaa, 7bec9284, and results.csv2 (windows, gtk4: P42 2026-09-16 and
2026-10-20, P61 2026-09-16, P95 2026-10-21, P50 2026-09-17).

## Scale: GTK says 1, Win32 says 1.25

- At 125% GDK reports an **integer scale of 1** (`gtk_widget_get_scale_factor`,
  `gdk_surface_get_scale`). One GTK layout unit is one physical pixel, so a GTK
  window is not enlarged as a WinUI one is. `GDK_SCALE` is ignored on Windows.
- `windowScaleFactor` comes from Win32 instead: `scui_window_display_scale()`
  calls `GetDpiForWindow` (85942e99, 2026-09-16; 0 before the window is
  realized).
- GtkBackend sets `GDK_WIN32_PER_MONITOR_HIDPI=1` unless already set. Without it
  the process is system-DPI-aware and the value freezes at launch.
- A live change 125% -> 150% -> 125% (`SPI_SETLOGICALDPIOVERRIDE`) reached the
  core as 1.25 -> 1.5 -> 1.25 (P42, 2026-10-20, b75b9ed0).
- Action-file replay still gets GTK's integer as its layout scale, because
  every `actions/win/*-gtk4.actions` coordinate was measured against it; see
  [action-files.md](action-files.md).
- Open: how GTK content should look at fractional scales (it is drawn 1:1).
  Last checked 2026-10-23 (P12/P14 "match macOS GTK apart from chrome and scale").

## Popovers are top-level windows

A `GtkPopover` or popover menu is its own owned top-level HWND, titled with the
exe name. Consequences:

- A window capture of the app does not contain it. Judge menus by a desktop
  capture.
- The screen, not the parent window, constrains its placement.
- With the gvsbuild runtime it exposes nothing to UIA; action-file rows inside
  it use `origin=popover` or positions from a desktop capture (P19, P92).
- Clicks inside it work (P50, 2026-09-17).
- The DComp GL content layer (`GdkWin32GL`) is a separate HWND too; the
  synthesiser skips it when choosing a target (2026-10-21).

## Single-instance handoff

GApplication is single-instance per app ID. A SwiftPM exe has no metadata, so
every test app gets `com.example.SwiftCrossUIApp`. A second app started while
another runs hands its arguments over and **exits 0 with an empty log**, which
looks exactly like an app that drew nothing. Kill every `P*.exe` before a
launch (test.zsh and window_sizes.zsh do), or set `SCUI_GTK_APP_ID` (an
environment variable read in `GtkBackend.init`) to run two at once.

Since 7bec9284, `g_application_run` gets argv[0] plus URL arguments, so a
launch with a URL reaches the app (P78 "received 2").

## Window size

- The 39 px header-bar shortfall (#79) is fixed by measuring a real
  `GtkHeaderBar` (`probeGtkOwnDecorationHeight`); P61 shortfall 0x0 (2026-09-16).
- **A mapped window never shrank:** GDK Win32 `request_layout` records the HWND
  size as configured and takes `MAX(minimum, configured)`. `GtkBackend.setSize`
  now re-presents the window when the request is smaller (3ee6ecaa, 2026-10-21).
- `.floating` window level works through `SetWindowPos` (`gtk_window_level.c`).
  A window level must not be re-applied on every layout pass: a re-applied
  `HWND_NOTOPMOST` undid the replay's topmost pin (fixed in `WindowReference`).

---

# Windows 上的 GtkBackend:縮放、視窗、popover、單一實例

2026-10-24 依 Sources/GtkCHelpers/gtk_window_scale.c、Sources/GtkBackend/GtkBackend.swift、
testapp/P0-P26-windows-findings.md、85942e99、3ee6ecaa、7bec9284,以及 results.csv2(windows、gtk4:P42
2026-09-16 與 2026-10-20、P61 2026-09-16、P95 2026-10-21、P50 2026-09-17)寫成。

## 縮放:GTK 說 1,Win32 說 1.25

- 在 125% 時 GDK 回報**整數縮放 1**(`gtk_widget_get_scale_factor`、`gdk_surface_get_scale`)。一個 GTK 版面
  單位等於一個實體像素，所以 GTK 視窗不會像 WinUI 那樣被放大。Windows 上 `GDK_SCALE` 無效。
- `windowScaleFactor` 改取自 Win32:`scui_window_display_scale()` 呼叫 `GetDpiForWindow`(85942e99,
  2026-09-16;視窗 realize 前為 0)。
- GtkBackend 會設定 `GDK_WIN32_PER_MONITOR_HIDPI=1`(已設定則不覆寫)。少了它，行程是 system DPI aware,數值在
  啟動時就固定。
- 執行中把縮放由 125% 改為 150% 再改回 125%(`SPI_SETLOGICALDPIOVERRIDE`),核心收到 1.25 -> 1.5 -> 1.25
  (P42,2026-10-20,b75b9ed0)。
- 動作檔重放仍以 GTK 的整數作為版面縮放，因為每個 `actions/win/*-gtk4.actions` 的座標都是以它量的；見
  [action-files.md](action-files.md)。
- 未解決：分數縮放下 GTK 內容應如何呈現(目前 1:1 繪製)。最後檢查 2026-10-23(P12/P14「除視窗外框與縮放外與
  macOS GTK 相同」)。

## popover 是 top-level 視窗

`GtkPopover` 或 popover 選單是自己的、有 owner 的 top-level HWND,標題是 exe 名稱。後果:

- app 的視窗擷取不包含它。判斷選單請看桌面擷取。
- 限制它擺放位置的是螢幕，不是父視窗。
- 使用 gvsbuild runtime 時它對 UIA 不暴露任何東西；落在它裡面的動作檔列使用 `origin=popover`,或取自桌面擷取的
  位置(P19、P92)。
- 在它裡面點擊是有效的(P50,2026-09-17)。
- DComp 的 GL 內容層(`GdkWin32GL`)也是獨立的 HWND;合成器選目標時會略過它(2026-10-21)。

## 單一實例交接

GApplication 以 app ID 為單位只允許一個實例。SwiftPM exe 沒有中繼資料，所以每支測試 app 都是
`com.example.SwiftCrossUIApp`。在另一支執行中時啟動的第二支會把引數交出去，然後**以 0 結束、log 是空的**,看起來
與「什麼都沒畫的 app」一模一樣。每次啟動前先 kill 所有 `P*.exe`(test.zsh 與 window_sizes.zsh 都會做),或設定
`SCUI_GTK_APP_ID`(`GtkBackend.init` 讀取的環境變數)以同時執行兩支。

自 7bec9284 起,`g_application_run` 會拿到 argv[0] 與 URL 引數，帶 URL 的啟動能送達 app(P78「received 2」)。

## 視窗大小

- header bar 少 39 px 的問題(#79)已修正，改為量測真正的 `GtkHeaderBar`(`probeGtkOwnDecorationHeight`);
  P61 差值 0x0(2026-09-16)。
- **已 map 的視窗從不縮小:**GDK Win32 的 `request_layout` 把 HWND 大小記成已設定值，再取
  `MAX(minimum, configured)`。`GtkBackend.setSize` 現在在要求較小時重新 present 視窗(3ee6ecaa,2026-10-21)。
- `.floating` 視窗層級透過 `SetWindowPos` 運作(`gtk_window_level.c`)。視窗層級不可在每次版面配置都重新套用：
  重新套用的 `HWND_NOTOPMOST` 曾解除重放的置頂釘選(已在 `WindowReference` 修正)。
