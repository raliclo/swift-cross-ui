# iOS environment and simulator devices

What a Mac needs to build and run the test apps on the iOS Simulator, and which
devices the results were measured on. Checked 2026-10-24.

## Setup

`zsh testapp/install_tools_ios.zsh` (also run by `compile.zsh -ios`):

- requires a full Xcode (`xcode-select -p` must contain
  `Platforms/iPhoneSimulator.platform`); Command Line Tools alone have no
  iPhoneSimulator SDK and no xcodebuild;
- requires an iOS runtime in `xcrun simctl runtime list` marked `(Ready)`;
  `xcodebuild -downloadPlatform iOS` fetches one (several GB, offered, not run);
- creates the device `swift-cross-ui` if missing, as `IOS_SIM_DEVICE_TYPE`
  (default "iPhone 16") on the newest iOS runtime;
- `--check` reports only, `--print-env` prints `IOS_SIM_DEVICE`, the UDID and
  the SDK path.

`simctl list devices available` showing nothing does not mean no runtime: a
fresh Xcode has runtimes but no devices. Check `simctl runtime list`.

## Devices actually used

| Device | Size | Notes |
|---|---|---|
| `swift-cross-ui`: iPhone 17 Pro Max, iOS 27.0 | 440x956 pt, @3x | the iPhone named in results from 2026-09-16 on (completed.md:250); sweep_apple records it as `swift-cross-ui (iPhone 17 Pro Max, iOS 27.0)` |
| iPad Pro 11-inch (M5), iOS 27.0 | 834x1210 pt, @2x | the `-ipad` files, `--device "iPad Pro 11-inch (M5)"` |

- The installer's default type ("iPhone 16") is not what the existing
  `swift-cross-ui` device is. Older notes giving 393x852 pt (flow.md, 2026-09-03;
  actions/ios/README.md) describe the iPhone 16 and are stale for results.
- Only an iOS 27 runtime is installed (2026-10-06). iOS 13-15 code paths
  (e.g. sheet detents before iOS 16) are built but never run.
- Any device: `--device <name|UDID>` on test.zsh/test_ios.zsh, or
  `IOS_SIM_DEVICE`. A 36-character UDID is passed to xcodebuild as `id=`,
  anything else as `name=`.
- Each action file's header states its device's point size, capture size and
  scale; the iPhone (440 pt) and the Android emulator (411 dp) are not resized
  to match (decision of 2026-09-03).

## Useful simctl commands

- `xcrun simctl ui swift-cross-ui appearance dark` switches appearance.
- `xcrun simctl spawn swift-cross-ui log stream --style compact --predicate
  'process == "debugTarget"'` follows the app's unified log.
- `xcrun simctl io swift-cross-ui screenshot <file>` captures the device
  framebuffer; exit 148 for an unknown device and 60 for a shut-down one, with
  no file left.

## Evidence

testapp/install_tools_ios.zsh; matrix_coverage/results.csv2 device column
(ios rows of 2026-10-22: 130 iPhone 17 Pro Max, 9 iPad Pro 11-inch (M5));
completed.md:250-253, :1517, :1737; flow.md:95-107.

---

# iOS 環境與模擬器裝置

Mac 在 iOS 模擬器上建置與執行測試 app 需要什麼，以及結果是在哪些裝置上量的。2026-10-24 確認。

## 設定

`zsh testapp/install_tools_ios.zsh`(`compile.zsh -ios` 也會執行它):

- 需要完整的 Xcode(`xcode-select -p` 底下必須有 `Platforms/iPhoneSimulator.platform`);只有
  Command Line Tools 時沒有 iPhoneSimulator SDK,也沒有 xcodebuild;
- 需要 `xcrun simctl runtime list` 中標為 `(Ready)` 的 iOS runtime;`xcodebuild -downloadPlatform iOS`
  可下載(數 GB,只提示指令，不自動執行);
- 缺少時建立裝置 `swift-cross-ui`,機型為 `IOS_SIM_DEVICE_TYPE`(預設「iPhone 16」),用最新的 iOS runtime;
- `--check` 只回報,`--print-env` 印出 `IOS_SIM_DEVICE`、UDID 與 SDK 路徑。

`simctl list devices available` 什麼都沒列，不代表沒有 runtime:新裝的 Xcode 有 runtime 但沒有裝置。
請看 `simctl runtime list`。

## 實際使用的裝置

| 裝置 | 尺寸 | 說明 |
|---|---|---|
| `swift-cross-ui`:iPhone 17 Pro Max,iOS 27.0 | 440x956 pt,@3x | 2026-09-16 起結果中記載的 iPhone(completed.md:250);sweep_apple 記為 `swift-cross-ui (iPhone 17 Pro Max, iOS 27.0)` |
| iPad Pro 11-inch (M5),iOS 27.0 | 834x1210 pt,@2x | `-ipad` 檔案,`--device "iPad Pro 11-inch (M5)"` |

- 安裝程式的預設機型(「iPhone 16」)不是現有 `swift-cross-ui` 裝置的機型。舊筆記中的 393x852 pt
  (flow.md,2026-09-03;actions/ios/README.md)描述的是 iPhone 16,對結果而言已經過時。
- 只裝了 iOS 27 runtime(2026-10-06)。iOS 13–15 的程式路徑(例如 iOS 16 之前的 sheet detent)
  有建置但從未執行。
- 指定裝置:test.zsh/test_ios.zsh 的 `--device <名稱|UDID>`,或 `IOS_SIM_DEVICE`。36 個字元的 UDID
  以 `id=` 傳給 xcodebuild,其他以 `name=`。
- 每份動作檔的標頭註明裝置的點尺寸、擷圖尺寸與縮放倍率;iPhone(440 pt)與 Android 模擬器(411 dp)
  不調成一致(2026-09-03 的決定)。

## 好用的 simctl 指令

- `xcrun simctl ui swift-cross-ui appearance dark` 切換外觀。
- `xcrun simctl spawn swift-cross-ui log stream --style compact --predicate 'process == "debugTarget"'`
  追蹤 app 的 unified log。
- `xcrun simctl io swift-cross-ui screenshot <檔案>` 擷取裝置的 framebuffer;裝置不存在時結束碼 148、
  已關機時 60,兩者都不留檔案。

## 證據

testapp/install_tools_ios.zsh;matrix_coverage/results.csv2 的 device 欄(2026-10-22 的 ios 列:
130 列 iPhone 17 Pro Max、9 列 iPad Pro 11-inch (M5));completed.md:250-253、:1517、:1737;flow.md:95-107。
