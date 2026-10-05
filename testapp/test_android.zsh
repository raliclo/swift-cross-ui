#!/usr/bin/env zsh
# Build, bundle, install, and launch one SwiftCrossUI test app on an Android
# emulator. The APK cache is deliberately separate from source and build trees.
#
#   zsh testapp/test_android.zsh P12
#   zsh testapp/test_android.zsh P12 --no-build
#   zsh testapp/test_android.zsh P12 --actionfile actions/android/P12-android-smoke.csv
#
# Usually reached as `zsh testapp/test.zsh P12 --android`, which is the same
# command and the same flags as every other platform.
# 通常經由 `zsh testapp/test.zsh P12 --android` 抵達，該指令與旗標和其他平台完全相同。
#
# 在 Android emulator 上建置、打包、安裝並啟動一支 SwiftCrossUI 測試 app。APK 快取與原始碼及
# build tree 分開；預設會重新建置 APK，`-noApk` 才重用既有 APK。

set -euo pipefail

script_path="${0:a}"
script_dir="${script_path:h}"
repo_root="${script_dir:h}"
output_dir="$script_dir/output"
apk_dir="$script_dir/.androidApk"
app=""
do_apk=1
action_file=""
device_name="${ANDROID_AVD_NAME:-}"
showtime_seconds="${ANDROID_SHOWTIME_SECONDS:-0}"

usage() {
    cat <<EOF_USAGE
Usage: ${script_path:t} <Pn> [--no-build] [--actionfile [path]] [--showtime seconds|--no-showtime] [--device name|serial]

Usually reached as: zsh testapp/test.zsh <Pn> --android
That uses the same flags as every other platform.

Default: compile and bundle a fresh Android APK in RELEASE, then install and
launch it. `--debug-build` uses debug instead.

Release is the default because Android was the only platform here that was not:
compile.zsh has used release everywhere else all along, and the debug default
cost 28 MB per APK -- 154 against 126, measured on P43 2026-09-05 -- for an
optimisation setting nothing was reading. `SCUI_DEBUG` is a separate thing and
still works: it is a compilation condition, not a build configuration, so
action-file replay and `--debug` diagnostics are available in both. Verified in
release on P43: the gradients measure what they did in debug and the replay
still reports `replayed P43-actions.csv`.
--no-build: reuse testapp/.androidApk/<Pn>.apk and skip compile/bundle.
            Aliases: -noApk, --no-apk.
--actionfile: replay an Android action file after launch; without a path, use
         testapp/actions/android/<Pn>-*.csv when exactly one file exists.
         Aliases: -replay, --replay.
--no-showtime: return as soon as the app is up.
--device: use an existing adb serial; otherwise boot the selected AVD.
EOF_USAGE
}

die() { print -u2 -r -- "[error] $1"; exit 1; }

[ "$#" -gt 0 ] || { usage >&2; exit 64; }
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 0
fi
app="${1:u}"
app_id="${app:l}"
shift
# A test target is any testapp/<name>.swift, as test_ios.zsh decides it. The old
# `P<->` pattern refused P15-DARK and P17-DOE, which exist and build, so they had
# no Android action file and could not get one.
# 測試目標是任何 testapp/<名稱>.swift，與 test_ios.zsh 的判定相同。舊的 `P<->` 樣式拒絕了
# P15-DARK 與 P17-DOE——它們存在也建得起來——因此它們沒有、也無法有 Android 動作檔。
[ -f "$script_dir/$app.swift" ] || die "Invalid test target: $app"

while [ "$#" -gt 0 ]; do
    case "$1" in
        # `--no-build` and `--actionfile` are the spellings test.zsh uses for
        # every other platform, and they are what test_common.zsh hands over.
        # The original `-noApk` and `-replay` stay as aliases so anything that
        # calls this script directly keeps working.
        # `--no-build` 與 `--actionfile` 是 test.zsh 在其他所有平台上使用的寫法，也是
        # test_common.zsh 交付過來的形式。原本的 `-noApk` 與 `-replay` 保留為別名，讓任何直接
        # 呼叫本腳本的既有做法仍然可用。
        -n|--no-build|-noApk|--no-apk) do_apk=0; shift ;;
        # Release is the default here, as it is for every other platform in
        # compile.zsh, and this is the way back to a debug build.
        # 此處預設為 release，與 compile.zsh 中其他所有平台相同；本旗標是回到 debug 建置的方式。
        --debug-build) BUILD_CONFIG=debug; shift ;;
        --actionfile|-replay|--replay)
            if [ "$#" -gt 1 ] && [[ "$2" != -* ]]; then
                action_file="$2"
                shift 2
            else
                candidates=("$script_dir/actions/android/$app"-*.csv(N))
                [ "${#candidates}" -eq 1 ] || die "Provide one Android action file for $app"
                action_file="${candidates[1]}"
                shift
            fi
            ;;
        --showtime)
            [ "$#" -gt 1 ] || die "--showtime requires seconds"
            showtime_seconds="$2"
            shift 2
            ;;
        --no-showtime) showtime_seconds=0; shift ;;
        --device)
            [ "$#" -gt 1 ] || die "--device requires an AVD name or adb serial"
            device_name="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

