# The iPad simulator

What differs on iPad and how the `-ipad` action files are run. Device: iPad
Pro 11-inch (M5), iOS 27.0, 834x1210 pt at @2x (capture pixels / 2 = points).
Checked 2026-10-24.

## Running

`zsh testapp/test.zsh <Pn> --ios --device "iPad Pro 11-inch (M5)" --actionfile
testapp/actions/ios/<Pn>-<name>-ipad.actions`. The iPhone sweep skips these
files. 14 exist as of 2026-10-20.

## Windowed Apps, once per device

A fresh iPad simulator runs every scene full screen, so a second window hides
the first. Turn on Settings > Multitasking & Gestures > Windowed Apps once per
device, by running `testapp/test_support/ipad-windowed-apps.csv` as an action
file with any app as host: it `activate`s `com.apple.Preferences` and presses
by label (labels survive layout differences between devices and OS versions).
`defaults write` (WindowManager, springboard keys) did not switch it
(2026-09-30). The setting persists in the simulator.

## Windows and scenes

- `supportsMultipleWindows` is `UIApplication.shared.supportsMultipleScenes`:
  true on iPad, false on iPhone. Until 2026-09-30 it was `false` everywhere, so
  `openWindow` was ignored and P5's second window never appeared. A later scene
  takes a window SwiftCrossUI already created (`pendingSceneWindows` in
  `SceneDelegate`). Older notes saying UIKit does not support multiple windows
  (settings-scene.md, completed.md:601) are superseded.
- **No programmatic window size.** In the iOS 27 SDK
  `UIWindowSceneGeometryPreferencesIOS` has only `interfaceOrientations`.
  `sizeRestrictions` pinned to 480x380 left the window at 834x1210, and three
  runs of four the simulator's render server (backboardd) aborted in Metal
  texture validation and took the XCUITest session with it (2026-10-02). A
  window is sized by its grip; the runner's held slow drag (mouseup `micros`)
  is the only thing that moves one. Avoid window drags where not needed.
- Closing: with multiple scenes the window's scene session is ended. P75 on
  iPad closes to the home screen; its `.onDisappear` line appeared only after
  a static URL handler in ViewGraph stopped holding the first window's view
  graph (`[weak self]`, found with `leaks --traceTree`, 2026-10-22).
- `# fresh-install` in a file discards restored windows (iPadOS reopens all
  windows of the last run).
- Use `origin` `screen` or `taplabel` for rows that must hit a specific window:
  `app.windows.firstMatch` is not reliably the same window.

## Pointer, cursors, menu bar

- Hover reaches the app only through the runner's synthesized pointer path;
  `XCUICoordinate.hover()` delivered the first call of a run and mostly not the
  rest, without modifiers (2026-10-13). See
  [pointer-hover-cursors.md](pointer-hover-cursors.md).
- iPadOS draws its pointer into the framebuffer, so a capture shows the cursor.
- The menu bar is built and compared against a SwiftUI reference
  ([menus-keys-shortcuts.md](menus-keys-shortcuts.md)).

## Verified on the simulator (2026-10-13 to 2026-10-22)

