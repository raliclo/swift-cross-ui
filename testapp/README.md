# testapp

Standalone apps that reproduce specific upstream issues, plus the documents
that say which app tests what and what has been verified.

**This directory does not exist upstream.** Nothing here can be part of a pull
request, which is why every commit touching it is recorded as `local` in
`issue_commits.csv` and why commits that mix `Sources/` and `testapp/` changes
need the `testapp/` half dropped before submitting.

## Start here

| Question | File |
| --- | --- |
| Where do I run this issue, and does the answer count? | `UI-test-plan platform-en.md` |
| What are the steps for app PN? | `UI-test-plan overall-en.md` |
| What is the plan for the GtkBackend work? | `UI-test-plan linux-en.md` |
| What is the plan for the AppKit/Android/iOS work? | `UI-test-plan bug-en.md` |
| What is the state of every upstream issue? | `issues.csv` |
| Which commit fixes what, and can it be submitted? | `issue_commits.csv` |

`UI-test-plan platform-en.md` is the entry point: it maps all 40 covered issues onto
the six platforms and marks, per cell, whether a run there settles the issue,
is only a comparison, or tells you nothing.

## The apps

P0-P44 and P46, plus `P15-DARK`, `P17-DOE` and `P6-v2`, are one Swift file each
-- 49 in total, counted with `ls -1 testapp/P*.swift | wc -l`. Each is built as
a standalone executable when the current
platform supports their backend. P0-P6 came out of the WinUIBackend work,
P7-P10 and P15 target GtkBackend, P11 AppKitBackend, P12 AndroidBackend, P14
UIKitBackend, and P13, P16 and P17 cover core layout and split-view behaviour.
Later apps extend backend feature, visual-fidelity, window-level, GPU and
DatePicker coverage. `UI-test-plan platform-en.md` has the full issue-to-platform
mapping.

```sh
zsh testapp/compile.zsh P7 P15 P17     # build a subset
zsh testapp/compile.zsh                # build everything
```

Output lands in `testapp/output/` -- `PN` on Linux and macOS, and on Windows
`PN-gtk4.exe` or `PN-WinUI.exe`, named for the backend it was built against.
**There is no suffix-less `PN.exe`**, and a command that names one will fail:
`ls testapp/output/*.exe` returns 45 files and every one carries a suffix.
Corrected 2026-09-07; the executables gained their suffix for the same reason
the build trees have one, which the next sentence already explains.
Neither the output directory nor the `.compile-work-*` build trees are
tracked. There is one tree per backend and the suffix names it -- there is
deliberately no suffix-less `.compile-work`, because its contents would depend
on the host rather than on its name. Both rules live in the root `.gitignore`;
`/testapp/output/` was added there on 2026-09-07, having until then been
ignored only by one checkout's untracked `.git/info/exclude`.

### `output/build-manifest.csv2`

The filename says which backend built an executable. It does not say which
*configuration*, and nothing inside the binary does either. Measured
2026-09-07: `output/` held 43 `-gtk4.exe` files in two size clusters, 56-57 MB
(33 files) and 80 MB (10 files), where the todo list had recorded one debug
binary. Three indirect checks were tried to tell the clusters apart -- an
embedded build-config path, the string `Sources/SwiftCrossUI`, and `.swift`
string density -- and all three found nothing, which looks exactly like the
files being the same. What settled it was rebuilding P7 at the default and
watching it move 80,582,656 to 57,024,000 bytes: a 23-minute build to answer a
question one recorded line answers free.

So `compile.zsh` now writes a row per artefact as it copies it out, into
`output/build-manifest.csv2` -- `file,app,platform,backend,config,scui_debug,built,bytes`,
a `.csv2` with the usual two header rows. Read and write it with `csv2`, never
with `awk -F,` or `cut -d,`.

```sh
csv2 -r -i testapp/output/build-manifest.csv2 -t      # read it
zsh testapp/compile.zsh --manifest                    # audit it, builds nothing
zsh testapp/compile.zsh --manifest --prune            # and drop rows whose file is gone
```

`--manifest` reports the three ways the manifest and the directory can
disagree and exits non-zero if any of them fired, so it works as a preflight:

| | Means |
| --- | --- |
| `unrecorded` | a file in `output/` with no row. Built before the manifest existed, or copied in by hand. Its configuration is genuinely unknown -- rebuild it rather than guessing from its size |
| `orphan` | a row whose file is gone. `--prune` removes the row; without it the row is reported and left, because a read-only audit that mutates is not one |
| `changed` | the file is not the size its row records, so something other than `compile.zsh` replaced it and the row describes a different binary. Never repaired automatically |

