# The executable must name the real SDK, and adopt the UIScene life cycle

Two linked requirements that decide whether a test app runs at native size on
iOS 27. Written 2026-10-24 from link-sdk.xcconfig, compile.zsh and
UIKitBackend.swift.

## Symptom (before 2026-10-01)

Test apps ran zoomed: a 428x926 window on a 440x956 screen. Every action file
was measured in that zoomed space.

## Cause

- The Swift driver's link job gives clang `--sysroot <SDK>`, and clang reads an
  SDK's version only from `-isysroot` or `$SDKROOT`. Without either it uses the
  deployment target, so the executable said `sdk 15.0` while linked against the
  iOS 27 SDK. Measured 2026-10-01 by re-running the logged link line with
  `-###`: `-platform_version ios-simulator 15.0.0 15.0.0`, and `15.0.0 27.0`
  with `-isysroot` added.
- iOS treats an app claiming an old SDK as an old app: zoomed, and without the
  UIScene launch check. That check is why the old binaries ran at all: an app
  linked against the iOS 27 SDK that does not adopt the scene life cycle is
  refused at launch ("Application failed to launch: UIScene life cycle",
  measured 2026-09-30).

## Fix

- `testapp/iosContainer/link-sdk.xcconfig`, passed as `XCODE_XCCONFIG_FILE`:
  `OTHER_LDFLAGS = $(inherited) -Xclang-linker -isysroot -Xclang-linker $(SDKROOT)`.
- `ApplicationDelegate.application(_:configurationForConnecting:options:)`
  returns a configuration whose delegate is `SceneDelegate`; the app template's
  Info.plist declares `UIApplicationSceneManifest` with
  `UIApplicationSupportsMultipleScenes = true` (8272b7a2, 2026-09-30).
- compile.zsh **checks** rather than patches: it compares
  `xcrun vtool -show-build` against `xcrun --sdk iphonesimulator
  --show-sdk-version` and exits 1 if they differ. From 2026-09-30 to 2026-10-01
  a `vtool` rewrite patched the field; since 9d4b5057 the link writes it, so a
  mismatch means the xcconfig stopped reaching the link.

## How to apply

- Changing the native size moves every recorded point. The 2026-10-01 switch
  re-aimed 84 action files (71433077, da76b8b5).
- Do not remove `$(inherited)` from the xcconfig.

---

# 執行檔必須標明真正的 SDK,並採用 UIScene 生命週期

兩個相連的條件，決定測試 app 在 iOS 27 上是否以原生尺寸執行。2026-10-24 依 link-sdk.xcconfig、
compile.zsh 與 UIKitBackend.swift 寫成。

## 症狀(2026-10-01 之前)

測試 app 以放大模式執行:440x956 的螢幕上一個 428x926 的視窗。所有動作檔都是在那個放大座標中量的。

## 原因

- Swift driver 的連結步驟給 clang 的是 `--sysroot <SDK>`,而 clang 只從 `-isysroot` 或 `$SDKROOT`
  讀取 SDK 版本。兩者都沒有時它改用部署目標，於是執行檔與 iOS 27 SDK 連結，卻寫著 `sdk 15.0`。
  2026-10-01 以 `-###` 重跑記錄下來的連結指令實測:`-platform_version ios-simulator 15.0.0 15.0.0`,
  加上 `-isysroot` 後是 `15.0.0 27.0`。
- iOS 把宣稱舊 SDK 的 app 當成舊 app:放大執行，而且略過 UIScene 啟動檢查。舊執行檔之所以能跑，
  正是因為那項檢查被略過：與 iOS 27 SDK 連結卻未採用 scene 生命週期的 app,啟動時會被拒絕
  (「Application failed to launch: UIScene life cycle」,2026-09-30 實測)。

## 修正

- `testapp/iosContainer/link-sdk.xcconfig`,以 `XCODE_XCCONFIG_FILE` 傳入:
  `OTHER_LDFLAGS = $(inherited) -Xclang-linker -isysroot -Xclang-linker $(SDKROOT)`。
- `ApplicationDelegate.application(_:configurationForConnecting:options:)` 回傳 delegate 為
  `SceneDelegate` 的設定;app 範本的 Info.plist 宣告 `UIApplicationSceneManifest` 與
  `UIApplicationSupportsMultipleScenes = true`(8272b7a2,2026-09-30)。
- compile.zsh 只**檢查**、不修補：它比對 `xcrun vtool -show-build` 與
  `xcrun --sdk iphonesimulator --show-sdk-version`,不同就以 1 結束。2026-09-30 到 2026-10-01 曾用
  `vtool` 改寫該欄位;自 9d4b5057 起由連結步驟寫入，所以不一致代表 xcconfig 不再傳到連結步驟。

## 怎麼用

- 改變原生尺寸會移動每一個記錄下來的座標。2026-10-01 的切換重新瞄準了 84 份動作檔
  (71433077、da76b8b5)。
- 不要把 xcconfig 中的 `$(inherited)` 拿掉。
