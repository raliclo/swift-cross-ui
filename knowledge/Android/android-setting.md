# Android build settings: debug, release, R8 and compressed native libraries

Measured 2026-10-24 on the api36b emulator with P96 (33 curve tiles). The
Swift side was identical in both builds.

## The switch

`SCUI_ANDROID_RELEASE=1 zsh testapp/test.zsh Pn --android` builds the release
variant. The pieces:

- `testapp/package_android.zsh` runs `assembleRelease` instead of
  `assembleDebug`, and passes `-PscuiCompressNativeLibs=true`.
- In `testapp/androidContainer/gradleProject/build.gradle.kts`:
  - the release build type sets `isMinifyEnabled = true` (R8) and
    `isShrinkResources = true`, and is signed with the debug key so it
    installs on an emulator;
  - `packaging.jniLibs.useLegacyPackaging` follows the property.
- `proguard-rules.pro` (next to it) keeps what Swift reaches through JNI by
  name:
  - all non-AndroidX, non-Material, non-Kotlin classes, which includes
    `dev.swiftcrossui.**` and swift-java's Java side;
  - the AndroidX and Material classes AndroidBackend's Swift names directly:
    `Chip`, `MaterialButtonToggleGroup`, `Variant`, `ListAdapter` and
    `FragmentActivity`.

  The rest of AndroidX and Material is reached through the Kotlin helpers,
  which R8 reads.

Debug stays the default.

## Results (P96)

| | debug | release |
|---|---|---|
| APK file | 113 MB | 37 MB |
| installed (`du` of the app dir) | 113 MB | 138 MB+ (`oat/` unreadable) |
| debuggable | yes | no |
| cold launch, `am start -W` TotalTime | 614-642 ms | 236-299 ms |
| main-thread CPU, 5 s from launch | 1.62 s | 0.59 s |
| libart share of main thread | 33.7% | 11.1% |
| CheckJNI / interpreter on main thread | 13.6% / most Java calls | gone |
| `back.out` distinct values (frames in the first tween) | 38-40 | 40-47 |
| Gradle, first build after switching | 8 s | 38 s (R8) |
| Gradle, nothing changed | 1 s | 1 s |
| whole `test.zsh` run (Swift dominates) | 83.9 s / 56.1 s | 79.6 s / 59.4 s |

R8 and non-debuggable are the speed win. ART on a debuggable APK runs
CheckJNI on every JNI call and interprets Java, and both disappear in
release. Compressing the native libraries trades on-device size for APK
size: the libraries are extracted at install, so the installed app is larger
than the uncompressed debug one. For a Play upload, an AAB without legacy
packaging is compressed for download anyway.

Release was checked on P96, P74 (segmented control = MaterialButtonToggleGroup,
radio group), P41 (date pickers), P23 (table) and P12 (toggles): no crash and
no `ClassNotFound` / `NoSuchMethod` in logcat. Each lays out the same as the
debug build of the same code.

## A trap found on the way

The template's `res/mipmap/icon.png` was WebP data with a .png name. Debug
never crunches PNGs, so it built. Release failed in `mergeReleaseResources`
with "AAPT: error: file failed to compile". It is `icon.webp` now (Android
accepts WebP launcher icons; `@mipmap/icon` is unchanged). The template sync
in package_android.zsh now uses `rsync --delete`, so a renamed template file
does not leave its old name behind as a duplicate resource.

## Toolchain versions (2026-10-24)

| | in the template | newest stable |
|---|---|---|
| Gradle | 8.13 | 9.8.2 |
| Android Gradle Plugin | 8.13.0 | 9.4.1 |
| Kotlin | 2.3.10 | 2.4.21 |
| appcompat | 1.6.1 | 1.8.0 |
| material | 1.10.0 | 1.14.0 |
| activity | 1.8.0 | 1.13.0 |
| constraintlayout | 2.1.4 | 2.2.2 |

AGP 9 is a major release (Kotlin support built in, a new DSL), so upgrading
is its own change, measured on its own.

## Open

- Whether to make release the harness default. Nothing in the harness needs a
  debuggable APK (no `run-as`), but the action-file replay was not run on a
  release build.
- `lib_FoundationICU.so` (38 MB) and the unused AndroidKit bindings (about
  23 MB of libPn.so) are the remaining size; see apk-size.md.

---

# Android 建置設定:debug、release、R8 與原生函式庫壓縮

2026-10-24 在 api36b 模擬器上以 P96(33 張曲線圖)量測。兩種建置的 Swift 端完全相同。

## 開關