Every run also compares the row count against the artefact count and says so
when they differ. That is the cheap check, not the full audit: the full audit
costs two `csv2` calls per row, about twelve seconds on a 45-row manifest,
against a six-second warm incremental build.

### `output/build-manifest.csv2`（中文）

檔名說得出執行檔是由哪個 backend 建出來的，卻說不出它是哪一種**組態**，而執行檔內部也
一樣說不出。2026-09-07 實測：`output/` 中有 43 個 `-gtk4.exe`，分成 56-57 MB（33 個）與
80 MB（10 個）兩個尺寸叢集，而待辦清單只記了一個 debug 執行檔。當時試了三種間接檢查來分辨
兩個叢集——內嵌的 build-config 路徑、字串 `Sources/SwiftCrossUI`、以及 `.swift` 字串密度
——三種都什麼也沒找到，而那看起來與「這些檔案本來就相同」完全一樣。真正定案的是以預設組態
重建 P7，看著它從 80,582,656 變成 57,024,000 位元組：為了回答一個「寫下一行就免費得到答案」
的問題，付出了 23 分鐘的建置。

因此 `compile.zsh` 現在會在複製出每一個產物時，於 `output/build-manifest.csv2` 寫下一列
——`file,app,platform,backend,config,scui_debug,built,bytes`，一份帶有慣例兩列標頭的
`.csv2`。請以 `csv2` 讀寫它，絕不要用 `awk -F,` 或 `cut -d,`。指令見上方英文區塊。

`--manifest` 會回報 manifest 與目錄之間可能不一致的三種情形，只要任一發生就以非零狀態
結束，因此可當作前置檢查使用：

| | 意義 |
| --- | --- |
| `unrecorded` | `output/` 中有檔案但沒有對應資料列。它建於本 manifest 出現之前，或是被手動複製進來。它的組態是真的未知——請重建它，不要從大小去猜 |
| `orphan` | 有資料列但檔案已不存在。`--prune` 會移除該列；不加時只回報並保留，因為「會改動東西的唯讀稽核」不叫唯讀稽核 |
| `changed` | 檔案的大小與資料列所記不同，代表有 `compile.zsh` 以外的東西換掉了它，該列描述的是另一個執行檔。絕不自動修復 |

每一次執行也會比對資料列數與產物檔數，不同時就出聲。那是便宜的檢查，不是完整稽核：完整
稽核每列要花兩次 `csv2` 呼叫，45 列約十二秒，而單一 app 的熱增量建置只要六秒。

## Environment setup

| Script | For |
| --- | --- |
| `install_tool_wsl.zsh` | WSL: GTK 4, the Swift tarball, and the libxml2/ICU shims Ubuntu 26.04 needs |
| `install_tools_ios.zsh` | macOS: the iOS Simulator toolchain, called automatically by `compile.zsh -ios` |
| `install_tool_mac.zsh` | macOS: GTK 4 via Homebrew, and the two things `swift test` needs to run on a Mac at all. `--test` runs the suite |
| `install_tools_android.zsh` | macOS: the Android SDK, NDK and emulator the Android runner needs |

## Running a test

`test.zsh` is the entry point for every platform:

```sh
zsh testapp/test.zsh P8                 # this host's platform
zsh testapp/test.zsh P8 --both          # WSLg, then Windows
zsh testapp/test.zsh P28 --macos --actionfile
zsh testapp/test.zsh P14 --ios
zsh testapp/test.zsh P12 --android
```

### Platforms

The platform flag is optional. Each test declares the platform it was written
for and most were written on Windows, so on a Mac the declared platform is
usually one this host cannot drive; the run moves to one it can and says so.
Naming a platform this host cannot drive is refused rather than redirected.

| Host | Can drive |
| --- | --- |
| Windows | `--windows` (`-win`), `--wsl`, `--both` |
| macOS | `--macos`, `--ios`, `--android` |

`--wsl` and `--both` reach into WSL with `wsl.exe`, so they need a Windows host
rather than a Linux one. `--ios` and `--android` need macOS.

### Flags

The same flags mean the same thing on every platform, iOS and Android included.

| Flag | Effect |
| --- | --- |
| `-n`, `--no-build` | Reuse what is already built |
| `--showtime <s>`, `--no-showtime` | How long to leave the app up after it renders |
| `--actionfile [path]` | Replay a CSV of synthesised input once the window is up. Without a path, `testapp/actions/<platform>/<Pn>-*.csv` is used — one folder per platform, because a file verified elsewhere is not evidence here |
| `--device <name>` | iOS and Android only; refused on the others |

