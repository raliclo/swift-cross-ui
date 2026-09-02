# Android build times, and the four things that have to be right first

Measured 2026-09-02 on macOS 27.0, Apple silicon. Every number here came from
`date +%s` around a real run, not from an estimate.

## Times

| What | Time | Notes |
|---|---|---|
| Clean `swift build` (executable only) | **630 s** | against the 6.3.3-RELEASE SDK |
| Clean `swift build`, earlier run | 659 s | against the 6.3-SNAPSHOT SDK |
| Incremental, nothing changed | **10 s** | |
| Incremental, one app source file touched | **7 s** | |
| APK path, first run | **569 s** | 3078 Swift compile steps |
| APK path, second run | **166 s** | **4** Swift compile steps -- see step 5 |

The 166 s is almost entirely Gradle packaging the APK and adb installing it.
The Swift half is four steps. Before the two entry points were given separate
scratch paths it was 3078 steps every time, in both directions.

So: about **eleven minutes** the first time or after anything that invalidates
the tree, and **seven to ten seconds** for an ordinary edit to a `Pn`.

Two build trees exist, deliberately:

    testapp/.compile-work-android/TestApps/.build            compile.zsh -android
    testapp/.compile-work-android/TestApps/.build-bundler    test_android.zsh

They used to be one, and that was the ten-minute problem. See step 5.

## The two steps

    zsh testapp/install_tools_android.zsh      # 1. everything the build needs
    zsh testapp/test.zsh P12 --android         # 2. build, bundle, install, launch

`test.zsh --android` runs `install_tools_android.zsh --check` first, so a
missing prerequisite stops the run before it builds rather than ten minutes in.
`zsh testapp/compile.zsh -android P12` builds without installing, if that is all
you want.

## 兩個步驟

    zsh testapp/install_tools_android.zsh      # 1. 建置所需的一切
    zsh testapp/test.zsh P12 --android         # 2. 建置、打包、安裝、啟動

`test.zsh --android` 會先執行 `install_tools_android.zsh --check`，因此缺少前提時會在建置之前
停下，而不是建到十分鐘後才失敗。若只想建置而不安裝，用 `zsh testapp/compile.zsh -android P12`。

A finished clean tree is **1.8 GB**. It grows with reuse — a tree that had seen
several runs measured 5.6 GB. That figure is accumulation, not the cost of one
build, and a stale tree is worth deleting before believing a size.

The debug executable is **173 MB** unstripped.

## The four prerequisites

None of these is optional, and three of the four fail with an error that points
somewhere other than the cause.

### 1. A toolchain matching the Android SDK — not Xcode's

`swift` on a Mac is Xcode's. Measured 2026-09-02 that is **6.4**, the Android
SDK is **6.3.3**, and every module importing Foundation fails with

    error: module compiled with Swift 6.3.3 cannot be imported by the
    Swift 6.4 compiler

**This is not an out-of-date SDK.** swift.org's release list carries
`android-sdk` from 6.3 onward and stops at **6.3.3 (2026-06-29)**; there is no
6.4 Android SDK because 6.4 is not a published release. Xcode ships ahead of
that train. The host compiler is the thing that is wrong for this job.

    SWIFT_BIN=~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift

`compile.zsh` already reads `SWIFT_BIN`.

### 2. The release SDK does not ship an NDK — you have to link one in

This is the one that looks like a corrupt download. The **snapshot** bundle
contained `android-ndk-r27d` and a populated `ndk-sysroot`; the **release**
bundle has neither, while its `swift-sdk.json` still says
`"sdkRootPath": "ndk-sysroot"`. Every C target then fails with

    fatal error: 'sys/types.h' file not found
    fatal error: 'stdio.h' file not found

Run the script the bundle ships for exactly this:

```sh
export ANDROID_NDK_HOME=/Volumes/Windows/proj_Win/.android-sdk/ndk/27.0.12077973
bash ~/.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle/swift-android/scripts/setup-android-sdk.sh
```

It requires NDK **27 or newer** and refuses politely below that.

### 3. One Android SDK installed, not two

With both the snapshot and the release installed, every build prints

    warning: multiple Swift SDKs match target triple
    `aarch64-unknown-linux-android31` and host triple arm64-apple-macosx

and picks one for you. It picked the right one here, but "picks one for you" is
not a property to build on. Remove the one you are not using:

```sh
swift sdk list
swift sdk remove swift-6.3-DEVELOPMENT-SNAPSHOT-2026-06-07-a_android
```

### 4. `--build-system native`, for Android only

The default `swiftbuild` refuses this package outright, six times:

    error: Swift package product 'SwiftJavaJNICore-product' is linked as a
    static library by 'P12-product' and 'SwiftJava-product'. This will result
    in duplication of library code.

