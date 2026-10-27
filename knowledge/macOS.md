# macOS

Knowledge for the two backends that run on macOS: AppKitBackend, and
GtkBackend on Homebrew GTK (`TEST_BACKEND=gtk4`). Written 2026-10-24 from the
repository, `matrix_coverage/results.csv2` (platform `mac`) and `git log`.

## Harness

- [harness-run.md](macOS/harness-run.md) — what `test.zsh Pn --macos` does: build, launch, marker, replay wait, captures, teardown, environment knobs.
- [debugtarget-bundle.md](macOS/debugtarget-bundle.md) — why every app runs inside `.macApp/debugTarget.app`, its per-app bundle id, and saved frames dropped before launch.
- [screenshot-capture.md](macOS/screenshot-capture.md) — `screencapture` priorities, window-title resolution through CGWindowList, and what a fallback to the whole screen means.
- [permissions-and-desktop.md](macOS/permissions-and-desktop.md) — Screen Recording, Accessibility, keyboard navigation, display sleep: desktop states that look like app defects.
- [input-synthesis.md](macOS/input-synthesis.md) — AppKitSynthesiser: in-process events by default, the HID tap and where it is required, rules that were each a bug once.
- [menu-dump.md](macOS/menu-dump.md) — P92's menu-bar dump against the SwiftUI reference, and reading or pressing menus through osascript/System Events.
- [sweep-apple.md](macOS/sweep-apple.md) — `sweep_apple.zsh` for AppKit and GTK, what a pass means and does not, and what past sweeps missed.
- [pairs-deck.md](macOS/pairs-deck.md) — `capture_macos.zsh` and the GTK/macOS and GTK three-way decks.
- [window-sizes.md](macOS/window-sizes.md) — `window_sizes_mac.zsh`, `SCUI_DEBUG_WINDOW_SIZE`, saved frames, and the virtual-display scale change for P42.
- [measure-tools.md](macOS/measure-tools.md) — the Swift and C probes under `test_support/measure` and what each found.

## AppKitBackend

- [appkit-windows-and-presentations.md](macOS/appkit-windows-and-presentations.md) — frame autosave, a window constrained while shown, popover edges, alerts and sheets.
- [appkit-layout-and-text.md](macOS/appkit-layout-and-text.md) — text measurement, whole lines, table column widths, list recycling and memory, scroller style.
- [appkit-drawing-and-colour.md](macOS/appkit-drawing-and-colour.md) — sRGB colours, strokes and hit testing, CIFilter and CATransform3D effects, frame clock, Metal adapters.
- [appkit-accessibility.md](macOS/appkit-accessibility.md) — what the AX tree needs, and checking it with `ax_dump`.
- [metal-renderer.md](macOS/metal-renderer.md) — SwiftCrossUIMetal, the mesh renderer shared with UIKit, and the decisions not to undo.

## GtkBackend on macOS

- [gtk-setup.md](macOS/gtk-setup.md) — Homebrew GTK 4.24.1 and libepoxy, `install_tool_mac.zsh`, the `compile.zsh -gtk4` Darwin branch.
- [gtk-menu-bar.md](macOS/gtk-menu-bar.md) — `menuBarModel` as the screen menu bar, GTK's own app menu, standard items, Command as Meta.
- [gtk-css-and-metrics.md](macOS/gtk-css-and-metrics.md) — CSS loading and reloads, AppKit-sized controls, dark mode, sRGB, emoji and wrapped text.
- [gtk-frame-clock.md](macOS/gtk-frame-clock.md) — GDK's display link stopping after every frame, the patch, and the numbers.
- [gtk-platform-integration.md](macOS/gtk-platform-integration.md) — replay into GDK windows, Apple-event URLs, WKWebView, window level, resizing through System Events.

## Open

- [open-problems.md](macOS/open-problems.md) — what is still open on either backend, with the date last checked.

---

# macOS

在 macOS 上執行的兩個 backend 的知識:AppKitBackend,以及以 Homebrew GTK 執行的 GtkBackend(`TEST_BACKEND=gtk4`)。
2026-10-24 依 repository、`matrix_coverage/results.csv2`(平台 `mac`)與 `git log` 寫成。

