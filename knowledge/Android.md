# Android

AndroidBackend, the Android emulator, Gradle packaging and action-file replay.
Index as of 2026-10-24; each line links one topic.

## Toolchain and build

- [Toolchain setup](Android/toolchain-setup.md) -- Swift 6.4.0 from swift.org, one Android SDK, NDK r30, `--build-system native`, Gradle 8.13 / AGP 8.13.0 against newest stable.
- [Building and packaging](Android/build-and-packaging.md) -- compile.zsh, then package_android.zsh into one shared Gradle project; no Swift Bundler; exports map; the stale-APK trap.
- [APK size](Android/apk-size.md) -- P96's 113 MB debug APK: ICU 38.2 MB, libP96 33.1 MB (23 MB AndroidKit), what came off, what is left.
- [Debug and release builds](Android/android-setting.md) -- release is the harness default (SCUI_ANDROID_RELEASE=0 for debug): R8, not debuggable, compressed libs; APK 113 -> 37 MB, launch 2.5x faster; replays match debug; toolchain versions.
- [swift-java from the raliclo fork](Android/swift-java-fork.md) -- AndroidKit and its bindings, raliclo/swift-java on develop, the identity warning.

## Emulator and harness

- [Emulator and AVDs](Android/emulator-avds.md) -- api36b (phone) and tablet36, storage on the project volume, boot flags, host-GPU check, emulator quirks.
- [Running an app](Android/harness-run.md) -- test_android.zsh: arguments through `scui_args`, captures, crash check, sweep and verify scripts.
- [Profiling](Android/profiling.md) -- adb, logcat, simpleperf with `cpu-clock`, symbolizing stripped Swift libraries.

## Action-file replay

- [Replay](Android/action-file-replay.md) -- in-process synthesiser, origin and root-scroll displacement, long press and scroll semantics, front windows.
- [Keys and menu shortcuts](Android/keys-and-shortcuts.md) -- the focus chain, ShortcutHostLayout, Control-shortcut offer, INJECT_EVENTS refused.
- [Re-aiming action files](Android/reaim-action-files.md) -- reaim_android.zsh moves points to their recorded widgets; what makes a file clean.

## Backend behaviour

- [Android lines up with iOS](Android/ui-alignment-with-ios.md) -- the alignment rule and every decision already made.
- [Windows and presentations](Android/windows-and-presentations.md) -- one activity per window, sheets, covers, popovers, floating windows.
- [Documents and URLs](Android/documents-and-urls.md) -- `content://` staging, synchronous write-back, incoming URLs.
- [The Kotlin half](Android/kotlin-helpers.md) -- what lives in Kotlin, how it reaches the APK, ktfmt and Chinese comments.
- [Arcs continue the path](Android/path-arcs.md) -- `Path.addArc` starts a contour; `arcTo` fixed Capsule (c7961de5).

## Performance

- [Where the time goes](Android/performance-jni.md) -- JNI lookups, text-measure cache, LastSet, button actions, parity with iOS.
- [Density cache](Android/density-cache.md) -- the display density read once per configuration (e6023a81).

## Known limits and open items

- [92.5% brightness](Android/display-brightness.md) -- kept as designed (2026-10-23); later reads disagree, unsettled.
- Open: equal-length saves within one millisecond (documents-and-urls.md, 2026-10-22); swift-java method-ID caching not landed (performance-jni.md, 2026-10-24); ImageFormats linked into every app (apk-size.md, 2026-10-24).

---

# Android

AndroidBackend、Android 模擬器、Gradle 打包與動作檔重播。2026-10-24 的索引；每行連到一個主題。

## 工具鏈與建置

- [工具鏈安裝](Android/toolchain-setup.md)——swift.org 的 Swift 6.4.0、只裝一個 Android SDK、NDK r30、`--build-system native`、Gradle 8.13 / AGP 8.13.0 與最新穩定版對照。
- [建置與打包](Android/build-and-packaging.md)——先 compile.zsh,再由 package_android.zsh 打包進一個共用的 Gradle 專案；不用 Swift Bundler;匯出符號表；舊 APK 的陷阱。
- [APK 大小](Android/apk-size.md)——P96 的 113 MB debug APK:ICU 38.2 MB、libP96 33.1 MB(其中 AndroidKit 23 MB),已拿掉什麼、還剩什麼。
- [Debug 與 release 建置](Android/android-setting.md)——release 是 harness 預設(SCUI_ANDROID_RELEASE=0 改用 debug):R8、不可除錯、原生函式庫壓縮；APK 113 → 37 MB,啟動快約 2.5 倍；重播結果與 debug 一致；工具鏈版本。
- [swift-java 改用 fork](Android/swift-java-fork.md)——AndroidKit 與其綁定、develop 分支的 raliclo/swift-java、識別衝突警告。

## 模擬器與 harness

- [模擬器與 AVD](Android/emulator-avds.md)——api36b(手機)與 tablet36、資料放在專案磁碟區、開機旗標、主機 GPU 檢查、模擬器怪癖。
- [執行 app](Android/harness-run.md)——test_android.zsh:以 `scui_args` 傳參數、擷圖、當機檢查、掃描與驗證腳本。
- [效能分析](Android/profiling.md)——adb、logcat、用 `cpu-clock` 的 simpleperf、解析已去符號的 Swift 函式庫。

## 動作檔重播

- [重播](Android/action-file-replay.md)——程序內的 synthesiser、原點與根捲動位移、長按與捲動的語意、前景視窗。
- [按鍵與選單快捷鍵](Android/keys-and-shortcuts.md)——焦點鏈、ShortcutHostLayout、補送 Control 快捷鍵、INJECT_EVENTS 被拒。
- [重新瞄準動作檔](Android/reaim-action-files.md)——reaim_android.zsh 把點移回記錄時的 widget;怎樣的檔案才算乾淨。

## Backend 行為

- [Android 對齊 iOS](Android/ui-alignment-with-ios.md)——對齊原則與已做的每一項決定。
- [視窗與呈現](Android/windows-and-presentations.md)——每個視窗一個 activity、sheet、cover、popover、浮動視窗。
- [文件與 URL](Android/documents-and-urls.md)——`content://` 代用檔、同步寫回、傳入的 URL。
- [Kotlin 那一半](Android/kotlin-helpers.md)——哪些東西在 Kotlin、如何進入 APK、ktfmt 與中文註解。
- [圓弧接續路徑](Android/path-arcs.md)——`Path.addArc` 會另起輪廓;`arcTo` 修好了 Capsule(c7961de5)。

## 效能

- [時間花在哪裡](Android/performance-jni.md)——JNI 查找、文字量測快取、LastSet、按鈕 action、與 iOS 相當。
- [密度快取](Android/density-cache.md)——顯示密度每次設定只讀一次(e6023a81)。

## 已知限制與未解項目

- [92.5% 亮度](Android/display-brightness.md)——維持為預期設計(2026-10-23);之後的讀值不一致，尚未定案。
- 未解：同一毫秒內兩次長度相同的存檔(documents-and-urls.md,2026-10-22);swift-java 方法 ID 快取尚未落地(performance-jni.md,2026-10-24);ImageFormats 被連進每支 app(apk-size.md,2026-10-24)。
