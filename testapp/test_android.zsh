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

Default: compile and bundle a fresh Android APK, then install and launch it.
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
[[ "$app" == P<-> ]] || die "Invalid test target: $app"

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
if [ -n "${SWIFT_BUNDLER:-}" ]; then
    bundler_bin="$SWIFT_BUNDLER"
elif [ -x "$repo_root/Vendor/swift-bundler/.build/out/Products/Debug/swift-bundler" ]; then
    # Use the build-tree executable because ErrorKit's resource bundle is kept
    # beside it. The copied root binary may fail before parsing arguments when
    # that resource bundle is absent.
    # 使用 build tree 的執行檔，因為 ErrorKit resource bundle 會與它放在一起；若缺少該
    # resource bundle，複製到 repository root 的 binary 可能在解析引數前就失敗。
    bundler_bin="$repo_root/Vendor/swift-bundler/.build/out/Products/Debug/swift-bundler"
else
    bundler_bin="$repo_root/swift-bundler"
fi
android_triple="${ANDROID_TRIPLE:-aarch64-unknown-linux-android28}"
android_ndk_version="${ANDROID_NDK_VERSION:-27.0.12077973}"
android_ndk_home="${ANDROID_NDK_HOME:-$android_root/ndk/$android_ndk_version}"
swift_snapshot="${SWIFT_ANDROID_SNAPSHOT:-swift-6.3-DEVELOPMENT-SNAPSHOT-2026-06-07-a}"
swift_bin="${SWIFT_BIN:-$HOME/Library/Developer/Toolchains/${swift_snapshot}.xctoolchain/usr/bin/swift}"
package_dir="$script_dir/.compile-work-android/TestApps"
apk_path="$apk_dir/$app.apk"
# Lowercased. The APK's application id is lowercase, so `adb shell am start`
# against "dev.swiftcrossui.testapp.P12" finds no such package while the install
# reports success -- the failure looks like the app refusing to launch.
# 轉為小寫。APK 的 application id 是小寫的，因此以 "dev.swiftcrossui.testapp.P12" 執行
# `adb shell am start` 會找不到該套件，而安裝本身卻回報成功——該失敗看起來會像是 app 拒絕啟動。
package_id="dev.swiftcrossui.testapp.$app_id"
adb="$android_root/platform-tools/adb"
emulator="$android_root/emulator/emulator"

zsh "$script_dir/install_tools_android.zsh" --check >/dev/null
[ -x "$adb" ] || die "Missing adb: $adb"

if [ "$do_apk" -eq 1 ]; then
    [ -x "$swift_bin" ] || die "Missing Swift Android toolchain: $swift_bin; run Scripts/build-tool-install-android-on-Mac.sh"
    [ -x "$bundler_bin" ] || die "Missing Swift Bundler: $bundler_bin; run Scripts/build-tool-install-android-on-Mac.sh"

    print "==> Building $app for Android"
    ANDROID_HOME="$android_root" ANDROID_SDK_ROOT="$android_root" \
        ANDROID_NDK_HOME="$android_ndk_home" ANDROID_NDK_ROOT="$android_ndk_home" \
        ANDROID_TRIPLE="$android_triple" SWIFT_BIN="$swift_bin" \
        SCUI_ANDROID=1 zsh "$script_dir/compile.zsh" -android "$app"

    print "==> Bundling $app APK"
    mkdir -p "$apk_dir"
    (
        cd "$package_dir"
        SCUI_ANDROID=1 ANDROID_HOME="$android_root" ANDROID_SDK_ROOT="$android_root" \
            ANDROID_NDK_HOME="$android_ndk_home" ANDROID_NDK_ROOT="$android_ndk_home" \
            "$bundler_bin" bundle "$app" --platform Android -c "${BUILD_CONFIG:-debug}"
    )
    generated_apk="$package_dir/.build/bundler/apps/$app/$app.apk"
    [ -f "$generated_apk" ] || die "Bundler succeeded but APK was not found: $generated_apk"
    cp "$generated_apk" "$apk_path"
    print "    -> $apk_path"
else
    [ -f "$apk_path" ] || die "Missing cached APK: $apk_path; omit -noApk to build it"
    print "==> Reusing $apk_path"
fi

if [ -z "$device_name" ]; then
    device_name="$($emulator -list-avds 2>/dev/null | head -n 1 || true)"
    [ -n "$device_name" ] || die "No Android AVD exists; create one before delivery"
fi

if [[ "$device_name" == emulator-* ]]; then
    serial="$device_name"
else
    print "==> Booting Android AVD: $device_name"
    "$emulator" -avd "$device_name" -no-snapshot -no-boot-anim >/dev/null 2>&1 &
    serial=""
    for _ in {1..60}; do
        serial="$($adb devices | awk '/^emulator-[0-9]+[[:space:]]+/{print $1; exit}')"
        [ -n "$serial" ] && break
        sleep 1
    done
    [ -n "$serial" ] || die "Android emulator did not appear in adb devices"
fi

print "==> Waiting for Android device"
ANDROID_SERIAL="$serial" "$adb" wait-for-device
ANDROID_SERIAL="$serial" "$adb" shell getprop sys.boot_completed | grep -q 1 || {
    for _ in {1..60}; do
        sleep 1
        ANDROID_SERIAL="$serial" "$adb" shell getprop sys.boot_completed 2>/dev/null | grep -q 1 && break
    done
}
ANDROID_SERIAL="$serial" "$adb" shell getprop sys.boot_completed | grep -q 1 || die "Android device did not finish booting"


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
# Start the declared launcher activity directly. `monkey` can return a non-zero
# status for emulator input limitations even when it does not provide a useful
# readiness check for action-file replay.
# 直接啟動 manifest 宣告的 launcher activity。`monkey` 可能因 emulator 輸入限制回傳
# 非零狀態，無法作為 action file replay 的可靠 readiness check。
ANDROID_SERIAL="$serial" "$adb" shell am start -W -n "$package_id/.MainActivity" >/dev/null

print "==> Launched $package_id on $serial"
sleep 1
capture "${app_id}-android-1s"

if [ "$showtime_seconds" -gt 0 ]; then
    sleep "$showtime_seconds"
fi

capture "${app_id}-android-final"
if [ "$screenshot_failures" -gt 0 ]; then
    print -u2 -r -- "!! $screenshot_failures screenshot(s) could not be taken"
fi
