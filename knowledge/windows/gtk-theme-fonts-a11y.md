# GtkBackend on Windows: theme, fonts, accessibility, frame rate

Written 2026-10-24 from testapp/gtk-silent-noops.md, Sources/GtkCHelpers
(gtk_titlebar_theme.c, gtk_dispatch_main_queue.c), commits 62239763, 97539442,
750f43a6, e9b80e8e, and results.csv2 (windows, gtk4: P66 2026-10-19, P69
2026-10-20, P96 2026-10-23).

## Theme

- GTK draws its own Adwaita and does not follow Windows' light/dark setting.
  GtkBackend reads `AppsUseLightTheme` and follows changes with a
  `RegNotifyChangeKeyValue` thread (62239763). The native title bar is set dark
  or light through `DwmSetWindowAttribute` 20/19 (`gtk_titlebar_theme.c`).
- `SCUI_GTK_COLOR_SCHEME=dark|light` overrides; `test_common.zsh` sets dark for
  test runs (97539442).

## Fonts

GTK's default family on Windows is Segoe UI, which has five faces (300, 400,
600, 700, 900). Nine SwiftUI weights therefore render as five
(gtk-silent-noops.md #5). Several emoji draw as hex boxes (🅿 as 01F17F): GTK
on Windows has no glyph for them (P103, 2026-10-19, open).

## Accessibility

- The gvsbuild runtime exposes one UIA node per window; every
  `.accessibility*` modifier is invisible to UIA there.
- The AccessKit runtime (`C:/gtk4-accesskit`, run with `GTK_A11Y=accesskit`)
  exposes the tree. AccessKit's Windows adapter names a Label role from its
  value, so GtkBackend sets the label as `VALUE_TEXT` too (750f43a6). P69
  passes 9 of 9 checks through `test_support/measure/p69_uia.zsh` (2026-10-20).
- Open: what Narrator/NVDA actually say (queue row 8; portable NVDA 2026.2
  installed by `install_nvda_windows.zsh`, 2026-10-23).

## Main queue and frame rate

- `DispatchQueue.main` was drained only by a 50 ms poll. Since e9b80e8e
  (2026-10-19) GtkCHelpers waits on libdispatch's main-queue handle with a
  one-shot thread-pool wait and hands the drain to `g_idle_add_full`. P66
  animation samples went from 2 to 7 (17 with the dGPU preference).
- **CSS reloads cost the frame rate (P96, fixed 2026-10-23).** Each update
  reloaded unchanged CSS: `css.clear()` then `css.set()` is two changes, each
  loading a provider added for the whole display, so every widget restyled
  twice; GtkCustomButton reloaded its provider every update. Now one assignment
  per site and `Widget.loadCSSText` skips identical text. Driven panel 25-29 fps
  -> 72-78 fps (92-94 alone). Any new per-update CSS write can bring it back.
- A Windows timer-resolution hold (`timeBeginPeriod`) was measured with P64 and
  made no difference; it was removed (2026-10-20).

---

# Windows 上的 GtkBackend:主題、字型、無障礙、幀率

2026-10-24 依 testapp/gtk-silent-noops.md、Sources/GtkCHelpers(gtk_titlebar_theme.c、
gtk_dispatch_main_queue.c)、62239763、97539442、750f43a6、e9b80e8e,以及 results.csv2(windows、gtk4:P66
2026-10-19、P69 2026-10-20、P96 2026-10-23)寫成。

## 主題

- GTK 畫自己的 Adwaita,不跟隨 Windows 的淺色/深色設定。GtkBackend 讀取 `AppsUseLightTheme`,並以
  `RegNotifyChangeKeyValue` 執行緒追蹤變更(62239763)。原生標題列透過 `DwmSetWindowAttribute` 20/19 設為深色或
  淺色(`gtk_titlebar_theme.c`)。
- `SCUI_GTK_COLOR_SCHEME=dark|light` 可覆寫;`test_common.zsh` 在測試時設為深色(97539442)。

## 字型

GTK 在 Windows 上的預設字族是 Segoe UI,只有五種字重(300、400、600、700、900)。因此 SwiftUI 的九種字重只畫成五種
(gtk-silent-noops.md #5)。部分 emoji 畫成十六進位方框(🅿 變成 01F17F):Windows 上的 GTK 沒有這些字形(P103,
2026-10-19,未解決)。

## 無障礙

- gvsbuild runtime 每個視窗只暴露一個 UIA 節點；在那裡所有 `.accessibility*` modifier 對 UIA 都看不見。
- AccessKit runtime(`C:/gtk4-accesskit`,以 `GTK_A11Y=accesskit` 執行)會暴露完整的樹。AccessKit 的 Windows
  adapter 以值為 Label 角色命名，所以 GtkBackend 也把標籤設為 `VALUE_TEXT`(750f43a6)。P69 經
  `test_support/measure/p69_uia.zsh` 通過 9 項中的 9 項(2026-10-20)。
- 未解決:Narrator/NVDA 實際念出什麼(queue 第 8 列;`install_nvda_windows.zsh` 於 2026-10-23 安裝了可攜版
  NVDA 2026.2)。

## 主佇列與幀率

- `DispatchQueue.main` 原本只靠 50 ms 的輪詢排空。自 e9b80e8e(2026-10-19)起,GtkCHelpers 以一次性的 thread-pool
  wait 等待 libdispatch 的主佇列 handle,再交給 `g_idle_add_full` 排空。P66 的動畫取樣由 2 增為 7(設定獨顯偏好時
  為 17)。
- **CSS 重新載入拖累幀率(P96,2026-10-23 修正)。** 每次更新都重新載入未改變的 CSS:`css.clear()` 再 `css.set()`
  是兩次變更，每次都載入一個加在整個 display 上的 provider,於是每個 widget 重新套樣式兩次;GtkCustomButton 每次
  更新也重新載入它的 provider。現在每處只指派一次，且 `Widget.loadCSSText` 遇到相同文字就略過。被驅動的面板由
  25–29 fps 升到 72–78 fps(單獨時 92–94)。任何新的逐次更新 CSS 寫入都可能讓它再發生。
- 以 P64 量測過 Windows 計時器解析度(`timeBeginPeriod`),沒有差別，已移除(2026-10-20)。