[ "$(uname -s)" = Darwin ] || die "test_android.zsh requires macOS"

android_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${repo_root:h}/.android-sdk}}"
# macOS 27 can block the legacy IOKit USB backend while adb starts its server.
# libusb keeps emulator-only testing responsive and can still be overridden by
# callers that need the legacy backend.
# macOS 27 可能讓 adb 啟動 server 時卡在舊版 IOKit USB backend。libusb 可讓僅使用
# emulator 的測試正常啟動；若有需要，呼叫端仍可覆寫此設定。
export ADB_LIBUSB="${ADB_LIBUSB:-1}"
# 31, matching compile.zsh and androidContainer/Bundler.android.toml.
#
# This said 28 while the other two said 31, which is worse than all three
# saying 28: `compile.zsh -android` would build for API 31 and then this script
# would rebuild the same app for 28 in its own tree, so the APK under test was
# not the thing that had just been checked. The three are one decision and have
# to move together.
#
# 31，與 compile.zsh 及 androidContainer/Bundler.android.toml 一致。
#
# 此處原本寫 28，而另外兩處寫 31——那比三處都寫 28 更糟：`compile.zsh -android` 會以 API 31 建置，
# 而本腳本接著會在自己的建置樹中以 28 重建同一支 app，於是受測的 APK 並不是剛才檢查過的那一個。
# 這三處是同一個決定，必須一起移動。
android_triple="${ANDROID_TRIPLE:-aarch64-unknown-linux-android31}"
# NDK r30, the one the Swift 6.4.0 Android SDK requires; testapp/install_tools_android.zsh
# installs it and is where the version is decided (2026-10-05; was 27.0.12077973).
# NDK r30，Swift 6.4.0 的 Android SDK 需要它；由 testapp/install_tools_android.zsh 安裝，版本以那裡為準
# （2026-10-05；原為 27.0.12077973）。
android_ndk_version="${ANDROID_NDK_VERSION:-30.0.16248370}"
android_ndk_home="${ANDROID_NDK_HOME:-$android_root/ndk/$android_ndk_version}"
# A toolchain matching the Android SDK, and explicitly not Xcode's.
#
# `swift` on a Mac is Xcode's -- 6.4 as of 2026-09-02 -- while the newest
# Android SDK swift.org publishes is 6.3.3. Building with the host default
# fails on every module that imports Foundation:
#
#     error: module compiled with Swift 6.3.3 cannot be imported by the
#     Swift 6.4 compiler
#
# The default was a dated snapshot name, `swift-6.3-DEVELOPMENT-SNAPSHOT-
# 2026-06-07-a`. That toolchain still exists here, but the name rots: the
# matching Android SDK was replaced with 6.3.3-RELEASE on 2026-09-02 and a
# hard-coded snapshot date has no way to follow. `swift-latest` is the same
# 6.3.3-dev compiler today and at least tracks whatever was installed last.
#
# If this ever fails with the version error above, the fix is to install a
# toolchain matching the SDK -- not to raise the SDK, which cannot be raised
# past what swift.org has published. See testapp/build_time_android.md.
#
# 需要與 Android SDK 相符的 toolchain，且明確不是 Xcode 的那個。
#
# Mac 上的 `swift` 是 Xcode 的——2026-09-02 為 6.4——而 swift.org 所發布最新的 Android SDK 是
# 6.3.3。使用主機預設值建置，會使每一個 import Foundation 的 module 都以上方英文所示的錯誤失敗。
#
# 原本的預設值是一個帶日期的 snapshot 名稱 `swift-6.3-DEVELOPMENT-SNAPSHOT-2026-06-07-a`。
# 該 toolchain 目前仍存在，但這個名稱會腐爛：對應的 Android SDK 已於 2026-09-02 換成
# 6.3.3-RELEASE，而寫死的 snapshot 日期無從跟上。`swift-latest` 今日即是同一個 6.3.3-dev 編譯器，
# 且至少會跟隨「最後安裝的是哪一個」。
#
# 若日後出現上述版本錯誤，正確的修法是安裝一個與 SDK 相符的 toolchain——而不是調高 SDK，
# 因為它無法高過 swift.org 已發布的版本。詳見 testapp/build_time_android.md。
swift_toolchain="${SWIFT_ANDROID_TOOLCHAIN:-swift-latest}"
swift_bin="${SWIFT_BIN:-$HOME/Library/Developer/Toolchains/${swift_toolchain}.xctoolchain/usr/bin/swift}"
# The macOS SDK the Android toolchain compiles HOST code against -- the package
# manifest and build plugins. Xcode 27's SDK ships Foundation interfaces whose
# module flags include `-target-arch-variant`, which the snapshot toolchain does
# not know, so every manifest compile failed with "unknown argument:
# '-target-arch-variant'" and "Invalid manifest". It had worked until 2026-10-01
# only because a module cache still held Foundation built from those interfaces
# earlier; once the cache was cleared nothing could rebuild it. The first SDK
# whose Foundation interface the toolchain can read is used; ANDROID_HOST_SDKROOT
# overrides the choice.
# Android toolchain 編譯「主機端」程式碼（package manifest 與 build plugin）所用的 macOS SDK。
# Xcode 27 的 SDK 附帶的 Foundation 介面，其 module flags 含 `-target-arch-variant`，快照版
# toolchain 不認得，於是每一次 manifest 編譯都以 "unknown argument: '-target-arch-variant'" 與
# "Invalid manifest" 失敗。2026-10-01 之前能成功，只是因為 module cache 裡還留著先前由那些介面
# 建出的 Foundation；cache 一被清掉就再也建不回來。這裡選第一個 toolchain 讀得懂其 Foundation
# 介面的 SDK；ANDROID_HOST_SDKROOT 可覆寫。
android_host_sdk="${ANDROID_HOST_SDKROOT:-}"
if [ -z "$android_host_sdk" ]; then
    for candidate in "$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)" \
        /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk(N/On); do
        interface="$candidate/System/Library/Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface"
        [ -f "$interface" ] || continue
        if ! grep -q -- '-target-arch-variant' "$interface"; then
            android_host_sdk="$candidate"
            break
        fi
    done
