# todo-Gtk — things to raise with GTK upstream, not with this repository

Items here are defects in GTK itself, found while driving SwiftCrossUI. Each one
says what was measured, where it lives in GTK's own source, and what was done on
the GtkBackend side meanwhile. Nothing here is reported upstream without explicit approval.

本檔收錄的是在驅動 SwiftCrossUI 時發現、但**缺陷在 GTK 本身**的項目。每一條都寫明量到什麼、對應到 GTK
原始碼的哪裡,以及 GtkBackend 端同時做了什麼。**未經明確同意,不向上游回報任何一條。**

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

  **GtkBackend side**, so the crash cannot take an app down meanwhile:
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
  GtkBackend 端已在 `Sources/GtkCHelpers/gtk_device_lifetime.c` 以 `device-removed` 多取一個永不釋放的參考擋住,
  修後 10/10 存活(commit `9dd625ac`)。

  **2026-10-29 (Windows): reproduced without SwiftCrossUI; 4.24.1 not settled.**
  A 60-line C program (one window, one `GtkGestureDrag`, a seat `device-removed`
  print), built with clang against gvsbuild 2026.10.0's headers and driven by
  `testapp/helper/bin/touch_gesture.exe drag`, which destroys its synthetic
  device right after the lift. On 4.22.4 (`C:/gtk4-accesskit` + `C:/gtk4`) it
  died with rc=139 after the same `GDK_IS_DEVICE` critical -- the reproducer to
  attach upstream. On 4.24.1 (`C:/gtk4-424`) one valid sample: touch events
  17/18/19 delivered, `device-removed` printed, process alive. One sample is not
  a fix; about 30 further trials of both versions never delivered touch (the
  user's own window sat over the test window) and do not count. Next: drive
  P11 --nested-slider through test.zsh with `SCUI_GTK_KEEP_REMOVED_DEVICES=0`
  on both runtimes, interleaved, counting only runs whose log shows the device
  removed. Source kept at scratchpad `gdkuaf/gdk_touch_uaf.c`; move it into
  the repo before filing.
  **2026-10-29(Windows):不靠 SwiftCrossUI 已重現;4.24.1 尚未定論。** 一支約 60 行的 C 程式(一個視窗、一個
  `GtkGestureDrag`、印出 seat 的 `device-removed`),以 clang 對 gvsbuild 2026.10.0 的標頭建置，用
  `touch_gesture.exe drag` 驅動(抬起後立即銷毀合成裝置)。4.22.4 上以 rc=139 結束，前面是同一句 `GDK_IS_DEVICE`
  斷言——這就是要附給上游的重現程式。4.24.1 只有一個有效樣本：觸控事件 17/18/19 送達、印出 `device-removed`、
  行程存活。一個樣本不等於已修好；之後兩個版本約 30 次試驗觸控都沒送達(使用者自己的視窗蓋在測試視窗上),不計。
  下一步：經 test.zsh 驅動 P11 --nested-slider,加 `SCUI_GTK_KEEP_REMOVED_DEVICES=0`,兩個 runtime 交錯，只計日誌
  顯示裝置已移除的那幾次。原始碼暫存於 scratchpad 的 `gdkuaf/gdk_touch_uaf.c`,回報前先移進 repo。

  **2026-10-29, later (Windows): NOT fixed in 4.24.1.** The note above left it
  open on one sample; driven through test.zsh it is settled. P11
  --nested-slider, `touch_gesture.zsh drag 208 265 560 265` on the vertical
  slider (device destroyed at the tool's exit), with the GtkBackend workaround
  switched off by the new `SCUI_GTK_KEEP_REMOVED_DEVICES=0`, the two runtimes
  alternated. Touch reached the slider in all 12 runs (`nested vertical ->
  93/94`). 4.22.4: 2 of 6 died, one more logged the critical and lived.
  4.24.1: 4 of 6 died, one more logged the critical and lived -- the same
  `gdk_device_get_display: assertion 'GDK_IS_DEVICE (device)' failed`. Control,
  4.24.1 with the workaround on: 6 of 6 alive, 0 criticals. So the workaround
  stays, and the report still applies to the current release. Script: scratchpad
  `gdkuaf/p11_trials.zsh`.
  **2026-10-29 稍後(Windows):4.24.1 沒有修好。** 上一段只有一個樣本而未定論；經 test.zsh 驅動後定案。P11
  --nested-slider,以 `touch_gesture.zsh drag 208 265 560 265` 拖垂直滑桿(工具結束時銷毀裝置),用新的
  `SCUI_GTK_KEEP_REMOVED_DEVICES=0` 關掉 GtkBackend 的保護，兩個 runtime 交錯。12 次觸控都送達(`nested vertical ->
  93/94`)。4.22.4:6 次崩 2 次，另 1 次出現斷言但存活。4.24.1:6 次崩 4 次，另 1 次出現斷言但存活——同一句
  `GDK_IS_DEVICE` 斷言。對照組 4.24.1 開著保護：6/6 存活、0 個斷言。保護保留，回報對目前版本仍然適用。

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

  **GtkBackend side (superseded by the 2026-10-20 correction below):** nothing. `setAccessibilityLabel` already sets the property, and
  it is correct on AT-SPI; there is nothing to change in GtkBackend for this.
  `testapp/test_support/measure/p69_uia.zsh` grades it as `text_label` and
  `no_original_text`, the only two of its nine checks that GTK fails.

  **2026-10-20: "GtkBackend side: nothing" was wrong, and so was "Where it lives".** The text runs
  do not overwrite the label: AccessKit's Windows adapter names a Role::Label node from its
  *value* (accesskit_windows 0.29 `name()` -> `label_comes_from_value`), and a GtkLabel's value
  is its runs unless one is set explicitly (accesskit_consumer `write_value`). GTK maps
  VALUE_TEXT to that value, so GtkBackend now also sets the label as VALUE_TEXT on a
  `CustomLabel`, on Windows only. P69 with the AccessKit build: all nine checks pass in both
  views, `text name='Half past twelve' class='GtkLabel'` (still a UIA Text control). What is
  left to raise upstream, when approved, is whether an explicit label should win for a Label role.
  **2026-10-20:「GtkBackend 端不需要改」與「位置」都錯了。**AccessKit 的 Windows adapter 對 Role::Label 取「值」當名稱，而 GtkLabel 的值在沒有明確設定時就是文字 run;GTK 把 VALUE_TEXT 對應到值，因此 GtkBackend 在 Windows 上也把標籤設為 CustomLabel 的 VALUE_TEXT。P69 九項全過。上游要問的只剩「Label role 是否該優先採用明確的 label」。

  **在 `GtkLabel` 上設定的標籤到不了 Windows:AccessKit 以節點的文字為名。** 2026-09-19 以 P69 量到:WSLg 的
  AT-SPI 讀到 `label 'Half past twelve'`;Windows 的 AccessKit 建置經行程外 UIA 讀到的卻是
  `text name='12:30'`。同一次執行裡,description 與 value 都正確抵達(`fulldesc=`、`value=`),設了標籤的按鈕也
  正確地沒有 `X` 子節點,因此不是整條路壞掉。`gtkaccesskitcontext.c` 確實有把 LABEL 對應到
  `accesskit_node_set_label`,但同一個函式接著為 `GtkLabel` 呼叫 `add_single_text_layout` 掛上 Pango 文字,
  而送到 UIA 的名稱取自那些文字。該由 adapter 優先採用明確標籤,還是 GTK 在已設標籤時不掛文字,是要問上游的。
  **GtkBackend 端(原判斷「不需要改」,已由上方 2026-10-20 的更正取代)**:`setAccessibilityLabel` 已經設了該屬性,在 AT-SPI 上也是對的。
