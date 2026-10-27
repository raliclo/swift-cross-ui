# GtkBackend on macOS: CSS, metrics and colour

GtkBackend draws with Adwaita on Homebrew GTK, and on macOS it is compared side
by side with AppKitBackend (the GTK / macOS pairs deck). These are the
macOS-specific adjustments and the CSS rules that keep them working.

## CSS loading

- **Global provider before the first view** (b7b60803, 2026-10-18). Button
  measures its padding once from a probe button and caches it
  (`measureBorderedButtonPadding`), so CSS loaded after `callback()` never
  reached a button's size.
- **Reload only when the text changes** (7ad78a1a, 2026-10-23). `css.clear()`
  then `css.set(...)` was two changes of `Widget.css`, each reloading a provider
  added for the whole display, so every widget restyled twice per update;
  GtkCustomButton reloaded on every update. Thirteen clear-then-set sites now
  assign once, and `Widget.loadCSSText` skips a load of the text the provider
  already holds. The speed-up was measured on Windows GTK (P96 25-29 fps -> 72-78)
  and WSL (29-30 -> 36.7); on macOS the change was checked for looks only: P1,
  P11, P19, P49, P50, P55, P71, P72 and P82 recaptured as before
  (results.csv2: mac, gtk4, 2026-10-23).
- **Animated transforms bypass CSS.** Geometric effects are set as the GtkFixed
  child transform, not a CSS `transform`: with CSS, P96's dots drew 28 fps with
  most of each frame in `gtk_css_node_validate`; with the child transform, 32-60
  (results.csv2: mac, gtk4, P96, 2026-10-17).

## Metrics: AppKit-sized controls (macOS only)

`platformMetricsCSS` (`GtkBackend.swift`) brings Adwaita's buttons (~34 px tall,
17 px side padding) and entries (34 px) to about 22-24, AppKit's size. A
horizontal scale drops Adwaita's 12 px side padding and the knob's negative
margins, so the trough spans the frame and the knob stays inside, as NSSlider's
does. Other desktops keep their theme's metrics. Cases: P52's 48 one-letter
buttons fit their column, P91's buttons and field match AppKit's height
(b7b60803); P32 trough x 36-554 against AppKit 36-556 (results.csv2: mac, gtk4,
P32, 2026-10-19), P99.

## Colour

- **Dark mode is read from macOS.** Homebrew GTK does not follow the system
  appearance and drew Adwaita light on a dark Mac (P3's headings dark grey on
  black, 2026-10-16). `systemColorScheme` reads `AppleInterfaceStyle`, and a
  `DistributedNotificationCenter` observer for
  `AppleInterfaceThemeChangedNotification` follows changes, hopping to GTK's
  thread with `g_idle_add`.
- **Windows are tagged sRGB.** GTK 4.24 leaves its NSWindow's pixels untagged, so
  they are shown in the display's colour space. `tagColourSpace(ofWindow:)`
  (`GtkBackend+ColourSpace.swift`, `scui_window_native_macos` in
  `gtk_window_native_macos.c`) sets `colorSpace = .sRGB` after `present()`. On a
  wide-gamut MSI MD272UPS, P95's (0.4, 0.9, 1) swatch read 0 237 255 before and
  102 229 255 after (queue item 16; results.csv2: mac, gtk4, P95, 2026-10-14).
- **List backgrounds:** GtkListView (node `listview`) was not covered by the
  `list { background: none }` rule and painted the theme's view colour; both
  nodes are transparent (628acffa; P3, 2026-10-19).
- **Destructive buttons** are system-red text on the ordinary bezel, the
  disabled one dimmed, as on AppKit; GtkBackend no longer adds
  `destructive-action` (P82, results 2026-10-19; system red 37cafb49,
  2026-10-23).
- **Conic gradients** start at three o'clock (CSS's 90 degrees): with -90 the
  angular and sweep gradients began at nine and ran opposite to AppKit
  (6f4f94a2; P27, P39, 2026-10-19).

## Text

- **Wrapped text in whole lines** (d21ad213). Pango sets wrapped lines at
  fractional heights (three 13 pt lines in 46, one in 16); Text kept only the
  lines that fit and ended in an ellipsis. A wrapped label is now reported as
  whole lines of its first line's height: P17's subject 150 x 48, three lines,
  against AppKit's 155 x 48.
- **Chinese two-line minimum** (869298ff). Pango decides ellipsizing from the
  font's empty-line height (13 px), while Chinese lines on macOS are 12 px, so a
  24 px two-line label drew one line and "...". Text of two lines or more now
  measures at least two empty-line heights; extents round up.
- **Emoji at AppKit's size** (d21ad213). Pango draws Apple Color Emoji at
  1.25 x the font size at every size; CoreText at 1.25 x at 13-16 pt, 1.1 x at
  20, 1 x from 24. Runs in that font get a Pango scale of CoreText ink width
  over Pango's: P103's first emoji 22 x 21 pt against AppKit's 21 x 21 (was
  25 x 24).

## Limits

- Accepted, not aligned: GTK's controls stay taller than AppKit's in places
  (P17/P41 open taller from GTK control minimum heights; kept as is since 2026-10-22, not a layout bug), GTK list rows 32 pt against AppKit's 28 (P3).
