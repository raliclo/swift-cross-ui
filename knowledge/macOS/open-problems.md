# macOS: known limits and open problems

Each item is still open. The date is when it was last checked; re-check
before relying on it.

| Item | Backend | Last checked | State |
| --- | --- | --- | --- |
| `P6-transport-toggles` captures no frame on Macs without `~/proj/LZFSE2/swift_tar/images`, the stream P6 autoplays; the render marker never comes and the only capture is `-timeout-`. The replay itself completes | AppKit | 2026-10-15 | handed to the M4, where the folder exists (queue item 16) |
| First frame-clock tick about 0.15 s after `onAppear` (limit 0.1 s): the first Pango text measurement creates a font map, 82-90 ms on the main thread. A background warm-up with its own font map did not help (the cost is per font map) | GTK | 2026-10-20 | open, nothing changed (results.csv2: mac, gtk4, P97) |
| P97 `speed(2)` logs `jumps 1` because the first tick came at 0.42 s | GTK | 2026-10-22 | noted |
| P106 PHASE: one of three runs 23.0 ms from the line where the header allows 17 ms (one frame) | GTK | 2026-10-19 | open; the path (`phaseAnimator`, `.animation(value:)`) was not touched by the change being tested |
| One P105 run took 14.7 s with 4 frames for its first step (the GTK frame clock started late for the app's first animation); the other complete run took 1.03 s | GTK | 2026-10-19 | not reproduced, cause unknown |
| A pointer entering the first popover-menu item while GTK already holds it as the active item is not seen as a selection | GTK | 2026-10-19 | open (queue item 24a) |
| Touch-hold hover measured only with the mouse standing in for a finger; no real `GDK_TOUCH_*` sequence on a Mac | GTK | 2026-10-15 | open, needs a touch screen |
| System Events `set size` is undone on every second resize by GDK 4.24.1 (`gtk4-widget-factory` shows it); this tree's apps followed every resize on re-test | GTK | 2026-10-20 | upstream behaviour; resize by dragging (`measure/drag_at.swift`) |
| `GtkListView` keeps about 200 rows built (P57 205 / 205, 112-150 MB) against AppKit's visible rows (58 MB) | GTK | 2026-10-23 | a GTK constant with no API; accepted |
| What VoiceOver says has never been recorded; only the AX tree is checked | AppKit | 2026-10-24 | open |
| Conic-gradient fallback below macOS 14 and the 60 Hz timer frame clock below macOS 14 never run | AppKit | 2026-10-24 | unexercised |
| `scale_change_mac.zsh` verified only on a Mac whose screen is itself a headless virtual display | AppKit | 2026-09-30 | behaviour with a physical display unrecorded |

Superseded, kept so they are not reopened by mistake:

- "AppKit's list ignores the wheel" (queue M6) was an inverted delta and a
  fallback that cancelled it in AppKitSynthesiser (bb2be624, 2026-09-17).
- "P21's ToggleSwitch stays false" was the correct result: the switch starts
  on (mistakes.md, 2026-09-27).
- "Magnify and rotate cannot be synthesised": they arrive as HID gesture
  events (P65, 2026-09-30).

---

# macOS:已知限制與未解問題

每一項都仍未解決。日期是最後一次檢查的日子；依賴之前請重新確認。

| 項目 | Backend | 最後檢查 | 狀態 |
| --- | --- | --- | --- |
| 在沒有 `~/proj/LZFSE2/swift_tar/images`(P6 自動播放的串流)的 Mac 上,`P6-transport-toggles` 拍不到任何一幀;算繪 marker 永遠不來，唯一的擷圖是 `-timeout-`。重放本身會完成 | AppKit | 2026-10-15 | 已交給有該資料夾的 M4(queue 第 16 項) |
| 第一次 frame clock tick 在 `onAppear` 之後約 0.15 秒(上限 0.1 秒):第一次 Pango 文字量測會建立 font map,在主執行緒上花 82–90 ms。用背景執行緒和它自己的 font map 預熱沒有幫助(成本是每個 font map 一次) | GTK | 2026-10-20 | 未解，程式未改(results.csv2:mac、gtk4、P97) |
| P97 的 `speed(2)` 記下 `jumps 1`,因為第一次 tick 在 0.42 秒 | GTK | 2026-10-22 | 已記錄 |
| P106 PHASE:三次執行中有一次離基準線 23.0 ms,檔頭允許 17 ms(一幀) | GTK | 2026-10-19 | 未解;受測的改動沒有碰到這條路徑(`phaseAnimator`、`.animation(value:)`) |
| 有一次 P105 第一步花了 14.7 秒、只有 4 幀(該 app 第一個動畫的 GTK frame clock 晚啟動);另一次完整執行是 1.03 秒 | GTK | 2026-10-19 | 未重現，原因不明 |
| 當 GTK 已把 popover 選單第一項視為作用中項目時，指標移入該項不會被當成選取 | GTK | 2026-10-19 | 未解(queue 第 24a 項) |
| 按住懸停只用滑鼠代替手指量過;Mac 上沒有真正的 `GDK_TOUCH_*` 序列 | GTK | 2026-10-15 | 未解，需要觸控螢幕 |
| 以 System Events `set size` 改大小，每隔一次就被 GDK 4.24.1 復原(`gtk4-widget-factory` 可重現);本樹的 app 重測時每次都跟上 | GTK | 2026-10-20 | 上游行為;改大小請用拖曳(`measure/drag_at.swift`) |
| `GtkListView` 會保留約 200 列已建好(P57 205 / 205,112–150 MB),AppKit 只建可見的列(58 MB) | GTK | 2026-10-23 | GTK 的常數，沒有 API;已接受 |
| 從未記錄 VoiceOver 實際唸什麼;只檢查 AX 樹 | AppKit | 2026-10-24 | 未解 |
| macOS 14 以下的 conic 漸層 fallback 與 60 Hz 計時器 frame clock 從未跑過 | AppKit | 2026-10-24 | 未驗證 |
| `scale_change_mac.zsh` 只在螢幕本身就是 headless 虛擬螢幕的 Mac 上驗證過 | AppKit | 2026-09-30 | 接實體螢幕時的行為沒有紀錄 |

已被推翻、留著以免誤開的項目:

- 「AppKit 的清單不理滾輪」(queue M6)其實是 AppKitSynthesiser 的位移量正負號反了，加上一個把它抵銷掉的 fallback
  (bb2be624,2026-09-17)。
- 「P21 的 ToggleSwitch 一直是 false」是正確結果：開關一開始就是開的(mistakes.md,2026-09-27)。
- 「放大與旋轉無法合成」:它們以 HID 手勢事件送達(P65,2026-09-30)。