fi
[ -n "$android_host_sdk" ] || die "No macOS SDK the Android toolchain can read (every Foundation interface uses -target-arch-variant); set ANDROID_HOST_SDKROOT"
export SDKROOT="$android_host_sdk"
package_dir="$script_dir/.compile-work-android/TestApps"
apk_path="$apk_dir/$app.apk"
# Lowercased. The APK's application id is lowercase, so `adb shell am start`
# against "dev.swiftcrossui.testapp.P12" finds no such package while the install
# reports success -- the failure looks like the app refusing to launch.
# 轉為小寫。APK 的 application id 是小寫的，因此以 "dev.swiftcrossui.testapp.P12" 執行
# `adb shell am start` 會找不到該套件，而安裝本身卻回報成功——該失敗看起來會像是 app 拒絕啟動。
# Without the `-`, matching the identifier compile.zsh writes for Android.
# 去掉 `-`，與 compile.zsh 為 Android 寫入的 identifier 一致。
package_id="dev.swiftcrossui.testapp.${app_id//-/}"
adb="$android_root/platform-tools/adb"
emulator="$android_root/emulator/emulator"

# One Android run at a time: the emulator, .compile-work-android and the one
# Gradle project are shared, so a second run waits here (test_support/platform_lock.zsh).
# 一次只跑一個 Android:emulator、.compile-work-android 與那一個 Gradle 專案是共用的，所以第二次執行在此等待。
source "$script_dir/test_support/platform_lock.zsh" android
zsh "$script_dir/install_tools_android.zsh" --check >/dev/null
[ -x "$adb" ] || die "Missing adb: $adb"

if [ "$do_apk" -eq 1 ]; then
    [ -x "$swift_bin" ] || die "Missing Swift Android toolchain: $swift_bin; run Scripts/build-tool-install-android-on-Mac.sh"

    print "==> Building $app for Android"
    ANDROID_HOME="$android_root" ANDROID_SDK_ROOT="$android_root" \
        ANDROID_NDK_HOME="$android_ndk_home" ANDROID_NDK_ROOT="$android_ndk_home" \
        ANDROID_TRIPLE="$android_triple" SWIFT_BIN="$swift_bin" \
        SCUI_ANDROID=1 zsh "$script_dir/compile.zsh" -android "$app"

    print "==> Packaging $app APK"
    # Packaged from compile.zsh's own build, without Swift Bundler.
    #
    # The bundler ran a second `swift build` of the same app in .build-bundler,
    # against a symlinked SDK silo that made SwiftPM treat the two trees as
    # different, and regenerated a Gradle project per app on every bundle.
    # package_android.zsh relinks the product compile.zsh just built as
    # lib<app>.so and builds the one Gradle project in androidContainer; its
    # header lists the steps, which are the bundler's.
    #
    # 由 compile.zsh 自己的建置打包，不經 Swift Bundler。bundler 會在 .build-bundler 把同一支 app 再
    # `swift build` 一次(對著一個符號連結的 SDK silo,讓 SwiftPM 把兩棵樹視為不同),並在每次打包時為每支
    # app 重新產生 Gradle 專案。package_android.zsh 把 compile.zsh 剛建好的 product 重新連結成
    # lib<app>.so,再建置 androidContainer 裡那一個 Gradle 專案；步驟列在它的檔頭，與 bundler 相同。
    ANDROID_HOME="$android_root" ANDROID_SDK_ROOT="$android_root" \
        ANDROID_NDK_HOME="$android_ndk_home" ANDROID_NDK_ROOT="$android_ndk_home" \
        ANDROID_TRIPLE="$android_triple" BUILD_CONFIG="${BUILD_CONFIG:-release}" \
        zsh "$script_dir/package_android.zsh" "$app" "$apk_path"
else
    [ -f "$apk_path" ] || die "Missing cached APK: $apk_path; omit -noApk to build it"
    print "==> Reusing $apk_path"
fi

running_serial=""
if [ -z "$device_name" ]; then
    running_serial="$("$adb" devices | awk '/^emulator-[0-9]+[[:space:]]+device$/{print $1; exit}')"
    device_name="$($emulator -list-avds 2>/dev/null | head -n 1 || true)"
    [ -n "$device_name" ] || die "No Android AVD exists; create one before delivery"
