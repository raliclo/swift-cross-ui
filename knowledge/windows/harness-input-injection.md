# Input injection on Windows: Win32Synthesiser, SetCursorPos and SendInput

Written 2026-10-24 from Sources/InputEvent/Win32Synthesiser.swift,
testapp/enable_input.zsh, testapp/P0-P26-windows-findings.md, commits d6e35a15,
eeb20c6a, 9ab71bd8, 27449b63, and results.csv2 (windows: P80 2026-10-07; P88,
P92, P108 2026-10-19 to 2026-10-21; P65 2026-09-17).

## How replay works

An app built with `SCUI_DEBUG=1` replays its own `-actionfile` on a background
queue, about 1 s after launch, with `SetCursorPos`/`SendInput` in its own
process (a process spawn costs ~43 ms on Windows, so no external tool per event).

- `prepareForReplay` restores the window, pins it with
  `SetWindowPos(HWND_TOPMOST, SWP_NOACTIVATE)` and tries the foreground.
  `SetForegroundWindow` is refused to a process launched from a background shell
  (d6e35a15), so a mouse-only file runs on the topmost pin alone. A file with
  key rows also tries `AttachThreadInput` and throws `windowNotForeground` if the
  window still is not in front.
- When a `focus` row changes the window, the new window is pinned. The pin hides
  native modal dialogs opened behind it (file pickers) and makes `.topmost()`
  unmeasurable during replay. `finishReplay` un-pins every window.

## Mouse

- **A `SetCursorPos` jump is not pointer motion to WinUI**: no `PointerMoved`,
  so hover never fired (P88) and menu items were not chosen (P92). On a
  `WinUIDesktopWin32WindowClass` window a buttonless move is ten stepped
  `SendInput` moves 10 ms apart (eeb20c6a, 2026-10-21). On GTK it stays
  `SetCursorPos`: stepped moves broke P92's GTK menu.
- The `hover` verb moves in ten steps 15 ms apart and waits up to 2 s for
  `GetCursorInfo` to change (9ab71bd8).
- While a button is held, a move is one absolute `SendInput`; a `SetCursorPos`
  move dragged nothing (P108). The synthesiser keeps the pressed window while a
  button is held: re-enumerating windows per move made points arrive 65 ms apart,
  too slow for a 0.1 s velocity window (now 31-39 ms).
