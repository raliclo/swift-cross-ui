# Android toolchain: versions and setup

Checked 2026-10-24 against testapp/install_tools_android.zsh, compile.zsh,
test_android.zsh and testapp/androidContainer.

## What

`zsh testapp/install_tools_android.zsh` installs everything; `--check` reports
only, and `test.zsh --android` runs `--check` first so a missing piece stops the
run before a ten-minute build. That script is where every version is decided.

| Piece | Version | Where it comes from |
|---|---|---|
| Swift toolchain | 6.4.0-RELEASE | swift.org signed `.pkg`, expanded into `<repo>/../.swift-toolchains`, linked into `~/Library/Developer/Toolchains`; `swift-latest` points at it |
| Swift Android SDK | `swift-6.4.0-RELEASE_android` artifact bundle | swift.org, checksum pinned in the script |
| NDK | r30, `30.0.16248370` | Google's DMG, checked against the published SHA-1 |
| Android platform / build-tools | `android-36` / `34.0.0` | sdkmanager |
| System image | `android-36;google_apis;arm64-v8a` | sdkmanager |
| Target triple | `aarch64-unknown-linux-android31` | compile.zsh, test_android.zsh, package_android.zsh |
| SDK levels | `min_sdk 31`, `target_sdk 35`, `compile_sdk 35` | testapp/androidContainer/Bundler.android.toml |

Gradle side, testapp/androidContainer/gradleProject (gradle/libs.versions.toml
and the wrapper), against the newest stable releases on 2026-10-24:

| | In the project | Newest stable |
|---|---|---|
| Gradle | 8.13 | 9.8.2 |
| Android Gradle Plugin | 8.13.0 | 9.4.1 |
| Kotlin | 2.3.10 | 2.4.21 |
| androidx.appcompat | 1.6.1 | 1.8.0 |
| material | 1.10.0 | 1.14.0 |
| androidx.activity | 1.8.0 | 1.13.0 |
| constraintlayout | 2.1.4 | 2.2.2 |

The project versions are the ones Swift Bundler's APKBundler generated, kept
unchanged when the bundler was removed (2026-10-05) so that removal changed how
the APK is assembled, not what goes into it. No upgrade has been tried.

## Rules that are not obvious

- **The compiler must be swift.org's, at exactly the SDK's version.** Xcode's
  `swift` cannot build for the Android SDK even at the same 6.4 version; a
  cross-compilation SDK needs the open-source toolchain of its exact version
  (swift.org guide, checked 2026-10-05). A mismatch fails every module that
  imports Foundation with "module compiled with Swift X cannot be imported by
  the Swift Y compiler". The fix is a matching toolchain, never a newer SDK.
- **Exactly one Swift Android SDK installed.** With two bundles for the same
  triple SwiftPM 6.4 refuses the build ("matched multiple SDKs", 2026-10-05).
  The installer removes older SDKs, NDKs and older swift.org toolchains by
  default (`--keep-old` keeps them), and only once the new set is complete.
- **The release SDK bundle ships no NDK.** Its `swift-sdk.json` names
  `ndk-sysroot`, which is absent, so every C target fails with
  `'sys/types.h' file not found` until the bundle's setup script links the local
  NDK in. The installer does that.
- **NDK r30 comes from the DMG, not sdkmanager**: on 2026-10-05 the sdkmanager
  channel listed only `30.0.14904198 rc1`.
- **Host SDK for manifests.** Xcode 27's macOS SDK has Foundation interfaces
  with `-target-arch-variant`, which the swift.org toolchain does not know, so
  every manifest compile failed with "Invalid manifest". compile.zsh and
  test_android.zsh pick the first macOS SDK whose Foundation interface lacks
  the flag (`ANDROID_HOST_SDKROOT` overrides). It worked before 2026-10-01 only
  because a module cache still held an older Foundation.
- **`--build-system native`, Android only** (`ANDROID_BUILD_SYSTEM`). The
  default `swiftbuild` rejects swift-java's static-linkage shape with six
  "SwiftJavaJNICore-product is linked as a static library by ..." errors, at
  API 28 and 31 alike. `native` is deprecated: drop the override when
  swiftbuild accepts the package or swift-java changes shape.
- **The triple and the three SDK levels are one decision.** compile.zsh,
  test_android.zsh and Bundler.android.toml must move together; when
  test_android.zsh said 28 and the others 31, the APK under test was a second
  build of a different configuration.
- **TOML keys are snake_case** (`min_sdk`, not `minSDK`); the Swift spelling
  made the whole file be rejected or ignored.
- **sdkmanager is Homebrew's; avdmanager is the SDK root's copy.** Homebrew's
  avdmanager fails against this SDK root with "Package path is not valid"
  (2026-10-06), so `cmdline-tools;latest` is installed into the root.
- **The SDK lives on the project volume**: `<repo>/../.android-sdk`
  (`ANDROID_HOME` overrides). adb is not on PATH; the scripts resolve it.

## Stale sources

- testapp/build_time_android.md describes Swift 6.3.3, NDK 27 and Swift Bundler
  (2026-09-02). Its causes (toolchain match, no NDK in the bundle, one SDK,
  `native`) still hold; its versions and its bundler steps do not.
- The comment above `swift_toolchain` in test_android.zsh still calls
  `swift-latest` "6.3.3-dev"; the installer points it at 6.4.0.

---

# Android 工具鏈：版本與安裝

2026-10-24 對照 testapp/install_tools_android.zsh、compile.zsh、test_android.zsh 與 testapp/androidContainer 查過。

## 內容

`zsh testapp/install_tools_android.zsh` 安裝一切;`--check` 只回報。`test.zsh --android` 會先跑 `--check`,
缺東西時在十分鐘的建置之前就停下。所有版本都由這支腳本決定。