fi

# Boot an AVD and wait until adb lists it; sets \$serial.
# 啟動一個 AVD,等到 adb 列出它為止；設定 \$serial。
boot_emulator() {
    print "==> Booting Android AVD: $1"
    # `-no-metrics`, or the emulator can block before it ever boots.
    #
    # Measured 2026-09-05: `emulator -avd ... -no-snapshot -no-boot-anim` logged
    # "Showing crashdialog to get consent." and then sat there. `adb devices`
    # stayed empty, the sixty-second wait below expired, and the failure read
    # "Android emulator did not appear in adb devices" -- which sounds like a
    # boot that was too slow rather than a modal dialog waiting for a click that
    # a headless run will never give it.
    #
    # 加上 `-no-metrics`，否則模擬器可能在啟動之前就卡住。
    #
    # 2026-09-05 實測：`emulator -avd ... -no-snapshot -no-boot-anim` 記錄了
    # 「Showing crashdialog to get consent.」然後就停在那裡。`adb devices` 一直是空的，下方的六十秒
    # 等待逾時，而失敗訊息是「Android emulator did not appear in adb devices」——那聽起來像是啟動太慢，
    # 而不是「一個模態對話框正在等一次點擊，而無人值守的執行永遠不會給它」。
    #
    # `-gpu host`: draw with this Mac's GPU. Left to `auto`, the emulator chose
    # for itself, and under memory pressure it chose software GL -- see the
    # renderer check after boot, which is what actually enforces this.
    # `-gpu host`:用這台 Mac 的 GPU 繪圖。留給 `auto` 時由模擬器自己挑，而記憶體吃緊時它挑過軟體 GL——
    # 真正把關的是開機後的 renderer 檢查。
    "$emulator" -avd "$1" -no-snapshot -no-boot-anim -no-metrics -gpu host \
        >/dev/null 2>&1 &
    serial=""
    for _ in {1..60}; do
        serial="$($adb devices | awk '/^emulator-[0-9]+[[:space:]]+/{print $1; exit}')"
        [ -n "$serial" ] && break
        sleep 1
    done
    [ -n "$serial" ] || die "Android emulator did not appear in adb devices"
}

wait_booted() {
    ANDROID_SERIAL="$serial" "$adb" wait-for-device
    ANDROID_SERIAL="$serial" "$adb" shell getprop sys.boot_completed | grep -q 1 || {
        for _ in {1..60}; do
            sleep 1
            ANDROID_SERIAL="$serial" "$adb" shell getprop sys.boot_completed 2>/dev/null | grep -q 1 && break
        done
    }
    ANDROID_SERIAL="$serial" "$adb" shell getprop sys.boot_completed | grep -q 1 || die "Android device did not finish booting"
}

# An emulator already running is used rather than a second one started on the
# same AVD. The second instance used to fail on the AVD lock and go away, but
# when the running one is restarted on the host GPU below, a stray second
# instance can win the race for the AVD with whatever flags it was given.
# 已在執行的模擬器直接沿用，不在同一個 AVD 上再啟動第二個。第二個實例原本會因 AVD 鎖而失敗並消失，但下方以主機
# GPU 重開執行中的那一台時，多出來的實例可能搶先拿到該 AVD,帶著它自己的旗標開機。
if [[ "$device_name" == emulator-* ]]; then
    serial="$device_name"
elif [ -n "$running_serial" ]; then
    serial="$running_serial"
    print "==> Using running emulator: $serial"
else
    # The AVD's data can live on another volume behind a symlink -- on this
    # machine ~/.android/avd/<name>.avd points into /Volumes/Windows since
    # 2026-10-02, because its qcow2 overlay grows with every APK install
    # (10 GB) and filled the system disk mid-sweep. If that volume is not
    # mounted, say so here rather than let the emulator fail to boot.
    # AVD 的資料可能透過 symlink 放在別的磁碟上——本機自 2026-10-02 起
    # ~/.android/avd/<name>.avd 指向 /Volumes/Windows,因為它的 qcow2 每裝一次 APK 就變大
    # (10 GB),曾在 sweep 中途塞滿系統碟。那顆磁碟沒掛上時，在這裡講清楚，而不是讓模擬器開不起來。
    avd_dir="${ANDROID_AVD_HOME:-$HOME/.android/avd}/$device_name.avd"
    if [ -L "$avd_dir" ] && [ ! -d "$avd_dir" ]; then
        die "AVD $device_name points to ${avd_dir:A}, which is not there -- is its volume mounted?"
    fi
    boot_emulator "$device_name"
fi

print "==> Waiting for Android device"
wait_booted

