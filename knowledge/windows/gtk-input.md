# GtkBackend on Windows: touch, VK_PACKET keys, and a GDK device bug

Written 2026-10-24 from Sources/GtkBackend/GtkBackend+WindowsTouch.swift,
Sources/GtkCHelpers/gtk_device_lifetime.c, commits 80427201, 27449b63, 9dd625ac,
and results.csv2 (windows, gtk4: P88, P91, P94 on 2026-10-23; P11, P65 on 2026-09-17).

## Touch arrives twice

GDK on Windows does receive touch (GDK_TOUCH_BEGIN/UPDATE/END, GTK's long
press). Windows also sends **emulated mouse input** for the same finger. The
emulated motion made a quick touch drag report 23 hovers, and one more move
just after `GDK_TOUCH_END` made the hover active again.

Fix (80427201, 2026-10-23): a thread message hook reads `WM_POINTERDOWN/UP`,
and the motion controller ignores motion while a finger is down and for 0.5 s
after the lift. P88 after: quick drag 0 hovers, 0.8 s hold then move 30 hovers
ending on the lift, 0.3 s hold 0.

An earlier note of the same day said GDK sees no touch on Windows. That was
wrong; `GDK_WIN32_TABLET_INPUT_API=winpointer` only changes pen input.

## VK_PACKET keys

A key sent with `KEYEVENTF_UNICODE` arrives as `VK_PACKET`. The touch keyboard,
the emoji panel and Win32Synthesiser all send printable keys this way. GDK
hands such a key to the key controller as keyval `VoidSymbol`, keycode 231, so
no `onKeyPress` heard it (P91).

Fix (27449b63): `GtkWindowsPacketKeys` reads the `WM_CHAR` of each VK_PACKET
key-down in the thread hook, and the key controller matches it by event time
within 50 ms. A plain queue went one off ("cdy" for "cde"); an exact time
match lost characters, because GDK adds a millisecond to a shared tick.

## GDK device use-after-free (GTK 4.22.4)

After a touch drag, `gdk_device_get_display: assertion 'GDK_IS_DEVICE (device)'`
then a crash: `gdkinput-winpointer.c` frees a touch device still in use.
`gtk_device_lifetime.c` takes an extra reference that is never released
(9dd625ac; 10 of 10 runs alive). Listed in todo-Gtk.md; not reported upstream
(last checked 2026-10-24).

## Other input facts

- GTK on Windows focuses the `TextEditor` at start, so a Tab in an action file
  is typed into it (P94; the file clicks instead).
- The arrow keys in a GTK popover menu start from a different item from run to
  run (queue row 24a, open); P19's GTK file clicks.
- Rotation: GTK's `angle_delta` is normalised to [0, 2π) and y-down, while
  WinUI reports a signed, unbounded angle. GtkBackend unwraps it step by step,
  reset on begin (P65, 2026-09-17).

---

# Windows 上的 GtkBackend:觸控、VK_PACKET 按鍵與 GDK 裝置錯誤

2026-10-24 依 Sources/GtkBackend/GtkBackend+WindowsTouch.swift、Sources/GtkCHelpers/gtk_device_lifetime.c、
80427201、27449b63、9dd625ac,以及 results.csv2(windows、gtk4:P88、P91、P94 於 2026-10-23;P11、P65 於
2026-09-17)寫成。

## 觸控會到兩次

Windows 上的 GDK 確實收得到觸控(GDK_TOUCH_BEGIN/UPDATE/END、GTK 的長按)。Windows 也會為同一根手指送出**模擬的
滑鼠輸入**。模擬的移動讓一次快速觸控拖曳回報 23 次 hover,而 `GDK_TOUCH_END` 之後緊接著的一次移動又讓 hover 重新
啟動。

修正(80427201,2026-10-23):執行緒訊息 hook 讀取 `WM_POINTERDOWN/UP`,手指按著時與放開後 0.5 秒內，motion
controller 忽略移動。修正後的 P88:快速拖曳 0 次 hover,按住 0.8 秒再移動 30 次並於放開時結束，按住 0.3 秒 0 次。

同一天較早的紀錄說 Windows 上 GDK 看不到觸控。那是錯的;`GDK_WIN32_TABLET_INPUT_API=winpointer` 只影響手寫筆。

## VK_PACKET 按鍵

以 `KEYEVENTF_UNICODE` 送出的按鍵會以 `VK_PACKET` 到達。觸控鍵盤、表情符號面板與 Win32Synthesiser 都以這種方式送
可列印字元。GDK 把這種按鍵交給 key controller 時是 keyval `VoidSymbol`、keycode 231,所以沒有任何 `onKeyPress`
收到(P91)。

修正(27449b63):`GtkWindowsPacketKeys` 在執行緒 hook 中讀取每個 VK_PACKET key-down 的 `WM_CHAR`,key
controller 以 50 ms 內的事件時間配對。單純的佇列會錯一個(「cde」變成「cdy」);時間完全相等的比對會漏字，因為
GDK 會在共用的 tick 上加一毫秒。

## GDK 裝置釋放後使用(GTK 4.22.4)

觸控拖曳之後出現 `gdk_device_get_display: assertion 'GDK_IS_DEVICE (device)'`,接著當機:
`gdkinput-winpointer.c` 釋放了仍在使用的觸控裝置。`gtk_device_lifetime.c` 多取一個永不釋放的參照(9dd625ac;
10 次執行 10 次存活)。已列入 todo-Gtk.md;尚未回報上游(最後檢查 2026-10-24)。

## 其他輸入事實

- Windows 上的 GTK 在啟動時就把焦點放在 `TextEditor`,所以動作檔中的 Tab 會被打進去(P94;該檔改為點擊)。
- GTK popover 選單中的方向鍵每次執行的起點項目不同(queue 第 24a 列，未解決);P19 的 GTK 檔改用點擊。
- 旋轉:GTK 的 `angle_delta` 正規化到 [0, 2π) 且 y 軸向下,WinUI 則回報有正負號、無上下限的角度。GtkBackend
  逐步展開，在 begin 時歸零(P65,2026-09-17)。