| 項目 | 版本 | 來源 |
|---|---|---|
| Swift toolchain | 6.4.0-RELEASE | swift.org 已簽章的 `.pkg`,展開到 `<repo>/../.swift-toolchains`,連結進 `~/Library/Developer/Toolchains`;`swift-latest` 指向它 |
| Swift Android SDK | `swift-6.4.0-RELEASE_android` artifact bundle | swift.org,checksum 寫死在腳本裡 |
| NDK | r30,`30.0.16248370` | Google 的 DMG,以公布的 SHA-1 檢查 |
| Android platform / build-tools | `android-36` / `34.0.0` | sdkmanager |
| 系統映像 | `android-36;google_apis;arm64-v8a` | sdkmanager |
| 目標 triple | `aarch64-unknown-linux-android31` | compile.zsh、test_android.zsh、package_android.zsh |
| SDK level | `min_sdk 31`、`target_sdk 35`、`compile_sdk 35` | testapp/androidContainer/Bundler.android.toml |

Gradle 這一側(testapp/androidContainer/gradleProject 的 gradle/libs.versions.toml 與 wrapper),對照 2026-10-24 的最新穩定版:

| | 專案中 | 最新穩定版 |
|---|---|---|
| Gradle | 8.13 | 9.8.2 |
| Android Gradle Plugin | 8.13.0 | 9.4.1 |
| Kotlin | 2.3.10 | 2.4.21 |
| androidx.appcompat | 1.6.1 | 1.8.0 |
| material | 1.10.0 | 1.14.0 |
| androidx.activity | 1.8.0 | 1.13.0 |
| constraintlayout | 2.1.4 | 2.2.2 |

專案中的版本是 Swift Bundler 的 APKBundler 產生的版本，拿掉 bundler(2026-10-05)時原樣保留，讓那次改動只改變 APK
的組裝方式，不改變內容。尚未嘗試升級。

## 不明顯的規則

- **編譯器必須是 swift.org 的，且與 SDK 版本完全相同。** 即使同為 6.4,Xcode 的 `swift` 也不能用來建置 Android SDK;
  交叉編譯 SDK 需要版本完全相同的開源 toolchain(swift.org 指南,2026-10-05 查過)。不相符時，每個 import Foundation
  的 module 都以「module compiled with Swift X cannot be imported by the Swift Y compiler」失敗。解法是相符的 toolchain,
  絕不是更新的 SDK。
- **只能裝一個 Swift Android SDK。** 同一 triple 有兩個 bundle 時，SwiftPM 6.4 拒絕建置(「matched multiple SDKs」,
  2026-10-05)。安裝腳本預設會移除舊的 SDK、NDK 與較舊的 swift.org toolchain(`--keep-old` 保留),而且只在新的一組
  完整到位後才移除。
- **release 版 SDK bundle 不附 NDK。** 它的 `swift-sdk.json` 指向不存在的 `ndk-sysroot`,在 bundle 附的設定腳本把本機 NDK
  連進去之前，每個 C target 都以 `'sys/types.h' file not found` 失敗。安裝腳本會做這一步。
- **NDK r30 取自 DMG,不是 sdkmanager**:2026-10-05 時 sdkmanager 的頻道只列出 `30.0.14904198 rc1`。
- **manifest 用的主機 SDK。** Xcode 27 的 macOS SDK 裡 Foundation 介面帶有 `-target-arch-variant`,swift.org 的 toolchain
  不認得，於是每次編譯 manifest 都以「Invalid manifest」失敗。compile.zsh 與 test_android.zsh 會挑第一個 Foundation 介面
  不含該旗標的 macOS SDK(可用 `ANDROID_HOST_SDKROOT` 覆寫)。2026-10-01 之前能成功，只是因為 module cache 還留著舊的 Foundation。
- **`--build-system native`,僅限 Android**(`ANDROID_BUILD_SYSTEM`)。預設的 `swiftbuild` 以六條「SwiftJavaJNICore-product
  is linked as a static library by ...」拒絕 swift-java 的靜態連結形狀,API 28 與 31 都一樣。`native` 已 deprecated:等 swiftbuild
  接受這個 package 或 swift-java 改變形狀時，拿掉這個覆寫。
- **triple 與三個 SDK level 是同一個決定。** compile.zsh、test_android.zsh 與 Bundler.android.toml 必須一起改；先前
  test_android.zsh 寫 28、其他兩處寫 31 時，受測的 APK 是另一種設定的第二次建置。
- **TOML 的鍵是 snake_case**(`min_sdk`,不是 `minSDK`);Swift 的拼法會讓整份檔案被拒絕或忽略。
- **sdkmanager 用 Homebrew 的;avdmanager 用 SDK 根目錄裡那一份。** Homebrew 的 avdmanager 對這個 SDK 根目錄會以
  「Package path is not valid」失敗(2026-10-06),所以 `cmdline-tools;latest` 裝在根目錄裡。
- **SDK 放在專案磁碟區**:`<repo>/../.android-sdk`(可用 `ANDROID_HOME` 覆寫)。adb 不在 PATH 上，由腳本解析。

## 過期的來源

- testapp/build_time_android.md 描述的是 Swift 6.3.3、NDK 27 與 Swift Bundler(2026-09-02)。其中的成因(toolchain 相符、
  bundle 不附 NDK、只裝一個 SDK、`native`)仍然成立；版本與 bundler 步驟已不適用。
- test_android.zsh 裡 `swift_toolchain` 上方的註解仍稱 `swift-latest` 為「6.3.3-dev」;安裝腳本已讓它指向 6.4.0。