# Hardware rendering, by default and checked rather than assumed. `-gpu host`
# above covers only an emulator this script boots; one already running keeps
# whatever it was started with, and an AVD left on `auto` has fallen back to
# software GL under memory pressure. SurfaceFlinger names the renderer it
# actually got: on this Mac the host GPU reads "OpenGL ES Translator (Apple M4)
# ... Metal", software reads SwiftShader. Timings and animation captures from a
# software renderer are not comparable with any other run, so an emulator found
# on one is restarted on the host GPU -- no flag needed -- and a run that still
# cannot get it stops here.
# 預設使用硬體繪圖，並且檢查而非假設。上面的 `-gpu host` 只管本腳本開機的模擬器；已在執行中的那一台保留它
# 啟動時的設定，而停在 `auto` 的 AVD 在記憶體吃緊時退回過軟體 GL。SurfaceFlinger 會說出它實際拿到的
# renderer:在這台 Mac 上，主機 GPU 是「OpenGL ES Translator (Apple M4) ... Metal」,軟體則是 SwiftShader。
# 軟體 renderer 的計時與動畫截圖無法與其他任何一次比較，因此發現模擬器跑在軟體上時，就以主機 GPU 重開——
# 不需要任何旗標——重開後仍拿不到的話，就在這裡停下。
renderer() {
    ANDROID_SERIAL="$serial" "$adb" shell dumpsys SurfaceFlinger 2>/dev/null | grep -m1 '^GLES:' || true
}
is_software() {
    [[ -z "$1" || "$1" == *[Ss]wift[Ss]hader* || "$1" == *llvmpipe* || "$1" == *lavapipe* ]]
}
if [[ "$serial" == emulator-* ]]; then
    gles="$(renderer)"
    if is_software "$gles"; then
        running_avd="$(ANDROID_SERIAL="$serial" "$adb" emu avd name 2>/dev/null | head -n 1 | tr -d '\r')"
        print "==> $serial renders in software (${gles:-no GLES line}); restarting ${running_avd:-it} on the host GPU"
        [ -n "$running_avd" ] || die "cannot tell which AVD $serial is, so cannot restart it on the host GPU"
        ANDROID_SERIAL="$serial" "$adb" emu kill >/dev/null 2>&1 || true
        for _ in {1..60}; do
            "$adb" devices | grep -q "^${serial}[[:space:]]" || break
            sleep 1
        done
        boot_emulator "$running_avd"
        wait_booted
        gles="$(renderer)"
    fi
    print "==> Renderer: ${gles:-unknown}"
    if is_software "$gles"; then
        die "the emulator is not rendering on the host GPU (${gles:-no GLES line})"
    fi
fi



# Screenshots, into the same place and with the same naming every other platform
# uses -- testapp/output/screenshots/<label>-<timestamp>.png -- so a run's
# evidence lands together whichever target produced it.
#
# Not through screenshot.zsh. That captures a display, and a display is the
# wrong thing here: what matters is the device's own framebuffer, which is a
# different image from "the emulator window as composited on this Mac" and is
# available without Screen Recording permission.
#
# The file is checked for content, not just the exit code. `adb exec-out` writes
# through a shell redirect, so the file exists whether or not a single byte
# arrived -- an empty PNG would otherwise be reported as a successful capture.
#
# Failure is reported and counted, never swallowed, and never aborts the run: a
# screenshot is evidence, not the assertion.
#
# 截圖輸出至與其他所有平台相同的位置與命名方式——testapp/output/screenshots/<label>-<時間戳>.png
# ——如此一來，無論由哪個 target 產生，一次執行的證據都會落在一起。
#
# 不經由 screenshot.zsh。該腳本擷取的是「顯示器」，而在此處那是錯的對象：真正重要的是裝置自身的
# framebuffer，它與「emulator 視窗在這台 Mac 上合成後的樣子」是不同的影像，且不需要螢幕錄製權限。
#
# 此處檢查的是檔案是否有內容，而不僅是結束碼。`adb exec-out` 是透過 shell 重導向寫出的，因此無論
# 是否真的收到任何位元組，該檔都會存在——否則一個空的 PNG 會被回報為擷取成功。
#
# 失敗會被回報並計數，不會被吞掉，也絕不中止執行：截圖是證據，而非斷言。
screenshot_failures=0
capture() {
    local label="$1"
    local dir="$script_dir/output/screenshots"
    mkdir -p "$dir"
    # Not `path`. It is the zsh array tied to $PATH, so `local path=...` empties
    # the command search path for the rest of the function: xcrun is not found,
    # the capture "fails", and then `rm` is not found either -- the observed
    # symptom was "capture:12: command not found: rm". Same family as `status`,
    # which bit two commits ago, and this file's own notes name `path` first.
    # 不用 `path`。它是 zsh 中與 $PATH 綁定的陣列，因此 `local path=...` 會清空該函式其餘部分的
    # 命令搜尋路徑：找不到 xcrun，擷取遂「失敗」，接著連 `rm` 也找不到——實際觀察到的症狀是
    # 「capture:12: command not found: rm」。與兩個 commit 前咬過人的 `status` 同一族，而本檔自身
    # 的註解正是把 `path` 列在第一個。
    local shot="$dir/${label}-$(date +%Y%m%d-%H%M%S).png"

    if ANDROID_SERIAL="$serial" "$adb" exec-out screencap -p > "$shot" 2>/dev/null \
        && [ -s "$shot" ]; then
        print "==> Screenshot: ${shot:t}"
        return 0
    fi

    rm -f "$shot"
    screenshot_failures=$(( screenshot_failures + 1 ))
    print -u2 -r -- "!! no screenshot from $serial"
    return 0
}

