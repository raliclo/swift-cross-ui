# macOS harness: permissions and the state of the desktop

Written 2026-10-24 from testapp/screenshot.zsh, Sources/InputEvent/AppKitSynthesiser.swift,
testapp/sweep_apple.zsh, testapp/sweep-test/measure_macos.zsh,
testapp/actions/mac/P31-focus-and-keyboard.actions and testapp/ui-lock.zsh.

## What each permission gates

Grant both to the program that actually runs the harness (Terminal, iTerm or
the editor), in System Settings > Privacy & Security.

| Permission | Without it |
| --- | --- |
| Screen & System Audio Recording | `screencapture` produces nothing for either priority, and window titles read empty, so `-w` cannot resolve by title. Takes effect without restarting the terminal (measured). |
| Accessibility (`AXIsProcessTrusted`) | No HID-tap events: clicks and keys in open/save panels, every click on a GTK (GDK) window, real wheel events, trackpad magnify/rotate. The replay refuses those rows loudly rather than skipping them. Also needed by System Events: raising a window for the priority-2 capture, reading and pressing menu-bar items, `get size of window 1` in `window_sizes_mac.zsh`. |

The default in-process path (`NSApp.postEvent`) needs neither, so AppKit apps
replay most files on an ungranted machine. See input-synthesis.md.

## Desktop conditions that look like app defects

- **Display asleep**: window capture fails for every window, a whole-screen
  capture returns a black frame with exit 0. `measure_macos.zsh` runs
  `caffeinate -u -t 30` first; `-u` asserts user activity, which wakes it.
- **Locked screen**: same message as a missing permission.
- **Keyboard navigation off** (`AppleKeyboardUIMode`, the macOS default and the
  state of the test Mac): Tab does not move focus to buttons, and Space does not
  press them. P31's Tab/Space rows were removed for that reason (results.csv2:
  2026-09-28, mac, appkit, P31); a file that relies on Tab to a button measures
  the system setting, not the backend.
- **The real pointer moves**: `move` rows warp the physical pointer, and HID
  clicks press whatever window is on top at that point. Do not use the Mac
  during a macOS sweep, and do not run the macOS and iOS sweeps at once: the
  Simulator window can end up over the test app (sweep_apple.zsh header).

## How to apply

- When a capture is missing or black, read screenshot.zsh's message and the
  `captured from` line before suspecting the app.
- When a click "does nothing" on a GTK window or a file panel, check
  `AXIsProcessTrusted` first: those rows need the HID tap.
- One UI test at a time: test.zsh takes `testapp/.ui-lock` itself (60 s retry;
  `SCUI_NO_UI_LOCK=1` skips). Other sessions sharing the Mac (SoftPCB's UI
  tests) get the desktop first; pause between apps.

## Evidence

- Title readability: 0 of 28 untrusted, 22 of 26 trusted (screenshot.zsh).
- Untrusted: `CGEvent.post(tap: .cghidEventTap)` 0 events delivered; trusted:
  an NSButton fired 23.8 ms after the post (AppKitSynthesiser.swift header,
  2026-09-10).
- 2026-08-26: `osascript is not allowed assistive access (-1719)` stopped a
  System Events check (testapp/mac-test-results-2026-08-26.md).

---

# macOS harness:權限與桌面狀態

2026-10-24 依 testapp/screenshot.zsh、Sources/InputEvent/AppKitSynthesiser.swift、testapp/sweep_apple.zsh、
testapp/sweep-test/measure_macos.zsh、testapp/actions/mac/P31-focus-and-keyboard.actions 與 testapp/ui-lock.zsh 寫成。

## 每個權限管什麼

兩個權限都要授予實際執行 harness 的程式(終端機、iTerm 或編輯器),位置在系統設定 > 隱私權與安全性。

| 權限 | 沒有時 |
| --- | --- |
| 螢幕與系統音訊錄製 | 兩個優先序的 `screencapture` 都產不出影像，視窗標題讀起來是空的,`-w` 無法依標題解析。勾選後不必重開終端機就生效(實測)。 |
| 輔助使用(`AXIsProcessTrusted`) | 沒有 HID tap 事件：開啟/儲存面板裡的點擊與按鍵、GTK(GDK)視窗上的每一次點擊、真正的滾輪事件、觸控板縮放/旋轉。重放會明確拒絕這些列，而不是略過。System Events 也需要它：為優先序 2 擷圖把視窗帶到前景、讀取與按下選單列項目、`window_sizes_mac.zsh` 的 `get size of window 1`。 |

預設的行程內路徑(`NSApp.postEvent`)兩者都不需要，所以 AppKit app 在未授權的機器上也能重放多數檔案。見 input-synthesis.md。

## 看起來像 app 缺陷的桌面狀態

- **顯示器休眠**:每個視窗的擷取都失敗，整螢幕擷取以 0 結束並回傳全黑畫面。`measure_macos.zsh` 先執行
  `caffeinate -u -t 30`;`-u` 宣告使用者活動，會喚醒顯示器。
- **螢幕鎖定**:訊息與缺少權限相同。
- **鍵盤導覽關閉**(`AppleKeyboardUIMode`,macOS 預設，測試用 Mac 也是如此):Tab 不會把焦點移到按鈕,Space 也不會按下按鈕。
  P31 的 Tab/Space 列因此移除(results.csv2:2026-09-28、mac、appkit、P31);依賴 Tab 走到按鈕的檔案量到的是系統設定，不是 backend。
- **真實指標會移動**:`move` 列會移動實體指標,HID 點擊會按到該點最上層的視窗。macOS sweep 進行時不要使用這台 Mac,也不要同時跑
  macOS 與 iOS 的 sweep:Simulator 視窗可能蓋到測試 app 上(sweep_apple.zsh 檔頭)。

## 怎麼用

- 擷圖缺漏或全黑時，先讀 screenshot.zsh 的訊息與 `captured from` 那一行，再懷疑 app。
- GTK 視窗或檔案面板上的點擊「沒反應」時，先查 `AXIsProcessTrusted`:那些列需要 HID tap。
- 一次只跑一個 UI 測試:test.zsh 自己取得 `testapp/.ui-lock`(重試 60 秒;`SCUI_NO_UI_LOCK=1` 略過)。共用這台 Mac 的其他 session
  (SoftPCB 的 UI 測試)優先使用桌面；每支 app 之間要停一下。

## 證據

- 標題可讀性：未授權 28 個中 0 個，已授權 26 個中 22 個(screenshot.zsh)。
- 未授權時 `CGEvent.post(tap: .cghidEventTap)` 送達 0 個事件；授權後 NSButton 在送出 23.8 ms 後觸發(AppKitSynthesiser.swift 檔頭,
  2026-09-10)。
- 2026-08-26:`osascript is not allowed assistive access (-1719)` 讓一次 System Events 檢查無法完成(testapp/mac-test-results-2026-08-26.md)。
