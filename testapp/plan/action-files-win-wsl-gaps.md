# Action files still missing on Windows and WSL (2026-10-20)

**Preparation only: no coordinates.** Every coordinate has to be measured on the
real window -- `uia_rects.c` / `measure_win.zsh` on Windows, AT-SPI under WSLg on
WSL -- for the reason `action-files-win-todo89.md` opens with: an unmeasured
coordinate replays without error, clicks empty space and reports success.

**準備用，不含座標。** 每個座標都必須在真實視窗上量測(Windows 用 `uia_rects.c` / `measure_win.zsh`,
WSL 在 WSLg 下用 AT-SPI)。理由同 `action-files-win-todo89.md` 開頭：沒量過的座標重放時不會報錯，
會點在空白處並回報成功。

## How the list was made / 清單如何產生

An app is listed for a platform when `testapp/actions/<platform>/` has no file
whose name starts with `<app>-`. 114 apps: **25 missing on win, 78 on WSL.**

- *Input sites* is a grep count of control constructors (`Button(`, `Toggle(`,
  `TextField(`, `Slider(`, `Picker(`, `Stepper(`, `Menu(`, `ScrollView`,
  `onTapGesture` and similar). It is a hint, not an inventory: 0 means a click row
  has nothing to land on, so the file may only `sleep` and state claims, in the form
  `testapp/actions/win/README.md` describes for apps with no controls.
- *Log writes* counts `Diagnostics.write`. Above 0, the file can carry a
  `# expect: log-contains` marker instead of relying on a capture.
- *Port from* is an existing file for the same app: for WSL the win file first
  (same GtkBackend, so the steps carry over and only the coordinates change), else
  mac; for win the mac file, else ios. The steps port; the numbers never do.
  "none" means no platform has a file yet and the sequence has to come from the source.

- 一支 app 在某平台列入，條件是 `testapp/actions/<平台>/` 沒有以 `<app>-` 開頭的檔案。共 114 支:**win 缺 25,WSL 缺 78。**
- *Input sites* 是控制項建構式的 grep 次數，只是提示。0 代表點擊列沒有東西可點，檔案只能 `sleep` 並寫明主張。
- *Log writes* 是 `Diagnostics.write` 的次數;大於 0 時可以用 `# expect: log-contains` 斷言，不必靠擷圖。
- *Port from* 是同一支 app 已有的檔案:WSL 先找 win(同為 GtkBackend,步驟可沿用、只換座標),否則 mac;
  win 先找 mac,否則 ios。**步驟可以移植，數字永遠不行。** none 代表任何平台都還沒有，要從原始碼設計。

## Order / 建議順序

1. **WSL, port from win** (53 apps): the steps are already written and verified on
   the same backend; only measuring is new.
2. **Port from mac/ios** (14 on win, 14 on WSL), checking each step against GtkBackend and
   WinUI behaviour rather than copying it.
3. **The 11 with no file anywhere** (P77, P78, P79, P81, P85, P86, P87, P89, P90,
   P93, P95), on both platforms at once: one design, two measurements.
4. **todo #89 leftovers**: P27 (a `scroll` in the WebView) and P15-DARK; P17-DOE
   last or never, as that document says.

1. **WSL、從 win 移植**(53 支):步驟已在同一 backend 上寫好並驗證，只差量測。
2. **從 mac/ios 移植**(win 14 支、WSL 14 支):逐步對照 GtkBackend 與 WinUI 的行為，不要照抄。
3. **任何平台都沒有的 11 支**:兩個平台一起做，一次設計、兩次量測。
4. **todo #89 剩下的**:P27(在 WebView 裡 `scroll`)與 P15-DARK;P17-DOE 依該文件，最後做或不做。

## Windows (25)

