# Android build settings: debug, release, R8 and compressed native libraries

Measured 2026-10-24 on the api36b emulator with P96 (33 curve tiles). The
Swift side was identical in both builds.

## The switch

`zsh testapp/test.zsh Pn --android` builds the release variant by default
(since 2026-10-27); `SCUI_ANDROID_RELEASE=0` builds debug. The release pieces:

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

Release is the default since 2026-10-27; `SCUI_ANDROID_RELEASE=0` builds debug
(debuggable, for `run-as` or a Java debugger). The evidence for the change is
under "Action-file replay" below.

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

## Action-file replay, debug against release (2026-10-27)

Before the default changed, ten apps were replayed on api36b with the same
action file and the same Swift build, once as debug and once as release, and
the app's `[Pn]` log lines (logcat) and final captures (pixel by pixel below
the status bar, tolerance 8) were compared:

| App | Action file | `replayed` in both | App log | Final capture |
|---|---|---|---|---|
| P12 | increment-the-counter | yes (3 actions) | same | same |
| P23 | column-sorting | yes (5) | same (6 lines) | same |
| P41 | turn-the-month-wheel | yes (3) | same | same |
| P74 | choose-in-every-style | yes (9) | same (6 lines) | same |
| P96 | timing-curves | yes (1, sleep only) | curve error 0.000 pt in both; DRIVEN distinct counts vary with timing | dot positions differ (animation phase) |
| P11 | drag-the-first-slider | yes (6) | same | only the clock in the time picker (8:00 vs 8:01 PM) |
| P65 | pinch-and-rotate | yes (7) | same (98 lines) | same |
| P72 | scroll-and-keys | yes (14) | SCROLL, KEY and MODIFIERS lines same; `tick` lines vary with timing | the rotating mesh differs |
| P88 | hover-cmd-drag | yes (23) | same | same |
| P94 | undo | yes (49) | the eight editor lines same, changes 8 | only Gboard's second suggestion |

None of the twenty logcats has `FATAL EXCEPTION`, `ClassNotFound`,
`NoSuchMethod` or `NoSuchField`. P113's Back check
(test_support/p113_back_android.zsh) passes 7/7 on release. A `test.zsh` run
(30 s showtime included) took 73-81 s for debug and 84-97 s for release (R8).

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

- Settled 2026-10-27: release is the default; see "Action-file replay" above.
- `lib_FoundationICU.so` (38 MB) and the unused AndroidKit bindings (about
  23 MB of libPn.so) are the remaining size; see apk-size.md.

---

# Android 建置設定:debug、release、R8 與原生函式庫壓縮

2026-10-24 在 api36b 模擬器上以 P96(33 張曲線圖)量測。兩種建置的 Swift 端完全相同。

## 開關

`zsh testapp/test.zsh Pn --android` 預設建置 release 版(2026-10-27 起);`SCUI_ANDROID_RELEASE=0` 改建 debug。release 的組成：

- `testapp/package_android.zsh` 改跑 `assembleRelease`(而非 `assembleDebug`),並傳入 `-PscuiCompressNativeLibs=true`。
- `testapp/androidContainer/gradleProject/build.gradle.kts`:
  - release 建置類型開啟 `isMinifyEnabled = true`(R8)與 `isShrinkResources = true`,並以 debug 金鑰簽章，才裝得上模擬器；
  - `packaging.jniLibs.useLegacyPackaging` 依該屬性決定。
- 同目錄的 `proguard-rules.pro` 保留 Swift 透過 JNI 以名稱取用的部分：
  - 所有非 AndroidX、非 Material、非 Kotlin 的類別，包括 `dev.swiftcrossui.**` 與 swift-java 的 Java 端；
  - AndroidBackend 的 Swift 直接指名的 AndroidX 與 Material 類別:`Chip`、`MaterialButtonToggleGroup`、`Variant`、`ListAdapter`、`FragmentActivity`。

  其餘的 AndroidX 與 Material 經由 Kotlin 輔助類別取用,R8 讀得到。

自 2026-10-27 起預設是 release;`SCUI_ANDROID_RELEASE=0` 改建 debug(可除錯，供 `run-as` 或 Java 除錯器)。改預設的依據見下方「動作檔重播」。

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

## 動作檔重播:debug 對 release(2026-10-27)

改預設之前，在 api36b 上對十支 app 各以同一個動作檔、同一份 Swift 建置跑 debug 與 release,比較 app 的 `[Pn]` log
(logcat)與最終擷圖(狀態列以下逐像素比較，容差 8):

| App | 動作檔 | 兩邊都 `replayed` | app log | 最終擷圖 |
|---|---|---|---|---|
| P12 | increment-the-counter | 是(3 個動作) | 相同 | 相同 |
| P23 | column-sorting | 是(5) | 相同(6 行) | 相同 |
| P41 | turn-the-month-wheel | 是(3) | 相同 | 相同 |
| P74 | choose-in-every-style | 是(9) | 相同(6 行) | 相同 |
| P96 | timing-curves | 是(1,僅 sleep) | 曲線誤差兩邊都是 0.000 pt;DRIVEN 的 distinct 數依時序而不同 | 點的位置不同(動畫相位) |
| P11 | drag-the-first-slider | 是(6) | 相同 | 只差時間選擇器顯示的時鐘(8:00 對 8:01 PM) |
| P65 | pinch-and-rotate | 是(7) | 相同(98 行) | 相同 |
| P72 | scroll-and-keys | 是(14) | SCROLL、KEY、MODIFIERS 各行相同;`tick` 行依時序不同 | 旋轉中的 mesh 不同 |
| P88 | hover-cmd-drag | 是(23) | 相同 | 相同 |
| P94 | undo | 是(49) | 八行 editor 相同,changes 8 | 只差 Gboard 的第二個建議字 |

二十份 logcat 都沒有 `FATAL EXCEPTION`、`ClassNotFound`、`NoSuchMethod` 或 `NoSuchField`。P113 的返回檢查
(test_support/p113_back_android.zsh)在 release 上 7/7 通過。每次 `test.zsh` 執行(含 30 秒展示時間):debug 73–81 秒，
release 84–97 秒(R8)。

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

- 已解決(2026-10-27):release 成為預設，見上方「動作檔重播」。
- 剩下的大小來自 `lib_FoundationICU.so`(38 MB)與用不到的 AndroidKit 綁定(libPn.so 中約 23 MB);見 apk-size.md。
