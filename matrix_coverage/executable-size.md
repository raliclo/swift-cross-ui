# Executable size per platform

`executable-size.csv2` records how large each test app builds on each platform
and backend. Read and write it with `csv2` — it has two header rows and the note
column contains commas.

`executable-size.csv2` 記錄每一支測試 app 在各平台、各 backend 下建置出來的大小。請以 `csv2`
讀寫——它有兩列表頭，且備註欄含有逗號。

## Why Windows has two columns

On Windows the same app builds against either backend, and the two differ by
about **3x**: roughly 56 MB for `-gtk4`, 178 MB for WinUI. That gap is the
measured reason `compile.zsh -gtk4` removes the WinUI products from the package
rather than only redirecting `DefaultBackend` — with the products still listed
the build compiled 73 extra WinUI steps and produced a 342 MB binary while
still running on GtkBackend, which is the switch without either saving.

The executables are named `<app>-gtk4.exe` and `<app>-WinUI.exe` for the same
reason a column is not enough: a capture matched by window title photographed
the wrong backend's window on 2026-09-02, and the two files were
indistinguishable once copied side by side.

Windows 之所以有兩欄：同一支 app 可對兩個 backend 各建一次，而兩者相差約 **3 倍**——`-gtk4` 約
56 MB，WinUI 約 178 MB。那個差距正是 `compile.zsh -gtk4` 選擇把 WinUI product 整組移出套件、而非
僅重新導向 `DefaultBackend` 的實測理由：product 仍列出時，建置多編了 73 個 WinUI 步驟、產生 342 MB
的執行檔，而 app 仍跑在 GtkBackend 上——切換達成了，兩項效益一項也沒有。

## Regenerating the numbers

Sizes are bytes, from `stat -c %s`. They change with every toolchain or library
change, so **re-measure rather than trust a row older than a week**.

```zsh
# Windows, both backends
cd testapp && SCUI_DEBUG=1 zsh compile.zsh          # -> <app>-WinUI.exe
cd testapp && SCUI_DEBUG=1 zsh compile.zsh -gtk4    # -> <app>-gtk4.exe
cd testapp/output && for f in P*-gtk4.exe P*-WinUI.exe; do
    printf '%s\t%s\n' "$f" "$(stat -c %s "$f")"
done

# Linux, in the WSL checkout
wsl.exe -d Ubuntu -- bash /tmp/lxsizes.sh

# iOS -- the Mach-O inside the bundle, not the bundle
cd testapp && SCUI_DEBUG=1 zsh compile.zsh -ios
cd testapp/output && for d in P*-ios.app; do
    a=${d%-ios.app}
    printf '%s\t%s\n' "$a" "$(stat -f %z "$d/$a")"
done

# Android -- two numbers, and they are different things
cd testapp && for a in P0 P1 ...; do SCUI_DEBUG=1 zsh test_android.zsh "$a" --no-showtime; done
cd testapp && for f in output/P*-android; do
    printf '%s\t%s\n' "${f##*/}" "$(stat -f %z "$f")"
done
cd testapp && for f in .androidApk/P*.apk; do
    printf '%s\t%s\n' "${f##*/}" "$(stat -f %z "$f")"
done
```

`stat -f %z` on macOS, `stat -c %s` on Linux and in WSL. The two flags mean the
same thing and neither is portable; a command copied from the Linux block into a
Mac shell fails with `stat: illegal option -- c`, which is at least loud.

The iOS number is the executable inside the bundle and not the bundle: measured
2026-09-02, `P12-ios.app` is 8,949,760 bytes against its `P12` executable's
8,933,456, so the bundle adds 16 KB of Info.plist and signature. Recording the
bundle would put this column in different units from every other one, which are
all executables.

Android needs two columns because the two numbers answer different questions.
The executable is what compares with the other platforms; the APK is what
installs, and it is 38 MB larger because it carries the Swift runtime's shared
libraries beside the executable rather than inside it.

macOS 用 `stat -f %z`，Linux 與 WSL 用 `stat -c %s`。兩個旗標意思相同，而且都不可移植；把 Linux
區塊的命令複製到 Mac 的 shell 會得到 `stat: illegal option -- c`——至少那是有聲的。