| App | What it tests (first line of the source) | Input sites | Log writes | Port from |
|---|---|---|---|---|
| P6 | stream player test app: | 14 | 57 | mac/: `P6-transport-toggles.actions` |
| P12 | Android (AndroidBackend) repro app: button margins, state across | 9 | 0 | mac/: `P12-tabs-margins-and-toggles-gtk4.actions`, `P12-tabs-margins-and-toggles.actions` |
| P14 | iOS (UIKitBackend) repro app: size proposals across rotation, and the | 3 | 0 | mac/: `P14-width-history-and-theme-control.actions` |
| P15-DARK | does preferredColorScheme(.dark) actually take effect? (#386) | 3 | 0 | mac/: `P15-DARK-button-under-an-overridden-scheme-gtk4.actions`, `P15-DARK-button-under-an-overridden-scheme.actions` |
| P17-DOE | a design-of-experiments app for the #389 image-clipping fix. | 0 | 0 | mac/: `P17-DOE-the-control-clips-too.actions` |
| P27 | backend feature coverage: the views whose absence used to abort the app. | 0 | 0 | mac/: `P27-scroll-the-webview.actions` |
| P38 | web view: does a page actually render, and does navigation report back? | 0 | 0 | mac/: `P38-scroll-the-web-view.actions` |
| P59 | does @SceneStorage keep two windows apart, and does @AppStorage not? | 4 | 4 | mac/: `P59-two-windows-one-typed-gtk4.actions`, `P59-two-windows-one-typed.actions` |
| P60 | does the Settings scene appear, and does it appear as the right thing | 2 | 5 | mac/: `P60-open-settings.actions` |
| P72 | does the backend actually RENDER a 3D scene, or only accept one? (M10) | 8 | 18 | mac/: `P72-context-menu-gtk4.actions`, `P72-context-menu.actions`, `P72-cursor.actions` |
| P75 | handing things to the system -- reveal a file, open a URL, choose where to | 4 | 10 | mac/: `P75-reveal-a-file-gtk4.actions`, `P75-reveal-a-file.actions` |
| P77 | one triangle mesh past 1,000,000 vertices, drawn with 32-bit indices | 1 | 0 | none -- design from the source |
| P78 | does `.onOpenURL` hear the URL an app is opened with, and the ones sent | 0 | 1 | none -- design from the source |
| P79 | is an AndroidViewRepresentable dismantled when it leaves the view graph? | 2 | 0 | none -- design from the source |
| P81 | a sheet, an alert, a popover and an open dialog, from either of two | 7 | 0 | none -- design from the source |
| P84 | does Image draw SVG, the same on every backend? | 3 | 0 | mac/: `P84-features-alpha-gtk4.actions`, `P84-larger-gtk4.actions`, `P84-larger.actions` |
| P85 | SVG <text> drawn by each platform's own text engine (2026-10-09). | 0 | 0 | none -- design from the source |
| P86 | translucent meshes in a Mesh3DView -- `Mesh3D.opacity` (2026-10-10). | 0 | 0 | none -- design from the source |
| P87 | SVG paint servers and effects (2026-10-10). | 0 | 0 | none -- design from the source |
| P88 | onContinuousHover -- where the pointer is, and which modifier keys are held (2026-10-10). | 4 | 0 | mac/: `P88-hover-cmd-drag-gtk4.actions`, `P88-hover-cmd-drag.actions` |
| P89 | .offset on text inside an overlay, static, changed later, and appearing later (2026-10-10). | 0 | 0 | none -- design from the source |
| P90 | the wheel date pickers in one region after another (2026-10-10). | 4 | 0 | none -- design from the source |
| P92 | CommandGroup -- commands placed in the system's own menu groups, as in SwiftUI (2026-10-13). | 13 | 0 | mac/: `P92-click-drag-copy-gtk4.actions`, `P92-click-drag-copy.actions`, `P92-undo-gtk4.actions` |
| P93 | several window scenes and the menus -- File > New and the Window menu's list (2026-10-14). | 1 | 0 | none -- design from the source |
| P95 | a mesh view that fills its window, holding one circle that faces the camera. | 0 | 0 | none -- design from the source |

## WSL (78)

| App | What it tests (first line of the source) | Input sites | Log writes | Port from |
|---|---|---|---|---|
| P0 | Windows repro app: | 8 | 0 | win/: `P0-present-environment-alert.actions` |
| P1 | Windows repro app: | 7 | 0 | win/: `P1-open-root-sheet.actions` |
| P2 | Windows repro app: | 14 | 0 | win/: `P2-controls-and-resizing.actions` |
| P3 | Windows repro app: | 5 | 0 | win/: `P3-sidebar-and-image.actions` |
| P4 | Windows exploration app: | 20 | 0 | win/: `P4-row-callback.actions` |
| P6 | stream player test app: | 14 | 57 | mac/: `P6-transport-toggles.actions` |
| P7 | Linux (GtkBackend) repro app: lists and split views. | 3 | 0 | win/: `P7-list-selection.actions` |
| P11 | macOS (AppKitBackend) repro app: sliders, scrollbars and date pickers. | 13 | 2 | win/: `P11-clamped-sliders.actions` |
| P12 | Android (AndroidBackend) repro app: button margins, state across | 9 | 0 | mac/: `P12-tabs-margins-and-toggles-gtk4.actions`, `P12-tabs-margins-and-toggles.actions` |
| P14 | iOS (UIKitBackend) repro app: size proposals across rotation, and the | 3 | 0 | mac/: `P14-width-history-and-theme-control.actions` |
| P15 | Linux (GtkBackend) repro app: colour scheme and window minimum height. | 7 | 0 | win/: `P15-colour-scheme.actions` |
| P15-DARK | does preferredColorScheme(.dark) actually take effect? (#386) | 3 | 0 | mac/: `P15-DARK-button-under-an-overridden-scheme-gtk4.actions`, `P15-DARK-button-under-an-overridden-scheme.actions` |
| P16 | Windows (WinUIBackend) repro app: NavigationSplitView initial layout. | 2 | 1 | win/: `P16-force-update-winui.actions` |
| P17-DOE | a design-of-experiments app for the #389 image-clipping fix. | 0 | 0 | mac/: `P17-DOE-the-control-clips-too.actions` |
| P18 | file dialogs, for comparing WinUIBackend against GtkBackend. | 3 | 1 | win/: `P18-three-dialogs.actions` |
| P20 | nested menus, for comparing WinUIBackend against GtkBackend. | 13 | 5 | win/: `P20-ctrl-k-shortcut.actions`, `P20-disabled-item.actions`, `P20-open-level-1.actions` |
| P22 | text styles, for comparing WinUIBackend against GtkBackend. | 3 | 1 | win/: `P22-weights.actions` |
| P25 | drag and drop, for comparing how a dropped file arrives across backends | 0 | 4 | win/: `P25-drop-zones-at-rest.actions` |
| P27 | backend feature coverage: the views whose absence used to abort the app. | 0 | 0 | mac/: `P27-scroll-the-webview.actions` |
| P28 | macOS hit-testing: a disabled overlay must let clicks reach the button | 1 | 3 | win/: `P28-click-through-overlay.actions` |
| P30 | effects and animation: current visual/geometric effects, plus animation gaps. | 1 | 2 | win/: `P30-toggle-frame-width.actions` |
| P32 | accessibility baseline: inspect this window with platform accessibility tools. | 5 | 3 | win/: `P32-empty-label-button.actions` |
| P33 | missing views: compileable approximations beside the missing SwiftUI names. | 5 | 3 | win/: `P33-hide-details.actions` |
| P34 | lazy containers and large collections: eager row construction probe. | 12 | 4 | win/: `P34-scroll-to-row-50.actions`, `P34-show-more-rows.actions` |
| P35 | state and scene composition: compileable state baseline plus structural gaps. | 2 | 2 | win/: `P35-increment-count.actions` |
| P36 | API-shape compatibility: SwiftCrossUI forms beside SwiftUI call-site gaps. | 11 | 2 | win/: `P36-focus-only-no-typing.actions`, `P36-string-label-button.actions`, `P36-textfieldstyle-recommit.actions` |
| P37 | window level: does `.topmost()` actually keep the window in front? | 0 | 0 | win/: `P37-floating-level.actions` |
| P38 | web view: does a page actually render, and does navigation report back? | 0 | 0 | mac/: `P38-scroll-the-web-view.actions` |
| P39 | visual effects: opacity, blur and the colour adjustments. | 0 | 0 | win/: `P39-read-nine-cells-against-the-control.actions` |
| P40 | geometric effects: offset, rotation, scale and an arbitrary matrix. | 0 | 0 | win/: `P40-read-seven-tiles-and-the-clipping.actions` |
| P42 | does the window scale factor follow a display-scale change while the app | 0 | 7 | win/: `P42-scale-factor-at-launch.actions` |
| P43 | is a gradient clipped to the shape, or does it fill a rectangle? | 0 | 1 | win/: `P43-gradient-clipped-to-the-shape.actions` |
| P44 | clipping: does `clipped()` cut a child down to its frame? | 3 | 1 | win/: `P44-clip-third-cell.actions` |
| P45 | toggles driven through a computed binding. | 7 | 7 | win/: `P45-computed-binding-toggle.actions` |
| P47 | draws every symbol in the table, on whatever backend it was built for. | 1 | 3 | win/: `P47-draw-every-symbol.actions` |
| P48 | exercises LazyVGrid, the first of the three views task #33 still listed as | 2 | 2 | win/: `P48-expand-colorpicker.actions` |
| P49 | exercises the presentation modifiers of task #36. | 6 | 7 | win/: `P49-show-fullscreen-cover.actions` |
| P50 | is the picture of the two view features that landed on 2026-09-08 and | 9 | 10 | win/: `P50-arrow-edge-bottom-gtk4.actions`, `P50-arrow-edge-gtk4.actions`, `P50-arrow-edge.actions` |
| P51 | is the first picture of the six views that landed on 2026-09-08. | 6 | 3 | win/: `P51-scroll-to-adaptive.actions` |
| P52 | measures what a custom `ButtonStyle` costs against a `PrimitiveButtonStyle`, | 2 | 9 | win/: `P52-scroll-to-separation.actions` |
| P53 | exercises .toolbar, the first of task #36's two remaining modifiers. | 0 | 5 | win/: `P53-control-click-close.actions`, `P53-press-toolbar-add.actions`, `P53-winui-press-toolbar-add.actions` |
| P54 | exercises `.refreshable`, added 2026-09-09 for Q7. | 6 | 3 | win/: `P54-press-the-refresh.actions` |
| P55 | does a real press flip `configuration.isPressed`? | 1 | 3 | win/: `P55-press-the-styled-button.actions` |
| P56 | does ScrollViewReader actually scroll? | 15 | 4 | win/: `P56-jump-to-row-59.actions` |
| P59 | does @SceneStorage keep two windows apart, and does @AppStorage not? | 4 | 4 | mac/: `P59-two-windows-one-typed-gtk4.actions`, `P59-two-windows-one-typed.actions` |
| P60 | does the Settings scene appear, and does it appear as the right thing | 2 | 5 | mac/: `P60-open-settings.actions` |
| P61 | does Slider.onEditingChanged report a DRAG, and only a drag? | 3 | 5 | win/: `P61-drag-the-trough.actions` |
| P64 | does the frame clock (#28) actually tick, and at what rate? | 0 | 8 | win/: `P64-measure-the-frame-clock.actions` |
| P65 | the three continuous gestures (#32). | 1 | 7 | win/: `P65-drag-the-panel.actions` |
| P66 | does `withAnimation` actually produce intermediate values (#28)? | 0 | 9 | win/: `P66-animation-samples.actions` |
| P67 | what does a screen reader hear when it lands on each of these buttons? | 3 | 6 | win/: `P67-accessibility-names.actions` |
| P68 | what does `-GPU N` do on this backend? | 0 | 2 | win/: `P68-list-the-adapters.actions` |
| P69 | do the four `.accessibility*` modifiers reach the screen reader? (#123) | 3 | 7 | win/: `P69-narrator-walk.actions` |
| P70 | does `@FocusState` move the keyboard, and does it hear it move? (#122) | 7 | 4 | win/: `P70-focus-gtk4.actions`, `P70-focus.actions` |
| P71 | does a menu item's keyboard shortcut actually fire it? (#121) | 4 | 4 | win/: `P71-shortcuts.actions` |
| P72 | does the backend actually RENDER a 3D scene, or only accept one? (M10) | 8 | 18 | mac/: `P72-context-menu-gtk4.actions`, `P72-context-menu.actions`, `P72-cursor.actions` |
| P73 | a publish that lands while the view graph is still being built. | 0 | 3 | win/: `P73-publish-during-build.actions` |
| P74 | every picker style, side by side, each with its own readout. | 6 | 6 | win/: `P74-choose-in-every-style.actions` |
| P75 | handing things to the system -- reveal a file, open a URL, choose where to | 4 | 10 | mac/: `P75-reveal-a-file-gtk4.actions`, `P75-reveal-a-file.actions` |
| P76 | lines, points, unlit faces, overlays and an orthographic camera in a | 2 | 0 | win/: `P76-projection.actions` |
| P77 | one triangle mesh past 1,000,000 vertices, drawn with 32-bit indices | 1 | 0 | none -- design from the source |
| P78 | does `.onOpenURL` hear the URL an app is opened with, and the ones sent | 0 | 1 | none -- design from the source |
| P79 | is an AndroidViewRepresentable dismantled when it leaves the view graph? | 2 | 0 | none -- design from the source |
| P81 | a sheet, an alert, a popover and an open dialog, from either of two | 7 | 0 | none -- design from the source |
| P83 | does .listStyle(.sidebar) change how a List is drawn? | 0 | 0 | win/: `P83-select-in-both-lists.actions` |
| P84 | does Image draw SVG, the same on every backend? | 3 | 0 | mac/: `P84-features-alpha-gtk4.actions`, `P84-larger-gtk4.actions`, `P84-larger.actions` |
| P85 | SVG <text> drawn by each platform's own text engine (2026-10-09). | 0 | 0 | none -- design from the source |
| P86 | translucent meshes in a Mesh3DView -- `Mesh3D.opacity` (2026-10-10). | 0 | 0 | none -- design from the source |
| P87 | SVG paint servers and effects (2026-10-10). | 0 | 0 | none -- design from the source |
| P88 | onContinuousHover -- where the pointer is, and which modifier keys are held (2026-10-10). | 4 | 0 | mac/: `P88-hover-cmd-drag-gtk4.actions`, `P88-hover-cmd-drag.actions` |
| P89 | .offset on text inside an overlay, static, changed later, and appearing later (2026-10-10). | 0 | 0 | none -- design from the source |
| P90 | the wheel date pickers in one region after another (2026-10-10). | 4 | 0 | none -- design from the source |
| P91 | .focusable() -- a view that is not a control takes the keyboard focus (2026-10-13). | 5 | 0 | win/: `P91-focusable.actions` |
| P92 | CommandGroup -- commands placed in the system's own menu groups, as in SwiftUI (2026-10-13). | 13 | 0 | mac/: `P92-click-drag-copy-gtk4.actions`, `P92-click-drag-copy.actions`, `P92-undo-gtk4.actions` |
| P93 | several window scenes and the menus -- File > New and the Window menu's list (2026-10-14). | 1 | 0 | none -- design from the source |
| P95 | a mesh view that fills its window, holding one circle that faces the camera. | 0 | 0 | none -- design from the source |
| P102 | long-press drag selection in text fields -- longPressTextSelection(), | 3 | 0 | win/: `P102-long-press-drag.actions` |
| P108 | GSAP's Draggable with InertiaPlugin as `.inertialDrag(offset:bounds:)` | 2 | 0 | win/: `P108-throw-gtk4.actions`, `P108-throw.actions` |
