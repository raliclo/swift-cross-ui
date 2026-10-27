# Building and packaging an Android test app

Since b8314441 (2026-10-05) the APK is packaged without Swift Bundler.
Checked against the scripts on 2026-10-24.

## The pipeline

`zsh testapp/test.zsh Pn --android` runs testapp/test_android.zsh, which:

1. runs `install_tools_android.zsh --check`;
2. takes the Android lock (test_support/platform_lock.zsh): the emulator,
   `.compile-work-android` and the one Gradle project are shared, so a second
   Android run waits; iOS and macOS runs do not;
3. runs `compile.zsh -android Pn`: `SCUI_ANDROID=1 swift build --build-system
   native --swift-sdk aarch64-unknown-linux-android31`, release by default
   (`--debug-build` for debug), into `testapp/.compile-work-android/TestApps/.build`;
4. runs `package_android.zsh Pn`, which writes `testapp/.androidApk/Pn.apk`;
5. installs, launches, replays and captures (see harness-run.md).

`--no-build` reuses `testapp/.androidApk/Pn.apk`.

## What package_android.zsh does

The steps and their order are Swift Bundler's APKBundler's:

1. Relinks the executable as `libPn.so` with an soname, using SwiftPM's own
   link command from `.build/<config>.yaml`. Without the soname the shim
   records the host path and the device loader cannot find the library. The
   plan is 111 MB; it is scanned for the one command rather than YAML-loaded
   (17.5 s per app with `yaml.safe_load`, 0.04 s scanning, 2026-10-05).
2. Copies `libPn.so` into jniLibs with `.swift_ast` removed
   (`SCUI_KEEP_SWIFT_AST=1` keeps it for a debugger). jniLibs is emptied first
   so the previous app's library does not ride along.
3. Copies every shared library it needs, found breadth-first with
   `llvm-readelf`, except those the device ships.
4. Builds `libshim.so` from `gradleProject/shim/shim.c`:
   `MainActivity.setup()` calls `AndroidBackend_entrypoint`.
5. Mirrors `Sources/AndroidBackend/Kotlin/*.kt` into `src/main/kotlin`
   (rsync `--delete`).
6. Writes AndroidManifest.xml from Bundler.android.toml (permissions, URL
   schemes, `configChanges`, `singleTop`, ScuiWindowActivity, OverlayService),
   only when its text changes, so Gradle sees an unchanged input across apps.
7. Runs `./gradlew assembleDebug` with stdin closed (with stdin open gradlew can
   hang after the build ends), passing `scuiApplicationId`, `scuiAppName`,
   `scuiVersionCode` and the SDK levels as `-P` properties.

The template testapp/androidContainer/gradleProject is copied over
`.compile-work-android/gradleProject`, keeping its `build/` and `.gradle/`, so
the Kotlin compiles once and the next app reuses it. The namespace is fixed:
`MainActivity` and the shim's JNI symbol are the same for every app; only the
application id differs.

`SCUI_ANDROID_RELEASE=1` builds the R8-shrunk, non-debuggable release variant with
compressed native libraries instead; size, speed and build time are in android-setting.md.

## Rules

- **Application id**: `dev.swiftcrossui.testapp.` plus the app name lowercased
  with hyphens dropped (`p17doe`). `am start` against another spelling finds no
  package while the install reported success; force-stop of a missing package
  says nothing, which once left P15-DARK and P17-DOE running across a sweep.
- **versionCode** is the commit count, as the bundler used, so an install over
  an older APK is not a downgrade.
- **`compile.zsh -android` alone packages nothing.** The previous APK stays,
  installs with "Success" and runs. On 2026-09-15 an hour went into a
  conformance "invisible at runtime" that the device had never been given.
  compile.zsh now says so on every Android run; check the APK's timestamp.
- **Exported symbols**: testapp/android-exports.map keeps `AndroidBackend_entrypoint`,
  `Java_*`, `JNI_OnLoad` and `main` global and everything else local. P44's
  library exported 151,047 symbols and needed 31; the names cost 15.81 MB
  (2026-09-05). Do not list `JNI_OnUnload`: Swift's runtime does not define it,
  and lld fails on a literal name that is missing.
- **Core code must compile for Bionic.** `sin(Float)` is a Darwin overload;
  Bionic has `sin(double)` and `sinf(float)`. One such line in Sources/SwiftCrossUI
  kept AndroidBackend from building at all until 2026-09-21 while three
  platforms were green. Compute in `Double`. `Scripts/check_android_build.zsh`
  (run by `Scripts/test.sh`) compiles for Android when the diff against
  origin/develop touches Package.swift or a Sources directory that is not
  another platform's backend: 0.25 s when skipped, 73 s when it runs; without
  an SDK it skips loudly and exits 0.

## Limits and stale numbers

- Build times in testapp/build_time_android.md (clean ~630 s, incremental
  7-10 s, 2026-09-02) predate Swift 6.4.0 and package_android.zsh; not
  re-measured since.
- testapp/README.md "Android build size, and the disk it takes" (126 MB APK,
  `.build-bundler`, 106 GB of per-app Gradle projects) describes the bundler era.
  Swift Bundler's 24 GB `.build-bundler` tree and per-app projects are gone.

---

# 建置與打包 Android 測試 app

自 b8314441(2026-10-05)起，APK 的打包不經 Swift Bundler。2026-10-24 對照腳本查過。

## 流程

`zsh testapp/test.zsh Pn --android` 執行 testapp/test_android.zsh,它會:

1. 執行 `install_tools_android.zsh --check`;
2. 取得 Android 鎖(test_support/platform_lock.zsh):模擬器、`.compile-work-android` 與唯一的 Gradle 專案是共用的，
   所以第二個 Android 執行會等待;iOS 與 macOS 的執行不必等;
3. 執行 `compile.zsh -android Pn`:`SCUI_ANDROID=1 swift build --build-system native --swift-sdk
   aarch64-unknown-linux-android31`,預設 release(debug 用 `--debug-build`),產物在
   `testapp/.compile-work-android/TestApps/.build`;
4. 執行 `package_android.zsh Pn`,寫出 `testapp/.androidApk/Pn.apk`;
5. 安裝、啟動、重播並擷圖(見 harness-run.md)。

`--no-build` 重用 `testapp/.androidApk/Pn.apk`。

## package_android.zsh 做什麼

步驟與順序都與 Swift Bundler 的 APKBundler 相同:

1. 以 SwiftPM 自己在 `.build/<config>.yaml` 裡的連結指令，把執行檔重新連結成帶 soname 的 `libPn.so`。少了 soname,
   shim 會記下主機上的路徑，裝置的載入器就找不到函式庫。plan 有 111 MB;以掃描找出那一條指令，而不是載入 YAML
   (`yaml.safe_load` 每支 app 17.5 秒，掃描 0.04 秒,2026-10-05)。
2. 把去掉 `.swift_ast` 的 `libPn.so` 放進 jniLibs(`SCUI_KEEP_SWIFT_AST=1` 保留，供除錯器使用)。jniLibs 先清空，
   上一支 app 的函式庫才不會跟著打包。
3. 以 `llvm-readelf` 逐層找出所需的共享函式庫並複製，裝置自帶的除外。
4. 由 `gradleProject/shim/shim.c` 建出 `libshim.so`:`MainActivity.setup()` 呼叫 `AndroidBackend_entrypoint`。
5. 把 `Sources/AndroidBackend/Kotlin/*.kt` 鏡像到 `src/main/kotlin`(rsync `--delete`)。
6. 依 Bundler.android.toml 寫出 AndroidManifest.xml(權限、URL scheme、`configChanges`、`singleTop`、ScuiWindowActivity、
   OverlayService),只在內容改變時才寫，換 app 時 Gradle 看到的輸入不變。
7. 關閉 stdin 執行 `./gradlew assembleDebug`(stdin 開著時 gradlew 可能在建置結束後掛住),以 `-P` 屬性傳入
   `scuiApplicationId`、`scuiAppName`、`scuiVersionCode` 與 SDK level。

範本 testapp/androidContainer/gradleProject 會覆蓋到 `.compile-work-android/gradleProject` 上，保留其 `build/` 與 `.gradle/`,
因此 Kotlin 只編一次，下一支 app 直接重用。namespace 固定:`MainActivity` 與 shim 的 JNI 符號對每支 app 都相同，只有
application id 不同。

`SCUI_ANDROID_RELEASE=1` 改建經 R8 縮減、不可除錯、原生函式庫壓縮的 release 版本；大小、速度與建置時間見 android-setting.md。

## 規則

- **application id**:`dev.swiftcrossui.testapp.` 加上轉小寫、去掉連字號的 app 名稱(`p17doe`)。用其他拼法 `am start`
  會找不到套件，而安裝明明回報成功;force-stop 不存在的套件什麼都不說，曾讓 P15-DARK 與 P17-DOE 在整次掃描中一直執行。
- **versionCode** 是 commit 數，與 bundler 相同，因此覆蓋安裝較舊的 APK 不算降版。
- **單跑 `compile.zsh -android` 不會打包任何東西。** 舊的 APK 還在，安裝回報「Success」也能執行。2026-09-15 曾花一小時
  追查一個「執行期看不到」的 conformance,而裝置根本沒拿到新程式。compile.zsh 現在每次 Android 執行都會明說；請查看 APK
  的時間戳。
- **匯出符號**:testapp/android-exports.map 讓 `AndroidBackend_entrypoint`、`Java_*`、`JNI_OnLoad` 與 `main` 保持 global,
  其餘全部 local。P44 的函式庫匯出 151,047 個符號，只需要 31 個；那些名字佔 15.81 MB(2026-09-05)。不要列
  `JNI_OnUnload`:Swift runtime 沒有定義它，而 lld 遇到不存在的字面名稱會失敗。
- **核心程式碼必須能在 Bionic 上編譯。** `sin(Float)` 是 Darwin 的多載;Bionic 只有 `sin(double)` 與 `sinf(float)`。
  Sources/SwiftCrossUI 裡一行這樣的程式碼，讓 AndroidBackend 直到 2026-09-21 都完全建不起來，而另外三個平台都是綠的。
  請以 `Double` 計算。`Scripts/check_android_build.zsh`(由 `Scripts/test.sh` 執行)在與 origin/develop 的差異觸及
  Package.swift 或任何非其他平台 backend 的 Sources 目錄時，為 Android 編譯一次：略過時 0.25 秒，執行時 73 秒；沒有 SDK
  時大聲略過並以 0 結束。

## 限制與過期的數字

- testapp/build_time_android.md 的建置時間(clean 約 630 秒、增量 7–10 秒,2026-09-02)早於 Swift 6.4.0 與
  package_android.zsh;之後沒有重量。
- testapp/README.md 的「Android build size, and the disk it takes」(126 MB APK、`.build-bundler`、106 GB 的各 app
  Gradle 專案)描述的是 bundler 時期。Swift Bundler 那棵 24 GB 的 `.build-bundler` 與各 app 的專案都已不存在。
