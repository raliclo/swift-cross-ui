# Building a test app for iOS: compile.zsh -ios

How `zsh testapp/compile.zsh -ios <Pn>` turns one test app into
`testapp/output/<Pn>-ios.app`. Checked against compile.zsh on 2026-10-24.

## What

- The build is `xcodebuild build -scheme <Pn> -destination 'generic/platform=iOS
  Simulator'`, run in `testapp/.compile-work-ios/`. Products land under
  `<package>/.build/<arch>-apple-iphonesimulator/Build/Products/<Config>-iphonesimulator/`.
- The executable is wrapped in a bundle assembled from
  `testapp/iosContainer/appTemplate.app` (Info.plist, PkgInfo). PlistBuddy sets
  `CFBundleExecutable`, `CFBundleName` and `CFBundleIdentifier`
  (`dev.swiftcrossui.testapp.<Pn>`). SwiftPM resource bundles
  (`*_<Pn>.bundle`) are copied beside the executable. The bundle is ad-hoc
  signed (`codesign --force --deep --sign -`), which is all a simulator app
  needs.
- The result is copied to `testapp/output/<Pn>-ios.app`. An iOS artefact is a
  directory, so its size is not `wc -c` of the name.
- The full xcodebuild output is kept in `testapp/output/ios-xcodebuild-<Pn>.log`.
- `compile.zsh -ios` runs `install_tools_ios.zsh` first, so a missing simulator
  device is found before a build of several minutes, not after.
- It takes the iOS platform lock (`test_support/platform_lock.zsh ios`).

## Why it is built this way

- **Not `swift build`.** `-Xswiftc -sdk <iphonesimulator>` applies to every
  target, including `SwiftCrossUIMacrosPlugin`, a compile-time tool that must be
  built for the host; the link then fails. xcodebuild separates host tools from
  target code.
- **One app per build, and the package is named after it.** xcodebuild derives
  scheme names from the package name. A package named `TestApps` has no scheme
  `P12`, and the failure reads "does not contain a scheme named P12", which looks
  like a missing target and is only a name mismatch. `-ios` with two apps exits
  with "-ios builds one app at a time".
- **A separate tree, `.compile-work-ios`.** Because iOS renames the package,
  sharing a tree with the macOS or WinUI builds flipped the manifest between
  `name: "P12"` and `name: "TestApps"`. The manifest is an llbuild input, so each
  flip re-planned the whole build (28-83 s per switch, measured for -gtk4).
- **No Swift Bundler.** Since 2026-10-05 (d97cfc25) the bundle is assembled from
  the template; a full iOS sweep built all 101 action files' apps with
  xcodebuild. The old fallback to Swift Bundler is gone: an xcodebuild failure
  exits 1 with "This is a defect to root-cause, not to work around", and the log
  gets the product's state and any stale `DerivedData/TestApps-*` folders.

## How to apply

- Build: `zsh testapp/compile.zsh -ios P12`. Install by hand:
  `xcrun simctl install swift-cross-ui testapp/output/P12-ios.app`, launch with
  `xcrun simctl launch swift-cross-ui dev.swiftcrossui.testapp.P12`.
- `SCUI_DEBUG` defaults to 1 in compile.zsh (the debug features, action-file
  replay and the view-mode button are compiled in). `SCUI_DEBUG=0` builds the
  control for A/B scripts such as `test_rootscroll_ios.zsh`. See
  [build-pitfalls.md](build-pitfalls.md) for why the value is stamped.
- Most runs do not call compile.zsh directly: `test_ios.zsh` rebuilds with
  `SCUI_DEBUG=1` unless given `-n`.

## Evidence

- testapp/compile.zsh, the `-ios` block (about lines 1725-2004) and the
  package-name note near line 1267.
- d97cfc25 (2026-10-05): 101 of 101 built by "xcodebuild + iosContainer".
- 8b45893a (2026-10-05): iOS builds without the bundler.

---

# 為 iOS 建置測試 app:compile.zsh -ios

`zsh testapp/compile.zsh -ios <Pn>` 如何把一支測試 app 變成 `testapp/output/<Pn>-ios.app`。
2026-10-24 對照 compile.zsh 確認。