print "==> Installing $apk_path"
ANDROID_SERIAL="$serial" "$adb" install -r "$apk_path" >/dev/null
ANDROID_SERIAL="$serial" "$adb" shell am force-stop "$package_id" || true
# Stylus handwriting off. With it on, Gboard answers a synthesised tap in a text
# field with a full-screen "Try out your stylus" sheet, and seven captures of
# the 2026-10-02 sweep (P2 P9 P15 P21 P31 P32 P36) photographed that sheet.
# 關閉手寫筆輸入。開啟時，對文字欄的合成點擊會讓 Gboard 跳出全螢幕的「Try out your stylus」,
# 2026-10-02 的 sweep 有七張擷圖(P2 P9 P15 P21 P31 P32 P36)拍到的是那個畫面。
ANDROID_SERIAL="$serial" "$adb" shell settings put secure stylus_handwriting_enabled 0 || true
# Start the declared launcher activity directly. `monkey` can return a non-zero
# status for emulator input limitations even when it does not provide a useful
# readiness check for action-file replay.
# 直接啟動 manifest 宣告的 launcher activity。`monkey` 可能因 emulator 輸入限制回傳
# 非零狀態，無法作為 action file replay 的可靠 readiness check。
# The action file goes to the device and its path goes in an intent extra.
#
# An Android app has no argv, so `AndroidBackend.entrypoint` used to call
# `main(0, nil)` and nothing downstream could see a flag. `--actionfile` was
# parsed by this script and then dropped -- an option that was accepted and did
# nothing. `AndroidBackend+Arguments.swift` now reads the `scui_args` extra and
# builds argv from it before `main` runs, so `--debug` and `-actionfile` mean
# here what they mean everywhere else.
#
# `/data/local/tmp` rather than the app's own directory: adb can write there
# without root and the app can read it, and no path in it contains a space --
# which matters, because the extra is split on spaces.
#
# 動作檔送到裝置上，而它的路徑放進 intent 的 extra。
#
# Android app 沒有 argv，因此 `AndroidBackend.entrypoint` 原本呼叫 `main(0, nil)`，下游看不到任何
# 旗標。`--actionfile` 由本腳本解析之後就被丟掉——一個被接受卻什麼都不做的選項。現在
# `AndroidBackend+Arguments.swift` 會讀取 `scui_args` 這個 extra，並在 `main` 執行前據以建構 argv，
# 使 `--debug` 與 `-actionfile` 在此處的意義與在其他每個平台相同。
#
# 使用 `/data/local/tmp` 而非 app 自己的目錄：adb 不需 root 即可寫入該處，而 app 讀得到；且其中
# 沒有任何路徑含有空白——這一點很重要，因為該 extra 是以空白切分的。
app_args=()
if [ -n "$action_file" ]; then
    [ -f "$action_file" ] || die "No such action file: $action_file"
    device_action_file="/data/local/tmp/$app-actions.csv"
    print "==> Pushing $action_file -> $device_action_file"
    ANDROID_SERIAL="$serial" "$adb" push "$action_file" "$device_action_file" >/dev/null \
        || die "Could not push the action file to the device"
    app_args=(--debug -actionfile "$device_action_file")
fi

# The arguments a file needs, read from the file, and TEST_APP_ARGS -- the two
# ways macOS and iOS already get them (sweep_apple.zsh, test_common.zsh). Android
# took neither until 2026-09-30, so P38's fixed `-url data:...` page and P34's
# `-rows 500` could not reach the app here, and a file carrying them replayed
# against the defaults. `scui_args` is split on whitespace, which is why the
# P38 page is percent-encoded rather than quoted.
#
# 檔案所需的參數從檔案本身讀出,另加 TEST_APP_ARGS——正是 macOS 與 iOS 已經取得它們的兩條路
# (sweep_apple.zsh、test_common.zsh)。2026-09-30 之前 Android 兩者都不讀,所以 P38 固定的
# `-url data:...` 頁面與 P34 的 `-rows 500` 到不了這裡的 app,帶著它們的檔案是對著預設值重放的。
# `scui_args` 以空白切分,這正是 P38 的頁面採百分比編碼而不是加引號的原因。
#
# `if`, not `[ ... ] && ...`: under `set -e` a false test as the last command of
# the enclosing `if` made the whole script exit 1 with no message, right after
# "Pushing ...", for every file WITHOUT a launch-args line (2026-09-30, P75).
# 用 `if` 而不是 `[ ... ] && ...`：在 `set -e` 之下，一個為假的判斷若是外層 `if` 的最後一個指令，
# 會讓整支腳本在「Pushing ...」之後不留訊息地以 1 結束——凡是**沒有** launch-args 的檔案都如此
# (2026-09-30,P75)。
launch_args=()
if [ -n "$action_file" ]; then
    launch_line="$(grep -m1 -E '^# *launch-args:' "$action_file" | sed -E 's/^# *launch-args: *//' || true)"
    if [ -n "$launch_line" ]; then
        launch_args=(${=launch_line})
    fi
fi
if [ -n "${TEST_APP_ARGS:-}" ]; then
    launch_args=(${=TEST_APP_ARGS} $launch_args)