iOS 記的是 bundle **之內**的執行檔，而不是 bundle 本身：2026-09-02 實測，`P12-ios.app` 為
8,949,760 位元組，而其中的 `P12` 執行檔為 8,933,456，因此 bundle 多出約 16 KB 的 Info.plist 與
簽章。若記錄 bundle，本欄的單位就會與其他每一欄（全是執行檔）不同。

Android 需要兩欄，因為那兩個數字回答的是不同的問題。執行檔是能與其他平台相比的那一個；APK 則是
實際安裝的那一個，而它大了 38 MB，因為它把 Swift runtime 的共享函式庫放在執行檔**旁邊**，
而不是放在其中。

`lxsizes.sh` must be run as a **file**. A `find -printf '%f|%s\n'` passed on a
quoted `wsl.exe` command line comes back empty — the format string does not
survive the trip, and the failure is silent output rather than an error.

`lxsizes.sh` 必須以**檔案**形式執行。把 `find -printf '%f|%s\n'` 放在帶引號的 `wsl.exe` 命令列上
會得到空的輸出——格式字串無法通過那一段，而且失敗的形式是「沒有輸出」而不是錯誤。

## Averages

```zsh
csv2 -r -i matrix_coverage/executable-size.csv2 | awk -F, '
  {for(i=2;i<=8;i++) if($i ~ /^[0-9]+$/) {s[i]+=$i; n[i]++}}
  END{split("_ windows_gtk4 windows_winui linux_gtk4 macos_appkit ios_uikit android_exe android_apk",L," ");
      for(i=2;i<=8;i++) if(n[i]) printf "%-14s n=%-3d avg=%7.1f MB\n", L[i], n[i], s[i]/n[i]/1048576}'
```

The range was 2–4 until 2026-09-04 and is now 2–8, and the `if(n[i])` guard is
new with it: `macos_appkit` has no numbers at all, and dividing by `n=0` printed
`-nan` rather than skipping the column.

Two things about that command, both learned by getting them wrong.

**No `-tail`.** `csv2 -r` already emits data rows only, so an earlier version
of this page piping through `-tail 45` was both unnecessary and lossy: the file
has 47 rows, so it silently dropped **P0 and P1** and reported `n = 44/44/45`.
The averages it printed were 53.9 / 169.7 / 52.7 MB — *identical to one decimal
place* with those two rows restored, because the values are so uniform. The
mistake changed the sample and not the answer, which is why nothing looked
wrong. Report `n` next to any average for exactly this reason: it is the only
column that moved.

**The `$i ~ /^[0-9]+$/` guard is load-bearing.** Without it `n/a` sums as **0**
and still counts toward `n`, dragging every average down silently.

關於那道命令的兩件事，都是做錯之後才學到的。

**不要用 `-tail`。** `csv2 -r` 本來就只輸出資料列，因此本頁較早的版本再接一段 `-tail 45`
既多餘又有損：檔案有 47 列，於是它靜默丟掉了 **P0 與 P1**，並報出 `n = 44/44/45`。它印出的
平均值是 53.9 / 169.7 / 52.7 MB——把那兩列補回去之後**到小數第一位完全相同**，因為各值太過
一致。這個錯誤改變的是樣本而非答案，所以看不出任何異狀。請在任何平均值旁邊一併報出 `n`，
理由正是如此：它是唯一會動的那一欄。

Windows and Linux measured 2026-09-02, iOS the same day, Android 2026-09-04.
48 rows.

| Column | n | Average | Range | Empty | vs GTK4 |
|---|---:|---:|---|---:|---:|
| Windows GTK4 | 46 | 53.9 MB | 53.9–54.2 | 2 | 1.00x |
| Windows WinUI | 46 | 169.7 MB | 169.6–170.3 | 2 | **3.15x** |
| Linux GTK4 | 47 | 52.7 MB | 52.0–53.3 | 1 | 0.98x |
| macOS AppKit | 0 | — | — | 48 | — |
| iOS UIKit | 46 | 8.5 MB | 8.5–8.7 | 2 | **0.16x** |
| Android executable | 45 | 173.3 MB | 173.1–173.6 | 3 | **3.21x** |
| Android APK | 44 | 211.5 MB | 211.5–211.8 | 4 | 3.92x |