It is not about Android and not about the API level — a control run at API 28
produces the same six errors. It is swiftbuild rejecting a static-linkage shape
in swift-java that the native build system accepts. `compile.zsh` selects
`native` for Android through `ANDROID_BUILD_SYSTEM`.

`native` is deprecated, so this has an expiry date: when swiftbuild stops
rejecting it, or swift-java changes shape, drop the override.


### 5. The bundler inherits nothing, and rebuilds everything

`test_android.zsh` runs Swift Bundler, which runs its own `swift build`. It
inherits neither of the two prerequisites above. Measured 2026-09-02, its
invocation was

    /usr/bin/env swift build -c debug --product P12 --arch aarch64 \
      --swift-sdks-path ~/Library/Caches/dev.moreswift.swift-bundler/sdk-silos/... \
      --swift-sdk aarch64-unknown-linux-android31 ...

-- Xcode's `swift`, and the default `swiftbuild`. So it reproduced the six
SwiftJava errors from step 4 immediately after `compile.zsh` had built the same
product successfully. Both are now passed explicitly:

    --toolchain <.xctoolchain>
    --Xswiftpm --build-system --Xswiftpm native

Note `--swift-sdks-path`: the bundler builds against a *silo* -- a symlink farm
under its cache that exists to disambiguate SDKs sharing a target triple. The
silo itself is cheap. What was expensive is that the scratch path was shared
with `compile.zsh` while the SDK path was not, so each entry point invalidated
the other's tree and rebuilt everything. Ten minutes each way, on a warm tree.

**Fixed by giving the bundler its own `--scratch-path`**, which it has always
accepted. Measured after the change: first run 569 s and 3078 Swift compile
steps, second run 166 s and 4. Two trees cost disk; one tree cost ten minutes
every time anyone switched.

This did not need a fork of Swift Bundler. All three of the problems in steps
4, 5 and this one are solved with options the bundler already exposes --
`--Xswiftpm`, `--toolchain`, `--scratch-path`.

### 6. TOML keys are snake_case, not the Swift spelling

`androidContainer/Bundler.android.toml` had `minSDK`, `targetSDK` and
`compileSDK` -- the Swift field names -- and was rejected whole:

    error: Failed to deserialize configuration
    Caused by: Encountered unexpected keys 'apps.P12.android.minSDK', ...

Swift Bundler's `@Configuration` macro converts each identifier to snake_case
for TOML (`lowerCamelCaseToSnakeCase` in `ConfigurationMacro.swift`), so the
keys are `min_sdk`, `target_sdk`, `compile_sdk`.

The file had been wrong since it was written and nothing noticed, because
Android could not be built at all until 2026-09-02. Its own comment claiming
the last APK carried minSDK 28 was the evidence: 28 is swift-bundler's default,
which is what an ignored file leaves behind.

Upgrading the bundler does not help -- upstream `main` rejects the Swift
spelling too. It was never a version problem.

### 5. bundler 什麼都不繼承，而且會整個重建

`test_android.zsh` 會執行 Swift Bundler，而後者又執行它自己的 `swift build`。上述兩個前提它一個
也不繼承——2026-09-02 實測，它用的是 Xcode 的 `swift` 與預設的 `swiftbuild`（指令見上方英文段落）。
於是在 `compile.zsh` 才剛成功建出同一個 product 之後，它立刻重現了第 4 點的那六條 SwiftJava 錯誤。
現在兩者都明確傳入（參數見上方英文段落）。

請注意 `--swift-sdks-path`：bundler 會把 SDK 複製到它自己的快取 silo，並針對該路徑建置。scratch
path 雖與 `compile.zsh` 共用，SDK 路徑卻不共用，因此 SwiftPM 認定輸入不同而從頭重建。這就是「在兩個
入口之間切換時每次都要付一次完整建置」的原因，也是「我明明剛建過，為什麼還要十分鐘」的誠實答案。

### 6. TOML 的鍵是 snake_case，不是 Swift 的拼法

`androidContainer/Bundler.android.toml` 原本使用 `minSDK`、`targetSDK` 與 `compileSDK`——也就是
Swift 的欄位名稱——因而整份被拒絕（錯誤見上方英文段落）。

Swift Bundler 的 `@Configuration` macro 會把每個識別字轉換為 TOML 的 snake_case
（`ConfigurationMacro.swift` 中的 `lowerCamelCaseToSnakeCase`），因此正確的鍵是 `min_sdk`、
`target_sdk`、`compile_sdk`。

該檔自撰寫之日起就是錯的，而沒有任何東西察覺，因為在 2026-09-02 之前 Android 根本建不起來。
它自己那句「上一個 APK 帶的是 minSDK 28」的註解正是證據：28 是 swift-bundler 的預設值，也就是一個
被忽略的檔案會留下的結果。

升級 bundler 並不能解決——upstream `main` 同樣拒絕 Swift 的拼法。這從來就不是版本問題。

## Installing the SDK