fi
# SCUI_UPDATE_STATS=1: the app reports its update timings (UpdateTimings.swift);
# the environment does not reach an Android app, so it goes as an argument.
# SCUI_UPDATE_STATS=1:app 回報它的更新耗時(UpdateTimings.swift);環境變數到不了 Android app,所以用參數傳。
if [ "${SCUI_UPDATE_STATS:-0}" = 1 ]; then
    launch_args+=(--update-stats)
fi
if [ "${#launch_args}" -gt 0 ]; then
    print "==> App arguments: ${launch_args[*]}"
    app_args+=($launch_args)
fi

# The device's clock at launch, so the crash check below reads this run's log only.
# 啟動時裝置的時鐘，讓下方的崩潰檢查只讀這一次執行的 log。
launch_log_time="$(ANDROID_SERIAL="$serial" "$adb" shell "date '+%m-%d %H:%M:%S.000'" | tr -d '\r')"
if [ "${#app_args}" -gt 0 ]; then
    # Quoted for the shell ON THE DEVICE, which is a second round of word
    # splitting `adb shell` does not protect against: it joins its arguments
    # into one command line and the device's shell re-parses it. Without the
    # inner quotes, `--es scui_args "--debug -actionfile /data/local/tmp/x.csv"`
    # arrives as three words, and `am` reads `-actionfile` as `-a ctionfile` --
    # it sets the intent's ACTION to "ctionfile" and takes the path as the
    # component:
    #
    #   Starting: Intent { act=ctionfile cmp=/data/local/tmp/P12-actions.csv }
    #   Error: Activity class {/data/local/tmp/P12-actions.csv} does not exist.
    #
    # Measured on the emulator. The app never launched, and the script stopped
    # with no line saying why.
    #
    # 這裡的引號是給**裝置上的** shell 的——那是 `adb shell` 並不會替你擋掉的第二輪斷詞：它把自己的
    # 引數併成一行命令，再由裝置端的 shell 重新解析。少了內層引號，
    # `--es scui_args "--debug -actionfile /data/local/tmp/x.csv"` 抵達時會是三個詞，而 `am` 會把
    # `-actionfile` 讀成 `-a ctionfile`——它把 intent 的 ACTION 設為「ctionfile」，並把該路徑當成
    # component（輸出見上方英文）。此事於 emulator 上實測：app 根本沒有啟動，而腳本停下時沒有任何
    # 一行說明原因。
    ANDROID_SERIAL="$serial" "$adb" shell am start -W -n "$package_id/dev.swiftcrossui.testapp.MainActivity" \
        --es scui_args "'${app_args[*]}'" >/dev/null
else
    ANDROID_SERIAL="$serial" "$adb" shell am start -W -n "$package_id/dev.swiftcrossui.testapp.MainActivity" >/dev/null
fi

print "==> Launched $package_id on $serial"

# Five seconds before the first capture, not one.
#
# One second is the number the other platforms use, and on Android it
# photographs the wrong thing. A cold start here has to bring up the JVM, load
# libswiftCore, Foundation and ICU, run `AndroidBackend_entrypoint` through JNI
# and then lay out; the apps log RENDER COMPLETE at around six seconds. A
# one-second capture can therefore photograph the launch splash instead of the
# app: `p13-android-1s-20260905-113746.png` is 97.6% white with a green Android
# robot and nothing else. One of 174 captures on 2026-09-05, so it is rare on a
# warm emulator and not rare enough to leave to chance.
#
# It also broke a check built on top of it. Comparing the `-1s-` and `-final-`
# captures was meant to show what the action file changed, and under
# `--no-showtime` the two are taken back to back: forty of forty-five apps
# differed by exactly zero pixels, same timestamp, same md5. One photograph
# compared with itself. The gap has to be real for the pair to mean anything.
#
# The name stays `-1s-`. It is in every existing filename and in the comparisons
# written against them, and renaming it would silently split the history in two.
# 是 5 秒,不是 1 秒。
#
# 1 秒是其他平台使用的數字,而在 Android 上它拍到的是錯的東西。此處的冷啟動必須先起 JVM、載入
# libswiftCore、Foundation 與 ICU、透過 JNI 執行 `AndroidBackend_entrypoint`,然後才排版;這些 app
# 大約在六秒左右記錄 RENDER COMPLETE。因此 1 秒的擷取有可能拍到啟動畫面而不是 app:
# `p13-android-1s-20260905-113746.png` 有 97.6% 是白色,畫面上只有一個綠色的 Android 機器人。
# 2026-09-05 的 174 張擷取中出現一次——在熱的模擬器上算罕見,但沒有罕見到可以交給運氣。
#
# 它同時也弄壞了一個建立在其上的檢查。比對 `-1s-` 與 `-final-` 兩張擷取,原意是顯示動作檔改變了
# 什麼;而在 `--no-showtime` 之下,這兩張是連續拍下的:四十五支中有四十支的差異恰好是零像素、
# 時間戳相同、md5 相同。那是拿一張照片跟它自己比。這一對要有意義,中間的間隔就必須是真的。
#
# 名稱維持 `-1s-`。它出現在每一個既有檔名、以及依據那些檔名所寫的比對之中,重新命名會靜默地把
# 歷史一分為二。
first_capture_seconds="${ANDROID_FIRST_CAPTURE_SECONDS:-5}"
sleep "$first_capture_seconds"
capture "${app_id}-android-1s"