## 內容

- 建置指令是 `xcodebuild build -scheme <Pn> -destination 'generic/platform=iOS Simulator'`,
  在 `testapp/.compile-work-ios/` 中執行。產物放在
  `<package>/.build/<arch>-apple-iphonesimulator/Build/Products/<Config>-iphonesimulator/`。
- 執行檔包進以 `testapp/iosContainer/appTemplate.app`(Info.plist、PkgInfo)組成的 bundle。
  PlistBuddy 設定 `CFBundleExecutable`、`CFBundleName` 與 `CFBundleIdentifier`
  (`dev.swiftcrossui.testapp.<Pn>`)。SwiftPM 的資源 bundle(`*_<Pn>.bundle`)複製到執行檔旁。
  bundle 以 ad-hoc 簽署(`codesign --force --deep --sign -`),模擬器 app 只需要這樣。
- 結果複製到 `testapp/output/<Pn>-ios.app`。iOS 產物是目錄，所以對名稱下 `wc -c` 不是它的大小。
- xcodebuild 的完整輸出保留在 `testapp/output/ios-xcodebuild-<Pn>.log`。
- `compile.zsh -ios` 會先執行 `install_tools_ios.zsh`,讓缺少模擬器裝置的狀況在建置前就被發現，
  而不是在數分鐘的建置之後。
- 它會取得 iOS 平台鎖(`test_support/platform_lock.zsh ios`)。

## 為什麼這樣建置

- **不用 `swift build`。** `-Xswiftc -sdk <iphonesimulator>` 會套用到每個 target,包括必須為主機
  建置的編譯期工具 `SwiftCrossUIMacrosPlugin`,連結因而失敗。xcodebuild 能區分主機工具與目標程式碼。
- **一次一支 app,套件以它命名。** xcodebuild 依套件名稱推導 scheme 名稱。名為 `TestApps` 的套件
  沒有 `P12` 這個 scheme,錯誤訊息是「does not contain a scheme named P12」,看起來像缺少 target,
  其實只是名稱不一致。`-ios` 帶兩支 app 會以「-ios builds one app at a time」結束。
- **獨立的目錄樹 `.compile-work-ios`。** 由於 iOS 會更改套件名稱，與 macOS 或 WinUI 共用目錄樹時，
  manifest 會在 `name: "P12"` 與 `name: "TestApps"` 之間來回切換。manifest 是 llbuild 的輸入之一，
  每次切換都重新規劃整個建置(-gtk4 實測每次切換 28–83 秒)。
- **不用 Swift Bundler。** 自 2026-10-05(d97cfc25)起 bundle 由範本組成;一次完整的 iOS sweep
  以 xcodebuild 建出全部 101 份動作檔的 app。舊的 Swift Bundler 後備已移除:xcodebuild 失敗時以
  「This is a defect to root-cause, not to work around」結束並回傳 1,日誌中會附上產物狀態與任何陳舊的
  `DerivedData/TestApps-*` 資料夾。

## 怎麼用

- 建置:`zsh testapp/compile.zsh -ios P12`。手動安裝:
  `xcrun simctl install swift-cross-ui testapp/output/P12-ios.app`,啟動:
  `xcrun simctl launch swift-cross-ui dev.swiftcrossui.testapp.P12`。
- compile.zsh 中 `SCUI_DEBUG` 預設為 1(debug 功能、動作檔重放與檢視模式按鈕都編譯進去)。
  `SCUI_DEBUG=0` 用來建出 A/B 腳本(如 `test_rootscroll_ios.zsh`)的對照組。為何要把這個值蓋印下來，
  見 [build-pitfalls.md](build-pitfalls.md)。
- 多數執行不直接呼叫 compile.zsh:`test_ios.zsh` 除非加 `-n`,都會以 `SCUI_DEBUG=1` 重建。

## 證據

- testapp/compile.zsh 的 `-ios` 區塊(約第 1725–2004 行)與第 1267 行附近的套件名稱說明。
- d97cfc25(2026-10-05):101 支全部「xcodebuild + iosContainer」建置。
- 8b45893a(2026-10-05):iOS 不經 bundler 建置。