The empty counts rose by one across the older columns because P44 was added on
2026-09-04 and exists only on Android so far; `P6-v2` and `P6` account for the
rest, as the table below records.

Windows/Linux 量於 2026-09-02，iOS 同日，Android 量於 2026-09-04。全表 48 列。舊有各欄的空格數
各增加一格，是因為 P44 於 2026-09-04 新增、目前只在 Android 上存在；其餘則由 `P6-v2` 與 `P6`
說明，見下方表格。

WinUI costs **115.8 MB more per app**, and the spread across all 46 is only
0.7 MB — so that is not application code, it is the statically linked WinRT/UWP
projection, paid once by every app. Windows GTK4 sits 1.2 MB (2.3%) above Linux
GTK4, which puts the whole 3.15x on the backend choice rather than the OS.

**iOS is the outlier downward and Android the outlier upward, for the same
reason.** An iOS app is 8.5 MB against Windows GTK4's 53.9 — 0.16x — because
Swift's runtime and Foundation ship with the OS and the app links against them.
Android has no such runtime on the device, so every app carries its own: the
executable is 173.3 MB and the APK 211.5 MB, and the APK is larger than the
executable because it also contains the runtime's shared libraries beside it.
The spread within each column is under half a megabyte across 44 apps, which is
what says this is per-platform overhead rather than anything the apps do.

**The Android figures are debug builds, and it does not matter.** `test_android.zsh`
builds debug because `SCUI_DEBUG` is what makes action-file replay exist at all,
while `compile.zsh` defaults to release, so the two are not the same
configuration. Measured on P12 the same day: release 181,824,952 bytes against
debug 181,629,584 — **0.1% apart**, because the size is the statically linked
runtime either way. P12's row carries the release number and says so in its
note; every other Android row is debug.

**iOS 是向下的例外，Android 是向上的例外，而兩者出於同一個原因。** 一支 iOS app 是 8.5 MB，相對於
Windows GTK4 的 53.9——0.16 倍——因為 Swift 的 runtime 與 Foundation 隨作業系統出貨，app 是連結
它們的。Android 的裝置上沒有這樣的 runtime，因此每一支 app 都自行攜帶：執行檔是 173.3 MB，APK 是
211.5 MB，而 APK 比執行檔大，是因為它同時還在旁邊放了該 runtime 的共享函式庫。每一欄之內、跨 44 支
app 的極差都不到半個 MB——正是這一點說明了它是平台的固定成本，而非各 app 所為。

**Android 的數字是 debug 建置，而那不重要。** `test_android.zsh` 建的是 debug，因為 `SCUI_DEBUG`
正是「動作檔重放得以存在」的前提；而 `compile.zsh` 預設為 release，因此兩者並非同一種組態。同日於
P12 上實測：release 為 181,824,952 位元組，debug 為 181,629,584——**相差 0.1%**，因為無論哪一種，
其尺寸都是那份靜態連結的 runtime。P12 那一列記的是 release 的數字，並在其 note 欄寫明；其餘每一列
的 Android 數字都是 debug。

`$i ~ /^[0-9]+$/` 這個條件是關鍵：少了它，`n/a` 會以 **0** 計入總和且仍佔一個 `n`，靜默拉低每一個
平均值。WinUI 每支多付 **115.8 MB**，而 43 支的極差只有 0.3 MB——那不是應用程式碼，是靜態連結的
WinRT/UWP projection，每支各付一次。Windows GTK4 只比 Linux GTK4 多 1.2 MB（2.3%），因此那 3.15
倍完全落在 backend 選擇上，與作業系統無關。

## What is inside an Android APK, and what came off it

Measured 2026-09-04 on P43 with `llvm-size --format=sysv` and
`llvm-nm --dynamic --defined-only --print-size`.

**212 MB, of which 43 was a debug section nothing reads.** `.swift_ast` is the
serialized Swift AST lldb uses to describe types: 45.0 MB of a 137.6 MB library,
its second largest section after `.text`'s 56.7. The bundler now removes it from
the packaged copy, which takes **the APK to 169 MB** with the rendering
unchanged pixel for pixel. `SCUI_KEEP_SWIFT_AST=1` puts it back for a build you
mean to attach a debugger to.