### Devices

Neither iOS nor Android needs a device named or an environment variable set.

`--ios` uses a Simulator called `swift-cross-ui`, which `install_tools_ios.zsh`
creates as an iPhone 16. `--android` boots the first AVD `emulator -list-avds`
reports, and says so if none exists rather than failing further in.

`--device` overrides either: a Simulator name or UDID for iOS, an AVD name or an
adb serial for Android. `IOS_SIM_DEVICE` and `ANDROID_AVD_NAME` do the same
thing from the environment.

### Screenshots

Every platform captures, into `testapp/output/screenshots/<label>-<timestamp>.png`.
Each run takes one shortly after launch and one at the end.

| Platform | How | Subject |
| --- | --- | --- |
| Windows, WSLg | `screenshot.zsh`, wincap for `-w`; gdigrab only without `-w` | the named window, or the desktop when explicitly requested |
| macOS | `screenshot.zsh`, `screencapture` | the named window by CGWindowID, or the display |
| iOS | `simctl io ... screenshot` | the Simulator's own framebuffer |
| Android | `adb exec-out screencap` | the device's own framebuffer |

iOS and Android do not go through `screenshot.zsh`: it captures a display, and
the device's framebuffer is a different image from the Simulator or emulator
window as composited on this Mac. They also need no Screen Recording permission,
where the macOS path does.

A failed capture is reported and counted, never swallowed, and never aborts the
run -- a screenshot is evidence, not the assertion. On Windows and WSLg,
`screenshot.zsh -w` fails closed when wincap cannot capture the named window;
omit `-w` only when the desktop is the intended subject. On macOS a fallback
from the window to the whole display is itself a signal: a sleeping display
defeats window capture while a full-screen grab still succeeds and returns a
black frame.

| Script | For |
| --- | --- |
| `test.zsh` | The command. Finds `test_support/test_Pn.zsh`, which sets the app's details and hands over to `test_support/test_common.zsh` |
| `test_common.zsh` | Parses the flags, resolves the platform, and runs WSLg, Windows or macOS directly; delegates iOS and Android to the two scripts below, rebuilding the flags in their spelling |
| `test_ios.zsh` | macOS: installs a Pn through the fixed `debugTarget` iOS bundle and launches Simulator; optionally replays an action file through XCUITest. Reached as `test.zsh <Pn> --ios` |
| `test_android.zsh` | macOS: builds and bundles a Pn as an APK, installs it on the emulator and launches it. Reached as `test.zsh <Pn> --android` |
| `sweep-test/sweep_drive_macos.zsh` | Runs every built Pn on macOS and appends a row per app to `matrix_coverage/results.csv2`. The macOS counterpart of `sweep_drive.zsh`, which is the Windows one |

## Android build size, and the disk it takes

An Android APK from this tree is **126 MB**; the same app on iOS is **8.6 MB**.
Measured 2026-09-05 on P43. That 20x is not this project: Swift's runtime ships
with iOS and the app links against it, while Android has none on the device, so
every APK carries its own.

| | P43 |
| --- | ---: |
| Android APK | 126 MB |
| iOS `.app` | 8.6 MB |

**86 MB came off, in three pieces**, and all three are the default:

| | APK |
|---|---:|
| where this started | 212 MB |
| `.swift_ast` stripped | 169 MB |
| SwiftSyntax not linked into Android | 154 MB |
| built release rather than debug | **126 MB** |

Release is the default because Android was the only platform here that was not;
`--debug-build` goes back. `SCUI_DEBUG` is a compilation condition rather than a
build configuration, so action-file replay and `--debug` diagnostics work in
both. `.swift_ast`
is the serialized Swift AST lldb reads to describe types, and nothing at runtime
touches it -- it was 45.0 MB of a 137.6 MB library, the second largest section
after `.text`. The bundler strips it from the packaged copy, so
`test.zsh --android` and `test_android.zsh` both produce the smaller APK with no
flag. Set `SCUI_KEEP_SWIFT_AST=1` for a build you mean to attach a debugger to.

That strip lives in a patch against `Vendor/swift-bundler`, so a bundler built
without it produces a correct APK that is merely 43 MB larger -- nothing fails.
`test_android.zsh` checks for the marker and says so; if you see that warning,
run `bash Scripts/build-android-bundler.sh`. **Use that script rather than
`swift build` by hand**: the Android path uses
`Vendor/swift-bundler/.build/out/Products/Debug/swift-bundler`, and
`swift build -c debug` writes somewhere it never looks.