- The 7ad78a1a frame-rate gain has no macOS measurement.

---

# macOS 上的 GtkBackend:CSS、尺寸與色彩

GtkBackend 在 Homebrew GTK 上以 Adwaita 繪製，而在 macOS 上會與 AppKitBackend 並排比對(GTK / macOS 對照簡報)。以下是
macOS 專屬的調整，以及讓它們生效的 CSS 規則。

## CSS 載入

- **全域 provider 在第一個 view 之前載入**(b7b60803,2026-10-18)。Button 以一顆探測按鈕量一次 padding 後快取，
  在 `callback()` 之後載入的 CSS 從來影響不到按鈕大小。
- **文字有變才重新載入**(7ad78a1a,2026-10-23)。`css.clear()` 再 `css.set(...)` 是兩次 `Widget.css` 變更，每次都重載一個
  套用到整個 display 的 provider,每次更新所有 widget 被重算樣式兩次。13 處改成一次指定,`Widget.loadCSSText` 遇到相同文字就
  略過。加速是在 Windows GTK(P96 25–29 → 72–78 fps)與 WSL(29–30 → 36.7)量的；macOS 上只檢查外觀:P1、P11、P19、P49、
  P50、P55、P71、P72、P82 重拍與先前相同(results.csv2:mac、gtk4、2026-10-23)。
- **動畫的變形不走 CSS。** 幾何效果設為 GtkFixed 的 child transform:用 CSS 時 P96 的點只有 28 fps,大部分時間在
  `gtk_css_node_validate`;改用 child transform 後 32–60(results.csv2:mac、gtk4、P96、2026-10-17)。

## 尺寸:比照 AppKit 的控制項(僅 macOS)

`platformMetricsCSS` 把 Adwaita 的按鈕(約 34 px 高、左右 17 px padding)與輸入框(34 px)縮到約 22–24,即 AppKit 的大小。
水平 scale 去掉 12 px 左右 padding 與旋鈕的負邊界，軌道跨滿 frame、旋鈕留在裡面，與 NSSlider 相同。其他桌面維持佈景主題的尺寸。
例:P52 的 48 顆單字母按鈕放得進欄位,P91 的按鈕與輸入框與 AppKit 等高(b7b60803);P32 軌道 x 36–554 對 AppKit 36–556
(2026-10-19),P99。

## 色彩

- **深色模式取自 macOS。** Homebrew GTK 不跟隨系統外觀，在深色 Mac 上畫 Adwaita 淺色(P3 的標題在黑底上是深灰,2026-10-16)。
  `systemColorScheme` 讀 `AppleInterfaceStyle`,並以 `DistributedNotificationCenter` 監聽
  `AppleInterfaceThemeChangedNotification`,經 `g_idle_add` 回到 GTK 執行緒。
- **視窗標記為 sRGB。** GTK 4.24 不標記 NSWindow 像素的色彩空間，於是以螢幕自己的色域顯示。`tagColourSpace(ofWindow:)`
  在 `present()` 之後設 `colorSpace = .sRGB`。廣色域的 MSI MD272UPS 上,P95 的 (0.4, 0.9, 1) 色塊由 0 237 255 變成
  102 229 255(queue 第 16 項;results.csv2:mac、gtk4、P95、2026-10-14)。
- **清單背景:** GtkListView(節點 `listview`)不在 `list { background: none }` 規則內，畫出佈景主題的底色；現在兩個節點都透明
  (628acffa;P3,2026-10-19)。
- **destructive 按鈕**是一般外框上的系統紅色文字、停用時變暗，與 AppKit 相同(P82,2026-10-19;系統紅 37cafb49,2026-10-23)。
- **圓錐漸層**從三點鐘方向(CSS 的 90 度)開始;用 -90 時 angular 與 sweep 從九點鐘開始、方向與 AppKit 相反
  (6f4f94a2;P27、P39,2026-10-19)。

## 文字

- **換行文字以整行計算**(d21ad213)。Pango 的換行行高是小數(三行 13 pt 共 46、一行 16),Text 只保留放得下的行並以省略號結尾。
  現在換行標籤回報為「第一行行高的整數倍」:P17 的 subject 150 x 48、三行，對 AppKit 155 x 48。
- **中文至少兩行高**(869298ff)。Pango 以字型的空行高度(13 px)判斷是否省略，而 macOS 上中文行高 12 px,兩行 24 px 的標籤
  只畫一行加「...」。兩行以上的文字現在至少量兩個空行高度，尺寸無條件進位。
- **emoji 與 AppKit 同大**(d21ad213)。Pango 在任何字級都把 Apple Color Emoji 畫成 1.25 倍;CoreText 在 13–16 pt 是 1.25 倍、
  20 pt 1.1 倍、24 pt 起 1 倍。該字型的文字段以「CoreText 墨水寬度 / Pango 墨水寬度」縮放:P103 第一個 emoji 22 x 21 pt,
  AppKit 21 x 21(原為 25 x 24)。

## 限制

- 接受而不對齊:GTK 的控制項在某些地方仍較高(P17/P41 因 GTK 控制項的最小高度而開得較高;2026-10-22 起維持原狀，不是排版錯誤),GTK 清單列高 32 pt、AppKit 28(P3)。
- 7ad78a1a 的幀率改善沒有 macOS 的量測。