**Against iOS, the same app is 8.6 MB.** P43 measured 2026-09-05: an Android
APK of 169 MB against an iOS `.app` bundle of 8.6, a factor of 20. None of that
gap is this project's code -- SwiftCrossUI's own symbols are 2.3 MB in the
Android binary. Swift's runtime ships with iOS and the app links against it;
Android has none on the device, so `lib_FoundationICU.so` alone, at 40 MB, is
nearly five times the entire iOS app.

**與 iOS 相比，同一支 app 是 8.6 MB。** P43 於 2026-09-05 量測：Android APK 為 169 MB，iOS 的
`.app` bundle 為 8.6 MB，相差 20 倍。這個差距沒有一分是本專案的程式碼造成的——SwiftCrossUI 自身的
符號在 Android 執行檔中是 2.3 MB。Swift 的 runtime 隨 iOS 出貨、app 是連結它的；Android 的裝置上
沒有，因此光是 `lib_FoundationICU.so` 的 40 MB，就將近整支 iOS app 的五倍。

**The remaining 169 MB**, by what is in it:

| part | size | |
|---|---:|---|
| `libP43.so` | 73 MB | the app, everything static |
| `lib_FoundationICU.so` | 38 MB | ICU data, shipped by every app |
| everything else in `lib/` | ~32 MB | the rest of the Swift runtime |
| `classes.dex` | 10 MB | |

**ICU is not removable from this tree, and that is measured rather than
assumed.** `llvm-readelf -d` shows `libFoundation.so` carrying
`lib_FoundationICU.so` as a hard `NEEDED` entry, so any app that imports
Foundation pulls in all 38 MB. `libFoundationEssentials.so`, the ICU-free core,
does not need it -- an app confined to that would not pay for ICU, but every app
here imports Foundation proper. Shrinking the blob itself means rebuilding the
Swift Android SDK, which this tree does not own.

**Nothing else in `lib/` is dead weight**: of the 21 libraries, every one but
`libshim.so` (0 MB, loaded by the JNI entry point) is a declared `NEEDED` of
something else in the APK.

**ICU 無法從本樹中移除，而這是量出來的、不是假定的。** `llvm-readelf -d` 顯示
`libFoundation.so` 把 `lib_FoundationICU.so` 列為硬性的 `NEEDED` 項目，因此任何 import Foundation
的 app 都會帶進那整整 38 MB。不需要它的是 `libFoundationEssentials.so`——那個不含 ICU 的核心；
一支只用它的 app 不必為 ICU 付費，但此處每一支 app 用的都是完整的 Foundation。要縮小那個資料塊
本身，就得重建 Swift Android SDK，而本樹並不擁有它。

**`lib/` 中其餘沒有任何贅物**：21 個函式庫中，除了 `libshim.so`（0 MB，由 JNI 進入點載入）之外，
每一個都是 APK 內其他東西所宣告的 `NEEDED`。

And inside `libP43.so`, the defined dynamic symbols account for 33.9 MB:

| module | size |
|---|---:|
| **SwiftSyntax** | **9.6 MB** |
| Android bindings (`AndroidView`, `SwiftJava`, `AndroidMaterial`, …) | ~16 MB |
| SwiftCrossUI | 2.3 MB |

**SwiftSyntax was a compile-time library and it shipped, until 2026-09-05.**
Removing SwiftCrossUI's direct dependency on it when `SCUI_ANDROID` is set takes
79,105 symbols out of the binary and **the APK from 169 MB to 154**, with P43's
gradients unchanged and macOS's 53 tests still passing -- macOS keeps the
dependency, which is what the workaround was for.

The first attempt read as a no-op and was reverted on that reading. It was not
the edit: llbuild caches the build plan, and `debug.yaml` and `build.db` have to
be deleted with any manifest change. Clearing only SwiftPM's manifest cache is
not enough. The paragraph below is what that failed attempt concluded, kept
because the conclusion was wrong for a reason worth seeing.