**`.compile-work-android` reaches about 106 GB and most of it is cache.** Each
of the 45 apps gets its own gradle project holding its own copy of the runtime,
and gradle then keeps three more: `merged_native_libs`, `merged_jni_libs` and
`stripped_native_libs` are byte-identical to `src/main/jniLibs` for the shared
libraries, confirmed by checksum. Deleting every `*.project/build` directory
recovers around 25 GB and costs about a minute per app to regenerate:

```zsh
rm -rf testapp/.compile-work-android/TestApps/.build-bundler/bundler/apps/*/*.project/build
```

The full breakdown, including what the remaining 87 MB of the app's own library
is made of, is in `matrix_coverage/executable-size.md`.

## Android 的建置體積，以及它佔用的磁碟

本樹產出的 Android APK 為 **126 MB**；同一支 app 在 iOS 上是 **8.6 MB**。2026-09-05 於 P43 上量測。
那 20 倍不是這個專案造成的：Swift 的 runtime 隨 iOS 出貨、app 是連結它的，而 Android 的裝置上沒有，
因此每一支 APK 都得自帶一份。

**共移除了 86 MB，分三塊**，而三者都是預設行為：212 MB 起算，剝除 `.swift_ast` 後為 169 MB，
不再把 SwiftSyntax 連進 Android 後為 154 MB，改以 release 而非 debug 建置後為 **126 MB**。

release 之所以是預設，是因為 Android 曾是此處唯一不是的平台；`--debug-build` 可以走回去。
`SCUI_DEBUG` 是 compilation condition 而非 build configuration，因此動作檔重放與 `--debug` 診斷
在兩者之下都可用。 `.swift_ast` 是 lldb 用來描述型別的序列化
Swift AST，執行期完全不會碰它——它在一個 137.6 MB 的 library 中佔 45.0 MB，是繼 `.text` 之後第二大的
section。bundler 會從打包的副本中剝除它，因此 `test.zsh --android` 與 `test_android.zsh` 都不需要
任何旗標就會產出較小的 APK。若某個建置你打算以除錯器附加，請設定 `SCUI_KEEP_SWIFT_AST=1`。

該剝除位於一份針對 `Vendor/swift-bundler` 的 patch 之中，因此一個未套用它的 bundler 會產生完全正確、
只是多出 43 MB 的 APK——不會有任何東西失敗。`test_android.zsh` 會檢查該標記並提示；若你看到那則警告，
請執行 `bash Scripts/build-android-bundler.sh`。**請用那支腳本，不要自己下 `swift build`**：Android
路徑使用的是 `Vendor/swift-bundler/.build/out/Products/Debug/swift-bundler`，而 `swift build -c debug`
寫出的位置它從不查看。

**`.compile-work-android` 會達到約 106 GB，而其中大部分是快取。** 45 支 app 各自擁有一個 gradle
專案、各帶一份 runtime 副本，而 gradle 之後還會再保存三份：`merged_native_libs`、`merged_jni_libs`
與 `stripped_native_libs` 對於共享函式庫而言與 `src/main/jniLibs` 逐位元組相同，此事已以 checksum
確認。刪除每一個 `*.project/build` 目錄可回收約 25 GB，而重新產生的代價約為每支 app 一分鐘。

完整的拆解——包含 app 自身 library 剩下的那 87 MB 由什麼組成——位於
`matrix_coverage/executable-size.md`。

## Other scripts

| Script | For |
| --- | --- |
| `screenshot.zsh` | Captures the composited desktop, which is the only way to see D3D/DirectComposition content |
| `gpu-matrix.zsh`, `P6-test.zsh`, `test_P6.zsh` | P6's throughput matrix and its unattended runs |
| `rebase.zsh` | **Performs a rebase**, then checks that the hashes in `issue_commits.csv` still exist on the branch. `--check` is the read-only half |

`rebase.zsh` exists because a rebase silently orphans recorded hashes: they
keep resolving from the reflog, so nothing looks wrong until the next clone.

Reach for `--check` unless you mean to rewrite history. Without it the script
fetches and rebases before it checks anything, and the name reads like a
description of when to run it rather than of what it does — running it to "just
check" left this repository mid-rebase on 2026-09-07.

## Records

`P6_findings/` holds the measured throughput numbers behind the NV12 work, and
`comments/` holds write-ups drafted for upstream issues.

Two documents are deliberately untracked and local to a checkout:
`UI-test-plan overall-zhTW.md`, the Traditional Chinese half of the test plan, and
`UI-test-results.md`. Edits to the test steps belong in both language files even
though only `UI-test-plan overall-en.md` is committed.
