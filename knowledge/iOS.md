# iOS

UIKitBackend, the iPhone and iPad simulators, building with xcodebuild and
action-file replay through XCUITest. Index as of 2026-10-24; each line links
one topic.

## Toolchain and build

- [Environment and devices](iOS/environment-and-devices.md) -- full Xcode, an iOS 27 runtime, the `swift-cross-ui` device (iPhone 17 Pro Max, 440x956 pt) and the iPad Pro 11-inch (M5); simctl commands.
- [Building with compile.zsh -ios](iOS/build-xcodebuild.md) -- xcodebuild, one app per build in `.compile-work-ios`, bundle from appTemplate, `output/<Pn>-ios.app`; no Swift Bundler since 2026-10-05.
- [Build pitfalls](iOS/build-pitfalls.md) -- Xcode's custom build location and stale executables, the PIF cache, CC/CXX, SCUI_DEBUG cached with the manifest.
- [Real SDK version and UIScene](iOS/sdk-version-and-uiscene.md) -- link-sdk.xcconfig ends the zoomed 428x926 run; iOS 27 refuses apps without the scene life cycle.

## Harness

- [Running one app](iOS/harness-run.md) -- test_ios.zsh: the `debugTarget` bundle, log stream, captures through a temp file, stdout through a pty.
- [Action-file replay](iOS/action-file-replay.md) -- the XCUITest runner, staging off `/Volumes`, every verb's iOS meaning, `# fresh-install`, `# app-args`.
- [Self-running apps](iOS/self-running-apps.md) -- the runner holds the main thread 0.8-0.9 s on attach; sleep-only files run without it and pass by "still running".
- [Aiming](iOS/aiming.md) -- a tap on empty space is not an error; `--dump-tree`, ios_aim_check.py, `IOS_AIM` re-aiming.
- [Sweeps and verification](iOS/sweep-and-verification.md) -- sweep_apple.zsh --ios, what `pass` means, the crash override, verify_effect_ios.zsh; 127 files on 2026-10-22.
- [iPad](iOS/ipad.md) -- Windowed Apps setup, scenes, no programmatic size, backboardd aborts, what is verified.
- [Sharing the simulator](iOS/simulator-sharing.md) -- SoftPCB gets the simulator first; the per-platform lock; one platform at a time.

## Backend behaviour

- [RootScrollHost](iOS/root-scroll-host.md) -- actualView/rwdView, placement rules, and the root causes behind "only the first tap lands".
- [Hit testing](iOS/hit-testing.md) -- children outside their container stay tappable; transparent layers pass taps through.
- [Menus, shortcuts and keys](iOS/menus-keys-shortcuts.md) -- the iPad menu bar against SwiftUI, `keyCommands` on iPhone, modifier release and arrow-key strings.
- [Visual effects and colour](iOS/visual-effects-and-colour.md) -- `CALayer.filters` ignored on iOS, the Core Image path, Generic RGB vs sRGB.
- [Pointer, hover and cursors](iOS/pointer-hover-cursors.md) -- a held finger is hover; a synthesized pointer path drives iPad hover; drawn cursor shapes.
- [Windows and presentations](iOS/windows-and-presentations.md) -- the unclosable iPhone window, PhoneSplitWidget, popovers that stay popovers, sheets, alerts.

## Performance

- [Performance numbers](iOS/performance.md) -- 60 Hz frame clock, update timings against macOS and Android, list rows and memory, app size.

## Known limits and open items

- [Open items](iOS/open-items.md) -- open problems with dates, platform limits, and documents known to be stale.

---

# iOS

UIKitBackend、iPhone 與 iPad 模擬器、以 xcodebuild 建置，以及經由 XCUITest 的動作檔重放。索引截至 2026-10-24;每一行連到一個主題。

## 工具鏈與建置

- [環境與裝置](iOS/environment-and-devices.md) -- 完整的 Xcode、iOS 27 runtime、`swift-cross-ui` 裝置(iPhone 17 Pro Max,440x956 pt)與 iPad Pro 11-inch (M5);simctl 指令。
- [以 compile.zsh -ios 建置](iOS/build-xcodebuild.md) -- xcodebuild、在 `.compile-work-ios` 中一次一支 app、由 appTemplate 組成 bundle、`output/<Pn>-ios.app`;2026-10-05 起不用 Swift Bundler。
- [建置陷阱](iOS/build-pitfalls.md) -- Xcode 自訂建置位置與陳舊執行檔、PIF 快取、CC/CXX、隨 manifest 快取的 SCUI_DEBUG。
- [真正的 SDK 版本與 UIScene](iOS/sdk-version-and-uiscene.md) -- link-sdk.xcconfig 結束 428x926 的放大執行;iOS 27 拒絕未採用 scene 生命週期的 app。

## Harness

- [執行一支 app](iOS/harness-run.md) -- test_ios.zsh:`debugTarget` bundle、log stream、經暫存檔的擷圖、經 pty 的 stdout。
- [動作檔重放](iOS/action-file-replay.md) -- XCUITest runner、避開 `/Volumes` 的暫存、每個動作在 iOS 上的意義、`# fresh-install`、`# app-args`。
- [自行執行步驟的 app](iOS/self-running-apps.md) -- runner 附加時佔住主執行緒 0.8–0.9 秒;只有 sleep 的檔案不經 runner,以「仍在執行」判定通過。
- [瞄準](iOS/aiming.md) -- 點在空白處不是錯誤;`--dump-tree`、ios_aim_check.py、`IOS_AIM` 重新瞄準。
- [Sweep 與驗證](iOS/sweep-and-verification.md) -- sweep_apple.zsh --ios、`pass` 的意義、當機優先、verify_effect_ios.zsh;2026-10-22 共 127 份檔案。
- [iPad](iOS/ipad.md) -- Windowed Apps 設定、scene、無法以程式設定大小、backboardd 中止、已驗證的項目。
- [共用模擬器](iOS/simulator-sharing.md) -- SoftPCB 優先使用模擬器;每個平台一把鎖;一次一個平台。

## Backend 行為

- [RootScrollHost](iOS/root-scroll-host.md) -- actualView/rwdView、擺放規則，以及「只有第一次點擊點得到」背後的根本原因。
- [點擊判定](iOS/hit-testing.md) -- 位於容器外的子 view 仍可點擊;透明圖層讓點擊穿過。
- [選單、快捷鍵與按鍵](iOS/menus-keys-shortcuts.md) -- iPad 選單列與 SwiftUI 比對、iPhone 上的 `keyCommands`、修飾鍵放開與方向鍵字串。
- [視覺效果與色彩](iOS/visual-effects-and-colour.md) -- iOS 忽略 `CALayer.filters`、Core Image 路徑、Generic RGB 與 sRGB。
- [指標、懸停與游標](iOS/pointer-hover-cursors.md) -- 按住的手指就是懸停;以合成指標路徑驅動 iPad 懸停;自行繪製的游標形狀。
- [視窗與呈現方式](iOS/windows-and-presentations.md) -- 關不掉的 iPhone 視窗、PhoneSplitWidget、維持 popover 的 popover、sheet、警示。

## 效能

- [效能數字](iOS/performance.md) -- 60 Hz frame clock、與 macOS 和 Android 比較的更新耗時、清單列與記憶體、app 大小。

## 已知限制與未解事項

- [未解事項](iOS/open-items.md) -- 附日期的未解問題、平台限制，以及已知過時的文件。
