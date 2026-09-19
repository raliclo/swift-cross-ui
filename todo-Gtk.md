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

---

- [ ] **A label set on a `GtkLabel` never reaches Windows: AccessKit names the
      node from its text instead (GTK 4.22.4 + AccessKit, Windows).**
      Report to https://gitlab.gnome.org/GNOME/gtk, or to AccessKit, once it is
      clear which of the two owns it -- and only when approved.

  **What happens.** `GTK_ACCESSIBLE_PROPERTY_LABEL` on a `GtkLabel` is announced
  on AT-SPI and ignored through AccessKit. A screen reader on Windows therefore
  reads the raw text where Linux reads the author's label.

  **Measured 2026-09-19** with P69, which puts
  `Text("12:30").accessibilityLabel("Half past twelve")` on screen:
  - WSLg, AT-SPI: `label 'Half past twelve'`, and no node named `12:30`.
  - Windows, the AccessKit build, out-of-process UIA:
    `text name='12:30' class='GtkLabel'`, and no node named `Half past twelve`.
  - The same run gets the other properties right, so the path itself works:
    `button name='Delete' fulldesc='Removes the file permanently'` and
    `button name='Volume' value='40 percent'`, and a labelled button reads
    `button name='Close'` with its `X` child gone.

  **Where it lives.** `gtk/a11y/gtkaccesskitcontext.c` does map the property:
  `set_string_property (ctx, GTK_ACCESSIBLE_PROPERTY_LABEL,
  accesskit_node_set_label, node)`. The same function then calls
  `add_single_text_layout` for a `GtkLabel`, which attaches the Pango layout as
  text runs. The node reaching UIA is named from those runs, so the label is
  overwritten rather than missing. Whether the adapter should prefer an explicit
  label over computed text, or GTK should not attach runs when a label is set,
  is the question to put upstream.

  **Our side:** nothing. `setAccessibilityLabel` already sets the property, and
  it is correct on AT-SPI; there is nothing to change in GtkBackend for this.
  `testapp/test_support/measure/p69_uia.zsh` grades it as `text_label` and
  `no_original_text`, the only two of its nine checks that GTK fails.

  **在 `GtkLabel` 上設定的標籤到不了 Windows:AccessKit 以節點的文字為名。** 2026-09-19 以 P69 量到:WSLg 的
  AT-SPI 讀到 `label 'Half past twelve'`;Windows 的 AccessKit 建置經行程外 UIA 讀到的卻是
  `text name='12:30'`。同一次執行裡,description 與 value 都正確抵達(`fulldesc=`、`value=`),設了標籤的按鈕也
  正確地沒有 `X` 子節點,因此不是整條路壞掉。`gtkaccesskitcontext.c` 確實有把 LABEL 對應到
  `accesskit_node_set_label`,但同一個函式接著為 `GtkLabel` 呼叫 `add_single_text_layout` 掛上 Pango 文字,
  而送到 UIA 的名稱取自那些文字。該由 adapter 優先採用明確標籤,還是 GTK 在已設標籤時不掛文字,是要問上游的。
  **我們這邊不需要改**:`setAccessibilityLabel` 已經設了該屬性,在 AT-SPI 上也是對的。