```sh
swift sdk install \
  https://download.swift.org/swift-6.3.3-release/android-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_android.artifactbundle.tar.gz \
  --checksum d160cc3206dd1886dae3fef2337af5e25ec034692cd0ec225721c56cc69da7f5
```

318 MB. The checksum is swift.org's own, from
`https://www.swift.org/api/v1/install/releases.json`. Then do step 2 above.

## A full cold run

```sh
export ANDROID_NDK_HOME=/Volumes/Windows/proj_Win/.android-sdk/ndk/27.0.12077973
export SWIFT_BIN=~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift
zsh testapp/compile.zsh -android P12      # ~11 min cold, 7-10 s warm
zsh testapp/test_android.zsh P12          # its own tree, ~10 min more
```

---

# Android 建置時間，以及必須先弄對的四件事

2026-09-02 於 macOS 27.0、Apple silicon 上量測。此處每一個數字都取自實際執行時的
`date +%s`，而非估計值。

## 時間

| 項目 | 時間 | 備註 |
|---|---|---|
| clean `swift build`（僅執行檔） | **630 秒** | 對 6.3.3-RELEASE SDK |
| clean `swift build`，較早一次 | 659 秒 | 對 6.3-SNAPSHOT SDK |
| 增量，無變更 | **10 秒** | |
| 增量，動一個 app 原始檔 | **7 秒** | |
| APK 路徑 — `test_android.zsh` | 再加 **約 570 秒** | 它有自己的建置樹，見下 |

也就是說：第一次、或任何使建置樹失效的動作之後，約需**十一分鐘**；而對某支 `Pn`
的一般修改，是**七到十秒**。

存在兩棵建置樹，且彼此不共用成果：

    testapp/.compile-work-android/TestApps/.build    compile.zsh -android
    （test_android.zsh 自建一棵）                     test_android.zsh

因此在剛跑完 `compile.zsh -android` 之後再跑 `test_android.zsh`，那十一分鐘會付兩次。
冷啟動的「建出 APK 並裝上裝置」請抓二十分鐘，而非十分鐘。

建置完成的乾淨樹為 **1.8 GB**。它會隨重複使用而變大——一棵經過多次執行的樹量得 5.6 GB。
那是累積量而非單次建置的成本；在相信某個尺寸之前，值得先刪掉過期的樹。

debug 執行檔為 **173 MB**（未 strip）。

## 四個前提

沒有一個是可選的，而其中三個失敗時所給的錯誤，都指向真正原因以外的地方。

### 1. 需要與 Android SDK 相符的 toolchain——不是 Xcode 的那個

Mac 上的 `swift` 是 Xcode 的。2026-09-02 實測那是 **6.4**，而 Android SDK 是 **6.3.3**，
於是每一個 import Foundation 的 module 都以上方英文所示的錯誤失敗。

**這不是 SDK 過舊。** swift.org 的 release 清單自 6.3 起才有 `android-sdk`，且停在
**6.3.3（2026-06-29）**；不存在 6.4 的 Android SDK，因為 6.4 並非已發布的 release。
Xcode 走在那條發布列車的前面。對這項工作而言，不對的是主機編譯器。

### 2. release 版 SDK 不附帶 NDK——必須自行連結

這一個最像是下載損毀。**snapshot** bundle 內含 `android-ndk-r27d` 與已填充的
`ndk-sysroot`；**release** bundle 兩者皆無，而其 `swift-sdk.json` 仍寫著
`"sdkRootPath": "ndk-sysroot"`。於是每個 C target 都以
`fatal error: 'sys/types.h' file not found` 失敗。

請執行 bundle 為此附帶的腳本（指令見上方英文段落）。它要求 NDK **27 或更新**，
低於此版本時會明確拒絕。

### 3. 只裝一個 Android SDK，不要兩個

snapshot 與 release 同時存在時，每次建置都會印出
`warning: multiple Swift SDKs match target triple`，並替你選一個。此處它選對了，
但「替你選一個」不是一個可以拿來當基礎的性質。請移除不使用的那一個。

### 4. 僅限 Android 使用 `--build-system native`

預設的 `swiftbuild` 會直接拒絕這個 package，共六次，錯誤內容見上方英文段落。

這與 Android 無關，也與 API level 無關——在 API 28 下的對照執行會產生同樣的六條錯誤。
那是 swiftbuild 拒絕接受 swift-java 中某種靜態連結形狀，而 native 建置系統接受它。
`compile.zsh` 透過 `ANDROID_BUILD_SYSTEM` 為 Android 選用 `native`。

`native` 已標記為 deprecated，因此這有到期日：待 swiftbuild 不再拒絕它，或 swift-java
改變形狀時，即可移除此覆寫。

## 安裝 SDK

指令與 checksum 見上方英文段落。檔案 318 MB，checksum 取自 swift.org 自己的
`https://www.swift.org/api/v1/install/releases.json`。安裝後請接著執行第 2 點。
