# GtkBackend on macOS: platform integration and replay

Behaviour of GtkBackend that exists only on macOS, or differs there, and what a
replay needs to drive it.

## Replay into GDK windows needs the HID tap

`AppKitSynthesiser` normally posts in-process with `NSApp.postEvent`, which
needs no permission. **A posted click reaches GDK but never fires a GtkButton**:
measured 2026-10-09 with P84 on GTK 4.24.1, `GDK_DEBUG=events` logged a
GDK_BUTTON_PRESS and RELEASE, yet nothing fired, with a 150 ms hold, after
warping the real cursor, or at nearby points. One CGEvent through
`.cghidEventTap` at the same point worked. So GDK windows take the HID path
(`AppKitSynthesiser.swift`, beside `isOutOfProcessPanel`), which requires the
Accessibility grant for the terminal running the harness and moves the real
pointer. Without the grant the replay refuses loudly.

- Wheel: GTK scrolls one step per wheel event and AppKit coalesces queued
  scroll events, so notches go out one per event from a background queue
  (244ed158; P22's vadjustment reached 307 then 0).
- Magnify and rotate are HID gesture events; GDK reads the queue itself, so
  draining it in the synthesiser lost them (P65, 2026-10-16).
- **Sheets and popovers.** A GTK sheet on macOS is a titled, key child window
  (GdkMacosWindow, styleMask 0x800F); `AppKitSynthesiser.targetWindow()` takes it
  as the replay target. A GTK popover (0x8000, cannot become key) is not
  (results.csv2: mac, gtk4, P49, 2026-10-21).
- **Focus on click is off.** GTK moves keyboard focus to a clicked button,
  toggle or switch; AppKit does not, and P70/P72 read wrong until it was turned
  off (244ed158).

## Window lifetime and size

- **A GTK app quits when its last window closes.** P75-close-the-window ended
  the process and `run_macos` waited 600 s for a replay line nobody printed
  (2026-10-22). The replay now reports at exit
  (`ActionFileReplay.reportIfCutShort`), and `run_macos` stops waiting when
  neither `debugTarget` nor the app process is alive (70e217b0).
- **Resize by dragging, not through System Events.** GDK 4.24.1 can set back a
  size set through System Events (`set size`): GTK answers `compute-size` with a
  default size updated later in the same frame, and GDK restores that stale size.
  `gtk4-widget-factory` undoes every second resize. In this tree's apps it did not
  reproduce on 2026-10-20 (P95 and P53, four resizes, two rounds each, idle,
  loaded and with the Android emulator running), so no workaround is in the code;
  one morning failure on P95 (window 1100x500, drawable 900x448, right part
  unpainted) is recorded in todo.md. Drags with `measure/drag_at.swift` always
  followed (P95: three drags, 80 drawable sizes, circle ratio 1.000-1.002).
- **`.floating` works.** `scui_window_set_topmost` puts the window at
  CGWindowList layer 3 (NSFloatingWindowLevel) (results.csv2: mac, gtk4, P37,
  2026-10-20).

## Integration

- **URLs arrive as Apple events.** Launch Services sends `kAEGetURL`; GTK's
  NSApplication delegate takes files only and dropped them, and GApplication's
  forwarding of a second launch needs a D-Bus session bus, which macOS does not
  run. `GtkBackend+AppleEvents.swift` installs a `kAEGetURL` handler in
  `setIncomingURLHandler` (74596369): in a bundle with `CFBundleURLTypes`,
  `open -a App scui-testapp://launch` then `scui-testapp://running` gave received
  1 and received 2 in one process (P78, results.csv2 2026-10-20).
- **WebView is WKWebView** (`GtkBackend+WebViewMac.swift`), kept as a sibling of
  GDK's view: GDK's content view hosts its own layer, and a subview of a
  layer-hosting view loaded but never showed. GDK passes an NSEvent to
  `NSApp.sendEvent` only when GTK leaves it unhandled, so a focused page lost
  Return; a capture-phase controller on the GTK window rebuilds the NSEvent and
  sends it through NSApp while the page is first responder (d68b40ac; P38
  Navigations reported 2).
- **Graphics adapters from Metal**, system default first, as AppKitBackend
  (`GtkBackend+GraphicsAdapters.swift`; until 2026-10-16 P68 read "adapters: 0").
- **SF Symbols** are drawn through `NSImage(systemSymbolName:)` at the resolved
  font size into a texture (`GtkBackend+Symbols.swift`); before, P47 drew
  truncated names (2026-10-15).
- **Date pickers:** GtkBackend lists `.automatic`, `.graphical`, `.compact` on
  macOS (no native `.wheel`); `.datePickerStyle(.wheel)` is drawn in Swift
  (efa2b093), and time `.rows` are GTK spin buttons.

## Limits

- GtkListView keeps about 200 rows built (P57: 205 built against AppKit's 10,
  112-150 MB against 58 MB); a GTK constant with no API (queue item 31).
- Touch-hold hover (`GtkTouchHold`) was measured on macOS only with the mouse
  standing in for a finger; there is no touch screen (results.csv2: mac, gtk4,
  P88, 2026-10-15).
- GTK sends no motion for a modifier change alone, so "modifier change without
  moving" was not seen on 2026-10-15; the 2026-10-21 run on the M4 read it as
  seen (results.csv2: mac, gtk4, P88). Which holds was not re-checked.

---

# macOS 上的 GtkBackend:平台整合與重放

只存在於 macOS、或在 macOS 上行為不同的 GtkBackend 功能，以及重放驅動它所需的條件。

## 重放到 GDK 視窗要走 HID tap

`AppKitSynthesiser` 平常以 `NSApp.postEvent` 在行程內送事件，不需要權限。**送進來的點擊到得了 GDK,卻從不觸發 GtkButton**:
2026-10-09 以 GTK 4.24.1 上的 P84 實測,`GDK_DEBUG=events` 記到 GDK_BUTTON_PRESS 與 RELEASE,但不論按住 150 ms、先移動
真實游標或改點附近都沒有作用；同一點經 `.cghidEventTap` 送一次 CGEvent 就成功。因此 GDK 視窗走 HID 路徑，需要執行 harness
的終端機具備「輔助使用」權限，並會移動真實指標；沒有權限時重放會明確拒絕。

- 滾輪:GTK 每個滾輪事件捲一步，而 AppKit 會合併排隊中的捲動事件，所以每一格從背景佇列各送一個事件(244ed158)。
- 縮放與旋轉是 HID 手勢事件;GDK 自己讀佇列,synthesiser 先清掉佇列時它們就消失了(P65,2026-10-16)。
- **sheet 與 popover。** macOS 上的 GTK sheet 是有標題、可成為 key 的子視窗(styleMask 0x800F),
  `targetWindow()` 會把它當成重放目標;GTK popover(0x8000,不能成為 key)不會(results.csv2:mac、gtk4、P49、2026-10-21)。
- **點擊不取得焦點。** GTK 會把鍵盤焦點移到被點的按鈕、切換鈕;AppKit 不會。關掉之前 P70/P72 讀數錯誤(244ed158)。

## 視窗的生命週期與大小

- **GTK app 在最後一個視窗關閉時結束。** P75-close-the-window 結束了行程,`run_macos` 為一行沒人會印的字等了 600 秒
  (2026-10-22)。現在重放會在結束時回報,`run_macos` 在 `debugTarget` 與 app 行程都不在時停止等待(70e217b0)。
- **改大小用拖曳，不用 System Events。** GDK 4.24.1 可能把 System Events `set size` 設的大小還原:GTK 回答 `compute-size`
  時用的預設尺寸要到同一幀稍後才更新,GDK 便把過期的大小設回去。`gtk4-widget-factory` 每隔一次就被還原。本樹的 app 在
  2026-10-20 沒有重現(P95 與 P53,各 4 次、2 輪，閒置、滿載、模擬器運作中),所以程式裡沒有繞過；早上一次 P95 失敗記在 todo.md。
  以 `measure/drag_at.swift` 拖曳一直正常(P95:三次拖曳、80 個 drawable 尺寸，圓的比例 1.000–1.002)。
- **`.floating` 可用。** 視窗位於 CGWindowList 第 3 層(results.csv2:mac、gtk4、P37、2026-10-20)。

## 整合

- **URL 以 Apple event 送達。** Launch Services 送 `kAEGetURL`;GTK 的 NSApplication delegate 只收檔案，把它丟了，而
  GApplication 轉送第二次啟動需要 D-Bus session bus,macOS 沒有。`GtkBackend+AppleEvents.swift` 在 `setIncomingURLHandler`
  裝上 `kAEGetURL` handler(74596369):同一個行程收到 received 1 與 received 2(P78,2026-10-20)。
- **WebView 是 WKWebView**,放在 GDK view 的旁邊而非裡面:GDK 的 content view 是 layer-hosting view,加在其下的子 view
  載入了卻不顯示。GDK 只在 GTK 沒處理時才把 NSEvent 交給 `NSApp.sendEvent`,所以取得焦點的網頁收不到 Return;GTK 視窗上的
  capture 階段控制器會在網頁是 first responder 時重建 NSEvent 交給 NSApp(d68b40ac;P38 Navigations reported 2)。
- **GPU 清單取自 Metal**,系統預設排第一，與 AppKitBackend 相同(2026-10-16 前 P68 讀到「adapters: 0」)。
- **SF Symbols** 經 `NSImage(systemSymbolName:)` 以字級畫成材質(`GtkBackend+Symbols.swift`);之前 P47 畫的是被截斷的名稱。
- **日期選擇器：** macOS 上 GtkBackend 列出 `.automatic`、`.graphical`、`.compact`(沒有原生 `.wheel`);`.wheel` 以 Swift
  繪製(efa2b093),時間的 `.rows` 是 GTK spin button。

## 限制

- GtkListView 會保留約 200 列已建好(P57:205 列對 AppKit 10 列,112–150 MB 對 58 MB),是 GTK 的常數、沒有 API(queue 第 31 項)。
- 長按懸停(`GtkTouchHold`)在 macOS 上只以滑鼠代替手指量過，沒有觸控螢幕(results.csv2:mac、gtk4、P88、2026-10-15)。
- GTK 對只改變修飾鍵不送 motion,2026-10-15 讀到「modifier change without moving: not seen」;2026-10-21 在 M4 上讀到 seen。
  哪一個成立未再確認。