- `GetCursorPos` after the move is the verdict, never a return value.
- Target choice skips GTK's `GdkWin32GL` content layer, a WinUI
  `PopupWindowSiteBridge`, and judges "covered by another app" by the root
  ancestor (WebView2's `Chrome_RenderWidgetHostHWND` is parented into ours).
- Clicks are physical events routed by cursor position, never posted to a
  chosen window.

## Keys

A printable key outside a chord is `KEYEVENTF_UNICODE` (arrives as `VK_PACKET`;
GTK needed 27449b63 to see it). Chords and named keys use VK plus scan code. The
replay tracks held keys itself (Narrator swallows Caps Lock); Win is released
with VK 0xE8 masking so the Start menu does not open.

## When injection is refused

`SendInput` fails with status 5 (`ERROR_ACCESS_DENIED`) or `SetCursorPos`
returns false with `GetLastError` 0, while captures keep working. Causes seen:

- a locked workstation (it locks itself; whole hours were lost);
- an elevated window in front (UIPI): `AsMonitorControl.exe`, `AsHotplugCtrl.exe`,
  `AsusUpdater.exe`, `GameInputSvc.exe` (a service that restarts within 1 s, so
  `sc stop`). `enable_input.zsh` stops them; test.zsh gates on it;
- a stray window of another test app in front (P80, 2026-10-07);
- **no live session**: on 2026-09-17 touch and mouse injection was accepted and
  delivered nowhere until a remote-desktop viewer was connected. A display that
  is off also cut P100 from 147 frames to 36 (2026-10-20).

Chrome Remote Desktop (`remoting_host.exe`) is reported, never stopped; it is a
suspect, not a proven cause. Open: the disconnect experiment (2026-10-24).

## Limits

- Not drivable by SendInput: OLE drag and drop (P25), a live display-scale
  change (use `SPI_SETLOGICALDPIOVERRIDE`).
- `Sources/InputEvent/README.md` still says `hover` is not implemented on
  Windows; it is.
- Open: `prepareForReplay` calls `forgetFocus()` again when a `focus` row
  changes the window mid-file; XdotoolSynthesiser moved its reset to
  `finishReplay` for that reason (83196598). Unverified on Win32.

---

# Windows 上的輸入注入:Win32Synthesiser、SetCursorPos 與 SendInput

2026-10-24 依 Sources/InputEvent/Win32Synthesiser.swift、testapp/enable_input.zsh、
testapp/P0-P26-windows-findings.md、d6e35a15、eeb20c6a、9ab71bd8、27449b63,以及 results.csv2(windows:P80
2026-10-07;P88、P92、P108 於 2026-10-19 至 2026-10-21;P65 2026-09-17)寫成。

## 重放如何運作

以 `SCUI_DEBUG=1` 建置的 app 在啟動約 1 秒後，於背景佇列重放自己的 `-actionfile`,在自己的行程內呼叫
`SetCursorPos`/`SendInput`(Windows 上開一個行程約 43 ms,所以不為每個事件呼叫外部工具)。

- `prepareForReplay` 還原視窗、以 `SetWindowPos(HWND_TOPMOST, SWP_NOACTIVATE)` 釘在最上層，並嘗試取得前景。
  背景 shell 啟動的行程會被拒絕 `SetForegroundWindow`(d6e35a15),所以純滑鼠的檔案只靠置頂釘選執行。含按鍵列的
  檔案還會嘗試 `AttachThreadInput`,若視窗仍不在前景就拋出 `windowNotForeground`。
- `focus` 列換視窗時，新視窗會被釘住。釘選會把在它後面開啟的原生 modal 對話框(檔案選擇器)藏起來，也讓
  `.topmost()` 在重放期間無法量測。`finishReplay` 解除所有視窗的釘選。

## 滑鼠

- **`SetCursorPos` 的跳躍對 WinUI 不是指標移動**:沒有 `PointerMoved`,所以 hover 從不觸發(P88),選單項目也
  選不到(P92)。在 `WinUIDesktopWin32WindowClass` 視窗上，沒按鍵的移動改為十段、間隔 10 ms 的 `SendInput`
  (eeb20c6a,2026-10-21)。GTK 上維持 `SetCursorPos`:分段移動弄壞了 P92 的 GTK 選單。
- `hover` 動詞分十段、間隔 15 ms 移動，並最多等 2 秒讓 `GetCursorInfo` 改變(9ab71bd8)。
- 按住按鍵時，移動是一次絕對座標的 `SendInput`;`SetCursorPos` 的移動拖不動任何東西(P108)。按住期間合成器保留
  按下時的視窗：每次移動都重新列舉視窗，使各點相隔 65 ms 到達，對 0.1 秒的速度計算窗太慢(現為 31–39 ms)。
- 移動後以 `GetCursorPos` 判定，從不看回傳值。
- 選目標時略過 GTK 的 `GdkWin32GL` 內容層、WinUI 的 `PopupWindowSiteBridge`,並以根祖先判斷「被其他 app 蓋住」
  (WebView2 的 `Chrome_RenderWidgetHostHWND` 掛在我們的視窗底下)。
- 點擊是依游標位置路由的實體事件，從不投遞到指定的視窗。

## 按鍵

不屬於組合鍵的可列印字元以 `KEYEVENTF_UNICODE` 送出(以 `VK_PACKET` 到達;GTK 要到 27449b63 才看得到)。組合鍵與
具名按鍵用 VK 加 scan code。重放自己追蹤按住的鍵(Narrator 會吞掉 Caps Lock);放開 Win 時以 VK 0xE8 遮蔽，避免
開啟開始功能表。

## 注入被拒絕時

`SendInput` 以 status 5(`ERROR_ACCESS_DENIED`)失敗，或 `SetCursorPos` 回傳 false 且 `GetLastError` 為 0,而擷取
照常運作。看過的原因:

- 工作站已鎖定(它會自己鎖；曾整整損失數小時);
- 前景有提權的視窗(UIPI):`AsMonitorControl.exe`、`AsHotplugCtrl.exe`、`AsusUpdater.exe`、`GameInputSvc.exe`
  (服務，1 秒內會重啟，所以要 `sc stop`)。`enable_input.zsh` 會停止它們;test.zsh 以它為閘門;
- 前景有另一支測試 app 殘留的視窗(P80,2026-10-07);
- **沒有活著的工作階段**:2026-09-17 觸控與滑鼠注入都被 API 接受，卻哪裡都沒送到，直到連上遠端桌面檢視端為止。
  螢幕關閉也讓 P100 從 147 幀降到 36 幀(2026-10-20)。

Chrome 遠端桌面(`remoting_host.exe`)只回報、從不停止；它是嫌疑，不是已證實的原因。未解決：中斷連線的實驗
(2026-10-24)。

## 限制

- SendInput 驅動不了:OLE 拖放(P25)、執行中改變顯示縮放(改用 `SPI_SETLOGICALDPIOVERRIDE`)。
- `Sources/InputEvent/README.md` 仍說 Windows 上未實作 `hover`;其實已實作。
- 未解決:`focus` 列在檔案中途換視窗時,`prepareForReplay` 會再呼叫一次 `forgetFocus()`;XdotoolSynthesiser 正是
  為此把重設移到 `finishReplay`(83196598)。Win32 上未驗證。