P5 alerts on two windows, P59 and P62 two windows, P14 rotation (width 802
portrait, 1178 landscape, once the file switches to rwdView), P16 split
columns, P50 popover (a real popover, not the phone's sheet), P71 shortcuts
through the hardware keyboard, P72 and P80 cursors, P88 hover, P91 focus with
Tab, P92 menu bar, P94 undo.

## Open (checked 2026-10-20)

- No physical iPad, and no trackpad, has been tried; the simulator was accepted
  in its place (2026-10-15).

---

# iPad 模擬器

iPad 有何不同，以及 `-ipad` 動作檔怎麼執行。裝置:iPad Pro 11-inch (M5),iOS 27.0,834x1210 pt、@2x
(擷圖像素 / 2 = 點)。2026-10-24 確認。

## 執行

`zsh testapp/test.zsh <Pn> --ios --device "iPad Pro 11-inch (M5)" --actionfile
testapp/actions/ios/<Pn>-<名稱>-ipad.actions`。iPhone 的 sweep 會略過這些檔案。截至 2026-10-20 共 14 份。

## Windowed Apps,每台裝置一次

新的 iPad 模擬器讓每個 scene 全螢幕執行，所以第二個視窗會蓋住第一個。每台裝置要打開一次「設定 > 多工處理與手勢 >
Windowed Apps」:把 `testapp/test_support/ipad-windowed-apps.csv` 當成動作檔，以任何 app 為宿主執行;它會
`activate` `com.apple.Preferences` 並依標籤點擊(標籤在不同裝置與 OS 版本間不受版面差異影響)。`defaults write`
(WindowManager、springboard 的鍵)切換不了(2026-09-30)。這個設定會保留在模擬器中。

## 視窗與 scene

- `supportsMultipleWindows` 是 `UIApplication.shared.supportsMultipleScenes`:iPad 上為 true,iPhone 上為 false。
  2026-09-30 之前它在各處都是 `false`,所以 `openWindow` 被忽略,P5 的第二個視窗從未出現。後來的 scene 會接手
  SwiftCrossUI 已建立的視窗(`SceneDelegate` 中的 `pendingSceneWindows`)。舊筆記中「UIKit 不支援多視窗」的說法
  (settings-scene.md、completed.md:601)已被取代。
- **無法以程式設定視窗大小。** iOS 27 SDK 的 `UIWindowSceneGeometryPreferencesIOS` 只有
  `interfaceOrientations`。把 `sizeRestrictions` 釘在 480x380 後視窗仍是 834x1210,而且四次中有三次模擬器的渲染
  伺服器(backboardd)在 Metal 紋理驗證中中止，連帶讓 XCUITest 工作階段結束(2026-10-02)。視窗由它的把手調整大小;
  runner 的按住慢速拖曳(mouseup 的 `micros`)是唯一能移動視窗的方式。不需要時避免拖曳視窗。
- 關閉：有多個 scene 時會結束視窗的 scene session。iPad 上的 P75 關閉後回到主畫面;它的 `.onDisappear` 那一行，
  要等 ViewGraph 中一個靜態 URL handler 不再持有第一個視窗的 view graph 之後才出現(`[weak self]`,以
  `leaks --traceTree` 找到,2026-10-22)。
- 檔案中的 `# fresh-install` 會丟棄被恢復的視窗(iPadOS 會重新打開上次執行的所有視窗)。
- 必須點中特定視窗的列，請用 `origin` `screen` 或 `taplabel`:`app.windows.firstMatch` 不一定是同一個視窗。

## 指標、游標、選單列

- 懸停只有經由 runner 合成的指標路徑才會到達 app;`XCUICoordinate.hover()` 只送達一次執行中的第一次呼叫，
  之後大多沒有，而且不帶修飾鍵(2026-10-13)。見 [pointer-hover-cursors.md](pointer-hover-cursors.md)。
- iPadOS 把指標畫進 framebuffer,所以擷圖中看得到游標。
- 選單列的建立方式與 SwiftUI 參考 app 比對過([menus-keys-shortcuts.md](menus-keys-shortcuts.md))。

## 已在模擬器上驗證(2026-10-13 至 2026-10-22)

P5 兩個視窗上的警示、P59 與 P62 兩個視窗、P14 旋轉(檔案先切到 rwdView 後，直向寬 802、橫向 1178)、P16 分割欄、
P50 popover(真正的 popover,不是手機上的 sheet)、P71 經硬體鍵盤的快捷鍵、P72 與 P80 游標、P88 懸停、P91 以 Tab
切換焦點、P92 選單列、P94 復原。

## 未解(2026-10-20 確認)

- 沒有試過實體 iPad,也沒有試過觸控板;已接受以模擬器代替(2026-10-15)。
