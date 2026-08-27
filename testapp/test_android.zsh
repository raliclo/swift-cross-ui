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
if [ "$showtime_seconds" -gt 0 ]; then
    sleep "$showtime_seconds"
fi