`SCUI_ANDROID_RELEASE=1 zsh testapp/test.zsh Pn --android` 會建置 release 版：

- `testapp/package_android.zsh` 改跑 `assembleRelease`(而非 `assembleDebug`),並傳入 `-PscuiCompressNativeLibs=true`。
- `testapp/androidContainer/gradleProject/build.gradle.kts`:
  - release 建置類型開啟 `isMinifyEnabled = true`(R8)與 `isShrinkResources = true`,並以 debug 金鑰簽章，才裝得上模擬器；
  - `packaging.jniLibs.useLegacyPackaging` 依該屬性決定。
- 同目錄的 `proguard-rules.pro` 保留 Swift 透過 JNI 以名稱取用的部分：
  - 所有非 AndroidX、非 Material、非 Kotlin 的類別，包括 `dev.swiftcrossui.**` 與 swift-java 的 Java 端；
  - AndroidBackend 的 Swift 直接指名的 AndroidX 與 Material 類別:`Chip`、`MaterialButtonToggleGroup`、`Variant`、`ListAdapter`、`FragmentActivity`。

  其餘的 AndroidX 與 Material 經由 Kotlin 輔助類別取用,R8 讀得到。

預設仍是 debug。

## 結果(P96)

| | debug | release |
|---|---|---|
| APK 檔案 | 113 MB | 37 MB |
| 安裝後(app 目錄的 `du`) | 113 MB | 138 MB 以上(`oat/` 無法讀取) |
| 可除錯 | 是 | 否 |
| 冷啟動,`am start -W` 的 TotalTime | 614–642 ms | 236–299 ms |
| 啟動後 5 秒的主執行緒 CPU | 1.62 秒 | 0.59 秒 |
| 主執行緒中 libart 的比例 | 33.7% | 11.1% |
| 主執行緒中的 CheckJNI／直譯器 | 13.6%／大部分 Java 呼叫 | 消失 |
| `back.out` 相異值(第一個補間收到的幀數) | 38–40 | 40–47 |
| Gradle,切換後第一次建置 | 8 秒 | 38 秒(R8) |
| Gradle,沒有改動時 | 1 秒 | 1 秒 |
| 整個 `test.zsh`(Swift 編譯佔大部分) | 83.9／56.1 秒 | 79.6／59.4 秒 |

速度的提升來自 R8 與不可除錯：可除錯 APK 上的 ART 會對每個 JNI 呼叫跑 CheckJNI,並以直譯方式執行 Java,
release 版兩者都沒有。原生函式庫壓縮則是以裝置上的空間換 APK 大小：函式庫在安裝時解開，所以安裝後比不壓縮的
debug 版還大。若要上傳 Play,不使用 legacy packaging 的 AAB 下載時本來就會壓縮。

release 版已在 P96、P74(分段控制,即 MaterialButtonToggleGroup,以及單選群組)、P41(日期選擇器)、
P23(表格)、P12(切換開關)上檢查：沒有當機,logcat 沒有 `ClassNotFound`／`NoSuchMethod`,版面都與同一份程式碼的
debug 版相同。

## 途中發現的陷阱

樣板中的 `res/mipmap/icon.png` 其實是 WebP 資料、副檔名卻是 .png。debug 從不處理 PNG,所以建置得起來；release
在 `mergeReleaseResources` 失敗,訊息是「AAPT: error: file failed to compile」。現在改名為 `icon.webp`(Android 接受
WebP 啟動圖示,`@mipmap/icon` 不變)。package_android.zsh 的樣板同步改用 `rsync --delete`,避免樣板中改名的檔案
留下舊名，變成重複的資源。

## 工具鏈版本(2026-10-24)

| | 樣板中 | 最新穩定版 |
|---|---|---|
| Gradle | 8.13 | 9.8.2 |
| Android Gradle Plugin | 8.13.0 | 9.4.1 |
| Kotlin | 2.3.10 | 2.4.21 |
| appcompat | 1.6.1 | 1.8.0 |
| material | 1.10.0 | 1.14.0 |
| activity | 1.8.0 | 1.13.0 |
| constraintlayout | 2.1.4 | 2.2.2 |

AGP 9 是主版本更新(內建 Kotlin 支援、新的 DSL),所以升級是另一項改動，另外量測。

## 未決

- 要不要讓測試工具預設改用 release。測試工具沒有任何地方需要可除錯的 APK(沒有 `run-as`),但動作檔重播還沒在
  release 版上跑過。
- 剩下的大小來自 `lib_FoundationICU.so`(38 MB)與用不到的 AndroidKit 綁定(libPn.so 中約 23 MB);見 apk-size.md。
