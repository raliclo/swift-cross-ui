# todo-Gtk — things to raise with GTK upstream, not with this repository

Items here are defects in GTK itself, found while driving SwiftCrossUI. Each one
says what was measured, where it lives in GTK's own source, and what we did on
our side meanwhile. Nothing here is reported to anyone until the user says so.

本檔收錄的是在驅動 SwiftCrossUI 時發現、但**缺陷在 GTK 本身**的項目。每一條都寫明量到什麼、對應到 GTK
原始碼的哪裡,以及我們這邊同時做了什麼。**在使用者同意之前,不對外回報任何一條。**

---

- [ ] **A removed pointing device is used after it is freed (GTK 4.22.4, Windows).**
      Report to https://gitlab.gnome.org/GNOME/gtk when approved.

  **What happens.** When a touch device disappears while a gesture still refers
  to it, GDK drops both of its own references and something in the gesture
  machinery keeps using the raw pointer. The log shows
  `gdk_device_get_display: assertion 'GDK_IS_DEVICE (device)' failed`, then the
  process takes an access violation.

  **Measured 2026-09-17** on Windows with `P11 --nested-slider`, a synthetic
  touch drag on a slider inside a vertical `ScrollView`:
  - Device destroyed right after the UP event: 4 of 6 runs crashed, the critical
    about 50 ms after the tool exited.
  - Device destroyed 3 s after UP instead: 0 of 6. The two conditions were
    alternated in one harness.
  - All 8 Windows Error Reporting records name the same offset,
    `gtk-4-1.dll+0x4ec0b1`, which GTK's own PDB resolves to
    `_gdk_win32_get_cursor_pos` (`gdk/win32/gdkevents-win32.c:166`). A NULL
    display reaches it from `gdk_device_winpointer_query_state`.

  **In GTK's source (4.22.4).** `winpointer_enumerate_devices`
  (`gdk/win32/gdkinput-winpointer.c`) runs on `WM_POINTERDEVICECHANGE`. For a
  device no longer in the system list it calls
  `gdk_seat_default_remove_physical_device` (which unrefs) and then
  `g_object_unref (device)` itself, while a gesture still holds the pointer.

  **Real hardware reaches the same path**: unplugging a touch screen or a
  tablet, or a remote-desktop session dropping its touch device. The synthetic
  device only made it easy to hit.

  **Our side**, so the crash cannot take an app down meanwhile:
  `Sources/GtkCHelpers/gtk_device_lifetime.c` takes one reference on the seat's
  `device-removed` signal, which fires before both unrefs, and never releases
  it. After that: 10 of 10 runs alive with no criticals, in the harness where
  the crash reproduced. Committed in `9dd625ac`.

  **一個被移除的指向裝置在釋放之後仍被使用(GTK 4.22.4,Windows)。** 觸控裝置在手勢仍指著它時消失,GDK 丟掉
  自己的兩個參考,而手勢機制裡仍有東西在用那個裸指標:先出現 `GDK_IS_DEVICE` 斷言失敗,接著行程存取違規。
  2026-09-17 以 `P11 --nested-slider` 實測:UP 後立即銷毀裝置,6 輪崩 4 輪;改為 3 秒後銷毀,6 輪 0 次(兩種
  條件在同一個 harness 中交錯執行)。8 份 WER 都指向 `gtk-4-1.dll+0x4ec0b1`,以 GTK 的 PDB 解析為
  `_gdk_win32_get_cursor_pos`(`gdk/win32/gdkevents-win32.c:166`),NULL display 由
  `gdk_device_winpointer_query_state` 傳入。原始碼位置是 `gdk/win32/gdkinput-winpointer.c` 的
  `winpointer_enumerate_devices`。真實硬體同樣會走到:拔掉觸控螢幕或繪圖板、遠端桌面移除觸控裝置。
  我們這邊已在 `Sources/GtkCHelpers/gtk_device_lifetime.c` 以 `device-removed` 多取一個永不釋放的參考擋住,
  修後 10/10 存活(commit `9dd625ac`)。
