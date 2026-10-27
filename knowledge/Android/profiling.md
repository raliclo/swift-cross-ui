# Profiling an Android test app

What worked on the api36b emulator, 2026-10-24.

## Tools and where they are

- adb: `/Volumes/Windows/proj_Win/.android-sdk/platform-tools/adb` on the Mac. It
  is not on PATH; the scripts resolve it as `$ANDROID_HOME`, else
  `<repo>/../.android-sdk`.
- The app's Swift `print` and its `Pn` logs reach logcat under the tag `Swift`:
  `adb logcat -d | grep '\[P96\]'`.
- `Choreographer: Skipped N frames` and `Displayed <pkg>/...: +Xms` in logcat
  measure how long the main thread was held and when the first frame showed.
- `adb shell am start -W -n <pkg>/dev.swiftcrossui.testapp.MainActivity` prints
  `TotalTime` for a launch.

## simpleperf

The emulator image is userdebug, so `adb root` works. Its CPU has no hardware
counters, so use `-e cpu-clock`:

```zsh
adb root
adb shell am force-stop <pkg>
adb shell simpleperf record -a -e cpu-clock -g --duration 5 -o /data/local/tmp/x.perf.data &
sleep 1.5; adb shell am start -W -n <pkg>/dev.swiftcrossui.testapp.MainActivity
pid=$(adb shell pidof <pkg>)
adb shell simpleperf report -i /data/local/tmp/x.perf.data --tids $pid --sort dso
adb shell simpleperf report -i /data/local/tmp/x.perf.data --tids $pid --children --sort symbol
adb unroot
```

The main thread's tid is the pid. Swift symbols in the APK are stripped, so
the report shows `libPn.so[+offset]`. Symbolize those offsets against the
unstripped library:

```zsh
ndk=/Volumes/Windows/proj_Win/.android-sdk/ndk/30.0.16248370/toolchains/llvm/prebuilt/darwin-x86_64/bin
lib=testapp/.compile-work-android/gradleProject/build/intermediates/merged_native_libs/debug/mergeDebugNativeLibs/out/lib/arm64-v8a/libP96.so
$ndk/llvm-symbolizer --obj=$lib --functions=linkage --no-inlines 0x82cdc4 | swift demangle --simplified
```

`llvm-nm -S --defined-only` on the same file gives symbol sizes. Grouping them
by the module in the Swift mangling shows which module a library's size comes
from.

## What to compare against

- Run the same app with its action file too. A sleep-only action file launches
  a little later after install, and that alone moved P96 from failing to
  passing on 2026-10-23.
- The emulator's state matters. P96's 2.7 s first-frame stall was seen for
  15 minutes on an emulator that had run 40 apps, and never on a fresh one.
  Before calling something a regression, try a fresh emulator, and reproduce
  with the old `Sources` checked out (`git checkout <rev> -- Sources/...`, then
  restore).

---

# 分析 Android 測試 app 的效能

2026-10-24 在 api36b 模擬器上行得通的做法。

## 工具與位置

- adb:Mac 上在 `/Volumes/Windows/proj_Win/.android-sdk/platform-tools/adb`,不在 PATH 上；腳本以 `$ANDROID_HOME`
  解析，否則用 `<repo>/../.android-sdk`。
- app 的 Swift `print` 與 `Pn` 紀錄以 `Swift` tag 進入 logcat:`adb logcat -d | grep '\[P96\]'`。
- logcat 裡的 `Choreographer: Skipped N frames` 與 `Displayed <pkg>/...: +Xms` 量的是主執行緒被佔住多久、第一幀何時出現。
- `adb shell am start -W -n <pkg>/dev.swiftcrossui.testapp.MainActivity` 會印出這次啟動的 `TotalTime`。

## simpleperf

模擬器映像是 userdebug,所以 `adb root` 可用；它的 CPU 沒有硬體計數器，所以用 `-e cpu-clock`(指令見上方英文段落)。
主執行緒的 tid 就是 pid。APK 裡的 Swift 符號已去除，所以報告顯示 `libPn.so[+offset]`;拿未去符號的函式庫解析這些位址
(見上方)。對同一個檔案跑 `llvm-nm -S --defined-only` 可得符號大小，依 Swift mangling 裡的模組分組，就看得出函式庫的
大小來自哪個模組。

## 要拿什麼來比

- 同一支 app 也用它的動作檔跑一次。只會等待的動作檔讓 app 在安裝後稍晚才啟動，2026-10-23 光這一點就讓 P96 從失敗變成
  通過。
- 模擬器的狀態有影響。P96 那段 2.7 秒的第一幀卡頓，只在一台跑過 40 支 app 的模擬器上出現了 15 分鐘，在重開的模擬器上
  從未出現。要判定退化之前，先試重開的模擬器，並把舊的 `Sources` checkout 回來重現(`git checkout <rev> -- Sources/...`,
  之後還原)。
