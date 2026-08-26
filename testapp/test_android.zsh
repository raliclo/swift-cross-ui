#!/usr/bin/env zsh
# Build, bundle, install, and launch one SwiftCrossUI test app on an Android
# emulator. The APK cache is deliberately separate from source and build trees.
#
#   zsh testapp/test_android.zsh P12
#   zsh testapp/test_android.zsh P12 -noApk
#   zsh testapp/test_android.zsh P12 -replay actions/android/P12-android-smoke.csv
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
Usage: ${script_path:t} <P0..Pn> [-noApk] [-replay [path]] [--showtime seconds] [--device name|serial]

Default: compile and bundle a fresh Android APK, then install and launch it.
-noApk: reuse testapp/.androidApk/<Pn>.apk and skip compile/bundle.
-replay: replay an Android action file after launch; without a path, use
         testapp/actions/android/<Pn>-*.csv when exactly one file exists.
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
shift
[[ "$app" == P<-> ]] || die "Invalid test target: $app"

while [ "$#" -gt 0 ]; do
    case "$1" in
        -noApk|--no-apk) do_apk=0; shift ;;
        -replay|--replay)
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
bundler_bin="${SWIFT_BUNDLER:-$repo_root/swift-bundler}"
android_triple="${ANDROID_TRIPLE:-aarch64-unknown-linux-android28}"
swift_snapshot="${SWIFT_ANDROID_SNAPSHOT:-swift-6.3-DEVELOPMENT-SNAPSHOT-2026-06-07-a}"
swift_bin="${SWIFT_BIN:-$HOME/Library/Developer/Toolchains/${swift_snapshot}.xctoolchain/usr/bin/swift}"
package_dir="$script_dir/.compile-work-android/TestApps"
apk_path="$apk_dir/$app.apk"
package_id="dev.swiftcrossui.testapp.$app"
adb="$android_root/platform-tools/adb"
emulator="$android_root/emulator/emulator"

zsh "$script_dir/install_tools_android.zsh" --check >/dev/null
[ -x "$adb" ] || die "Missing adb: $adb"

if [ "$do_apk" -eq 1 ]; then
    [ -x "$swift_bin" ] || die "Missing Swift Android toolchain: $swift_bin; run Scripts/build-tool-install-android-on-Mac.sh"
    [ -x "$bundler_bin" ] || die "Missing Swift Bundler: $bundler_bin; run Scripts/build-tool-install-android-on-Mac.sh"

    print "==> Building $app for Android"
    ANDROID_HOME="$android_root" ANDROID_SDK_ROOT="$android_root" \
        ANDROID_TRIPLE="$android_triple" SWIFT_BIN="$swift_bin" \
        SCUI_ANDROID=1 zsh "$script_dir/compile.zsh" -android "$app"

    print "==> Bundling $app APK"
    mkdir -p "$apk_dir"
    (
        cd "$package_dir"
        ANDROID_HOME="$android_root" ANDROID_SDK_ROOT="$android_root" \
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
ANDROID_SERIAL="$serial" "$adb" shell monkey -p "$package_id" 1 >/dev/null

print "==> Launched $package_id on $serial"
if [ "$showtime_seconds" -gt 0 ]; then
    sleep "$showtime_seconds"
fi
