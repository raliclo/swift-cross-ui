# Measuring with UI Automation on Windows

Written 2026-10-24 from testapp/test_support/measure/ (measure_win.zsh,
uia_rects.c, uia_tree.c, p69_uia.zsh) and results.csv2 (windows: P69 2026-10-20,
P81 2026-10-20, P18 2026-10-07).

## Tools

- `measure/measure_win.zsh Pn [gtk4]` builds `uia_rects.c` (clang; ole32,
  oleaut32, user32, uuid), launches the exe, waits `MEASURE_WAIT` (6 s) and
  prints frame-relative centres of UIA control-view elements, ready for
  `origin=frame` rows. It walks with a TreeWalker: `FindAll` over a WinUI
  island sometimes returned only 7 elements (2026-10-07).
- `uia_tree.c` / `p69_uia.zsh` dump the raw, control or content view from
  outside the process; P69 runs 9 checks and passes only if every check passes
  in both the control and content views.

## What UIA settles that a capture cannot

- **Popups.** A WinUI sheet is a Popup and a GTK sheet an owned window; neither
  is in a window capture. `uia_rects` during the hold showed P81's sheet under
  window B, correcting two fail rows (2026-10-20).
- **Pressing controls without the mouse.** UIA Invoke/Toggle/SelectionItem
  drives buttons, pickers and dialog buttons when injection is refused (P18:
  IDOK=1 / IDCANCEL=2 by AutomationId; by Name, Open hit the combo's drop-down).
  An Invoke that works where a click does not points at hit testing (P50).
- **Accessible names** (#123): WinUI 14/14 (2026-09-17); GTK only with the
  AccessKit runtime ([gtk-theme-fonts-a11y.md](gtk-theme-fonts-a11y.md)).

## Limits

- With the gvsbuild GTK runtime, a GTK window is one UIA node; menus and
  popovers expose nothing. `measure_win.zsh`'s header says GTK has no tree;
  that is true only without `C:/gtk4-accesskit`. The script does not source
  `gtk_runtime.zsh`, so a gtk4 launch takes whatever PATH the caller has.

---

# 在 Windows 上以 UI Automation 量測

2026-10-24 依 testapp/test_support/measure/(measure_win.zsh、uia_rects.c、uia_tree.c、p69_uia.zsh)與
results.csv2(windows:P69 2026-10-20、P81 2026-10-20、P18 2026-10-07)寫成。

## 工具

- `measure/measure_win.zsh Pn [gtk4]` 建置 `uia_rects.c`(clang;ole32、oleaut32、user32、uuid),啟動 exe,等
  `MEASURE_WAIT`(6 秒),印出 UIA control view 元素相對於外框的中心點，可直接用於 `origin=frame` 列。它以
  TreeWalker 走訪:對 WinUI island 做 `FindAll` 有時只回傳 7 個元素(2026-10-07)。
- `uia_tree.c` / `p69_uia.zsh` 從行程外部傾印 raw、control 或 content view;P69 執行 9 項檢查，只有在 control 與
  content 兩種 view 都全數通過時才算通過。

## UIA 能判定、擷圖不能判定的事

- **彈出視窗。** WinUI 的 sheet 是 Popup,GTK 的 sheet 是有 owner 的視窗；兩者都不在視窗擷取裡。在按住期間執行
  `uia_rects`,看到 P81 的 sheet 在視窗 B 底下，更正了兩筆失敗列(2026-10-20)。
- **不用滑鼠按控制項。** 注入被拒絕時,UIA 的 Invoke/Toggle/SelectionItem 可驅動按鈕、選擇器與對話框按鈕(P18:
  以 AutomationId 按 IDOK=1 / IDCANCEL=2;以 Name 找時,Open 先命中下拉框的展開鈕)。Invoke 有效而點擊無效時，問題
  在點擊判定(P50)。
- **無障礙名稱**(#123):WinUI 14/14(2026-09-17);GTK 只有在 AccessKit runtime 下才有
  ([gtk-theme-fonts-a11y.md](gtk-theme-fonts-a11y.md))。

## 限制

- 使用 gvsbuild 的 GTK runtime 時，一個 GTK 視窗只是一個 UIA 節點；選單與 popover 不暴露任何東西。
  `measure_win.zsh` 的標頭說 GTK 沒有樹，那只在沒有 `C:/gtk4-accesskit` 時成立。該腳本不引入 `gtk_runtime.zsh`,
  所以 gtk4 的啟動取決於呼叫者的 PATH。