if [ "$showtime_seconds" -gt 0 ]; then
    sleep "$showtime_seconds"
fi

# With an action file, the final capture waits for the replay to finish. A
# fixed delay photographed P72-stop-and-check half way through on 2026-10-02:
# its log printed EXPORTED and SNAPSHOT, and the capture, taken first, read
# "glTF: 0 bytes". The replay prints `-actionfile: replayed` (or `failed:`)
# when it is done; up to 60 s is allowed, then the capture is taken anyway and
# says so.
# 有動作檔時，最後一張擷圖要等重放結束。2026-10-02 以固定延遲拍下的 P72-stop-and-check 停在半途:
# log 印出了 EXPORTED 與 SNAPSHOT,而先拍下的擷圖讀到「glTF: 0 bytes」。重放結束時會印出
# `-actionfile: replayed`(或 `failed:`);最多等 60 秒，逾時仍會拍並說明。
if [ -n "$action_file" ]; then
    replay_waited=0
    until ANDROID_SERIAL="$serial" "$adb" logcat -d -T "$launch_log_time" 2>/dev/null \
        | grep -qE -- "-actionfile: (replayed|failed)"; do
        if [ "$replay_waited" -ge 60 ]; then
            print -u2 -r -- "!! the replay had not finished after 60 s; capturing anyway"
            break
        fi
        sleep 1
        replay_waited=$((replay_waited + 1))
    done
    # One more second for the last action's redraw to reach the screen.
    # 再一秒，讓最後一個動作的重繪抵達畫面。
    sleep 1
fi

capture "${app_id}-android-final"

# Did the app die? `am start -W` returns once the activity is created, so an app
# that throws in onCreate a moment later still "launched", and the captures then
# photograph whatever was in front before it. P15-DARK did exactly that on
# 2026-10-01 -- UnsatisfiedLinkError in setup(), exit 0, and a capture of P73
# filed as p15-dark-android-final. Reading the front activity would misjudge the
# files that leave the app on purpose (P38's browser, P75's file manager and
# close), so this reads the crash records instead: a Java FATAL EXCEPTION or a
# native crash naming this package since launch.
# app 死了嗎?`am start -W` 在 activity 建立後就返回，所以一個稍後在 onCreate 中拋出例外的 app
# 仍算「已啟動」,而擷圖拍到的是它之前在前景的東西。2026-10-01 的 P15-DARK 正是如此——setup() 拋出
# UnsatisfiedLinkError、以 0 結束、一張 P73 的擷圖被存成 p15-dark-android-final。改讀前景 activity
# 會誤判那些刻意離開 app 的檔案(P38 的瀏覽器、P75 的檔案管理員與關窗),所以這裡讀的是崩潰紀錄:
# 自啟動以來，指名此 package 的 Java FATAL EXCEPTION 或原生崩潰。
crash_lines="$(ANDROID_SERIAL="$serial" "$adb" logcat -d -T "$launch_log_time" 2>/dev/null \
    | grep -E "Process: $package_id, PID|>>> $package_id <<<" || true)"
if [ -n "$crash_lines" ]; then
    print -u2 -r -- "!! $package_id crashed after launch; the captures above are not this app:"
    ANDROID_SERIAL="$serial" "$adb" logcat -d -T "$launch_log_time" 2>/dev/null \
        | grep -E "FATAL EXCEPTION|Process: $package_id|UnsatisfiedLinkError|>>> $package_id <<<|signal [0-9]+" \
        | head -8 >&2 || true
    exit 1
fi
# The app's own update timings, when asked for: the last cumulative line since
# launch. It is printed once updates have been quiet for 1.5 s, so wait a little
# for it after the final capture.
# 要求時，取 app 自己的更新耗時：自啟動以來最後一行累計值。它在更新安靜 1.5 秒後才印，所以在最後一張擷圖
# 之後稍等一下。
if [ "${SCUI_UPDATE_STATS:-0}" = 1 ]; then
    update_stats=""
    for _ in 1 2 3 4; do
        update_stats="$(ANDROID_SERIAL="$serial" "$adb" logcat -d -T "$launch_log_time" 2>/dev/null \
            | grep -o "update-stats: .*" | tail -1 || true)"
        [ -n "$update_stats" ] && break
        sleep 1
    done
    print -r -- "==> ${update_stats:-update-stats: none reported}"
else
    # Said, not left out: with no line at all, a run that never measured reads like an
    # app that never updated (2026-10-05, seven runs thrown away).
    # 明講，而不是不印：一行都沒有時，「根本沒在量」看起來就像「app 沒有更新」(2026-10-05,作廢七次)。
    print -r -- "==> update-stats: off (set SCUI_UPDATE_STATS=1)"
fi
if [ "$screenshot_failures" -gt 0 ]; then
    print -u2 -r -- "!! $screenshot_failures screenshot(s) could not be taken"
fi