**SwiftSyntax is a compile-time library and it ships.** It is larger in the
binary than SwiftCrossUI itself. `Package.swift` has SwiftCrossUI depending on
it directly, with a comment saying it works around a macOS linker and plugin
problem -- but **making that dependency non-Android changes nothing**: tried
2026-09-04, the symbols and the 169 MB both stayed exactly as they were, so it
arrives by another path, most likely the macro plugin. The edit was reverted
rather than left in place looking like a saving.

## 一支 Android APK 的內容，以及從它身上拿掉了什麼

2026-09-04 於 P43 上，以 `llvm-size --format=sysv` 與
`llvm-nm --dynamic --defined-only --print-size` 量測。

**212 MB，其中 43 MB 是一個沒有任何東西會讀取的除錯 section。** `.swift_ast` 是 lldb 用來描述型別的
序列化 Swift AST：在一個 137.6 MB 的 library 中佔 45.0 MB，是繼 `.text` 的 56.7 MB 之後第二大的
section。bundler 現在會從打包的副本中移除它，使 **APK 降到 169 MB**，而繪製結果逐像素不變。
`SCUI_KEEP_SWIFT_AST=1` 會把它放回去，供「你打算附加除錯器」的建置使用。

**剩下的 169 MB** 的組成：`libP43.so` 87 MB（整個 app，全部靜態連結）、`lib_FoundationICU.so`
40 MB（ICU 資料，每支 app 各帶一份）、`lib/` 中其餘約 32 MB（Swift runtime 的其餘部分）、
`classes.dex` 10 MB。

而在 `libP43.so` 之內，已定義的動態符號合計 33.9 MB：**SwiftSyntax 9.6 MB**、Android 綁定
（`AndroidView`、`SwiftJava`、`AndroidMaterial` 等）約 16 MB、SwiftCrossUI 2.3 MB。

**SwiftSyntax 是編譯期函式庫，而它會出貨。** 它在該執行檔中比 SwiftCrossUI 自身還大。
`Package.swift` 中 SwiftCrossUI 直接依賴它，註解說那是為了繞過 macOS 的 linker 與 plugin 問題
——但**把該依賴改為「非 Android 才加入」毫無改變**：2026-09-04 試過，符號與 169 MB 都一模一樣，
因此它是循另一條路徑進來的，最可能是 macro plugin。那次編輯已被撤回，而不是留在原處、看起來像是
一項節省。

## Empty cells and `n/a`

The two are different and the difference is the point:

- **`n/a`** — the combination does not exist by design. Nothing to build.
- **empty** — it should exist and does not. A real gap; the `note` says what is
  known.

Neither ever means zero.

兩者不同，而這個區別正是重點：**`n/a`** 表示該組合按設計就不存在，沒有東西可建；**空白**表示它應該
存在卻沒有——那是真實的缺口，`note` 欄記錄已知的部分。兩者都不代表零。

**Current status.** Only two cells are `n/a`, and no cell is empty except the
whole `macos_appkit` column:

| App | Cell | Why |
|---|---|---|
| `P6` | windows_gtk4 | `n/a` — imports the WinUI products under `#if os(Windows)`, which `-gtk4` removes; the guard stays true because the flag changes products, not the OS |
| `P6-v2` | windows_winui | `n/a` — pure GTK app, no WinUI counterpart exists |
| every app | macos_appkit | empty — never measured. The Mac in use builds and runs macOS apps, so this is a sweep that has not been run rather than a platform that is out of reach |
| `P6-v2` | ios_uikit, android_* | empty — GTK-only app; it has no iOS or Android build and no action file on either |
| `P12` | android_apk | empty — the executable was measured but no APK was on disk when the sweep ran |
| `P15-DARK`, `P17-DOE` | android_apk | empty — variants that are built when their experiment is run, not by the standard sweep |
| `P44` | everything but Android | empty — added 2026-09-04 and only built for Android so far |

**Resolved 2026-09-02**, kept because what the gaps turned out to be is worth
more than the fact they are closed:

| App | Cell | Was | Turned out to be |
|---|---|---|---|
| `P6` | windows_winui | empty | The link had died with `LLVM ERROR: IO failure on output stream: no space on device`, which reads as a compiler crash. The disk was full at 336 MB free. Rebuilt with 7.6 GB free: 178,624,000 bytes, no errors |
| `P7` `P8` `P9` | windows_gtk4 | empty | Nothing at all — the earlier sweep had missed them. Rebuilt on a quiet machine, all three produced |
| `P28` | linux_gtk4 | empty | Same: `P28.swift` was present in the WSL checkout and byte-identical to the Windows copy; the Linux sweep had skipped it |

**目前狀態。** 只有兩格是 `n/a`，除了整欄的 `macos_appkit` 之外沒有空格。
**2026-09-02 已解決**的部分仍保留於上表，因為那些空格「原來是什麼」比「它們已經補上」更有價值。

## What the empty cells found

The gaps were the useful part of building this table, which is the argument for
keeping it: three of them are real defects that nothing else was reporting.

`P7`, `P8` and `P9` had no `-gtk4` executable, and neither skip rule explained
it. **Resolved 2026-09-02: the earlier sweep had simply missed them.** Rebuilt
on a quiet machine, `compile.zsh -gtk4 P7 P8 P9` returned 0 and produced all
three (56.6, 56.6, 56.5 MB) with no errors. Nothing in the source or in
`compile.zsh` was at fault.

Three attempts failed before that, and none of the failures were about `P7`.
The two false readings they produced are worth more than the answer:

`P7`、`P8`、`P9` 原本沒有 `-gtk4` 執行檔，而兩條 skip 規則都無法解釋。**2026-09-02 已解決：
就是先前那趟掃描漏掉了它們。** 在淨空的機器上重建，`compile.zsh -gtk4 P7 P8 P9` 回傳 0 並產出
全部三支（56.6、56.6、56.5 MB），沒有任何錯誤。原始碼與 `compile.zsh` 都沒有問題。

在那之前失敗了三次，而沒有一次的失敗與 `P7` 有關。它們造成的兩次誤讀比答案本身更值得記下：

**Exit code 0 with nothing built.** The attempt ran
`zsh compile.zsh … > log 2>&1; printf 'rc=%d\n' $?; tail -30 log`. The harness
reports the status of the **last** command in that chain — `tail`, which
succeeds — so the run looked clean while `compile.zsh` had returned 1. Record
the status inside the log (`rc=$?` on its own line); do not trust what wraps the
command.

**Then `rc=1` was read as a build failure, and it was not.** `swift-build.exe`
outlived the shell that started it and was still compiling `P7` minutes later —
confirmed by its command line (`--product P7`, started 13:19:23) while a second
attempt failed with `unable to attach DB: database is locked`. A nonzero status
from a parent whose child is still running says nothing about the build. Check
for live `swift-build.exe` before reading any build result.

追查過程中出現兩次誤讀，兩者都比答案本身更值得記下。

**其一：退出碼 0，卻什麼都沒建出來。** 工具回報的是鏈中**最後一個**命令 `tail` 的狀態，而它成功，
於是這一輪看起來乾淨，實際上 `compile.zsh` 回傳的是 1。請把狀態記進紀錄檔本身（獨立一行的
`rc=$?`），不要相信包在命令外面的東西。

**其二：接著把 `rc=1` 讀成建置失敗，而它不是。** `swift-build.exe` 比啟動它的 shell 活得更久，
數分鐘後仍在編譯 `P7`——由其命令列（`--product P7`，13:19:23 啟動）確認，同時第二次嘗試以
`unable to attach DB: database is locked` 失敗。一個 child 仍在執行的 parent 所回傳的非零狀態，
對建置結果毫無意義。讀任何建置結果之前，先確認沒有活著的 `swift-build.exe`。

`P0-winui-baseline` and `P45-MIN` are not rows here: they are hand-made
executables with no `.swift` source, so they cannot be rebuilt and a size for
them would describe an artefact nobody can reproduce.

空白格代表**未建置**，絕不代表**零**。`note` 欄在原因已知時會說明。
`P0-winui-baseline` 與 `P45-MIN` 不列入：它們是沒有 `.swift` 原始碼的手工執行檔，無法重建，
為它們記錄一個大小，等於描述一個沒有人能重現的產物。