## Harness

- [harness-run.md](macOS/harness-run.md) — `test.zsh Pn --macos` 做了什麼：建置、啟動、marker、等待重放、擷圖、收尾、環境變數。
- [debugtarget-bundle.md](macOS/debugtarget-bundle.md) — 為何每支 app 都在 `.macApp/debugTarget.app` 裡執行、每支 app 的 bundle id,以及啟動前丟掉儲存的視窗框。
- [screenshot-capture.md](macOS/screenshot-capture.md) — `screencapture` 的優先序、經 CGWindowList 解析視窗標題，以及退回整個螢幕代表什麼。
- [permissions-and-desktop.md](macOS/permissions-and-desktop.md) — 螢幕錄製、輔助使用、鍵盤導覽、螢幕休眠：看起來像 app 缺陷的桌面狀態。
- [input-synthesis.md](macOS/input-synthesis.md) — AppKitSynthesiser:預設在行程內送事件、HID tap 及其必要之處，以及每一條都曾是 bug 的規則。
- [menu-dump.md](macOS/menu-dump.md) — P92 的選單列傾印與 SwiftUI 基準比對，以及經 osascript/System Events 讀取或按下選單。
- [sweep-apple.md](macOS/sweep-apple.md) — AppKit 與 GTK 的 `sweep_apple.zsh`、pass 代表與不代表什麼，以及過去的 sweep 漏掉了什麼。
- [pairs-deck.md](macOS/pairs-deck.md) — `capture_macos.zsh` 與 GTK/macOS、GTK 三方對照簡報。
- [window-sizes.md](macOS/window-sizes.md) — `window_sizes_mac.zsh`、`SCUI_DEBUG_WINDOW_SIZE`、儲存的視窗框，以及 P42 用的虛擬螢幕縮放切換。
- [measure-tools.md](macOS/measure-tools.md) — `test_support/measure` 下的 Swift 與 C 探針，以及各自找到了什麼。

## AppKitBackend

- [appkit-windows-and-presentations.md](macOS/appkit-windows-and-presentations.md) — 視窗框自動儲存、顯示時被約束的視窗、popover 的邊、alert 與 sheet。
- [appkit-layout-and-text.md](macOS/appkit-layout-and-text.md) — 文字量測、整行、表格欄寬、清單回收與記憶體、捲軸樣式。
- [appkit-drawing-and-colour.md](macOS/appkit-drawing-and-colour.md) — sRGB 顏色、筆畫與 hit test、CIFilter 與 CATransform3D 效果、frame clock、Metal 介面卡。
- [appkit-accessibility.md](macOS/appkit-accessibility.md) — AX 樹需要什麼，以及用 `ax_dump` 檢查。
- [metal-renderer.md](macOS/metal-renderer.md) — SwiftCrossUIMetal,與 UIKit 共用的網格算繪器，以及不該改回去的決定。

## macOS 上的 GtkBackend

- [gtk-setup.md](macOS/gtk-setup.md) — Homebrew GTK 4.24.1 與 libepoxy、`install_tool_mac.zsh`、`compile.zsh -gtk4` 的 Darwin 分支。
- [gtk-menu-bar.md](macOS/gtk-menu-bar.md) — `menuBarModel` 成為螢幕選單列、GTK 自己的 app 選單、標準項目、Command 即 Meta。
- [gtk-css-and-metrics.md](macOS/gtk-css-and-metrics.md) — CSS 載入與重新載入、AppKit 尺寸的控制項、深色模式、sRGB、emoji 與換行文字。
- [gtk-frame-clock.md](macOS/gtk-frame-clock.md) — GDK 的 display link 每幀之後就停、修補方式與數據。
- [gtk-platform-integration.md](macOS/gtk-platform-integration.md) — 對 GDK 視窗重放、Apple event URL、WKWebView、視窗層級、經 System Events 改大小。

## 未解

- [open-problems.md](macOS/open-problems.md) — 兩個 backend 上仍未解決的問題，附最後檢查日期。
