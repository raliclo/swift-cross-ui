#!/usr/bin/env zsh
# Prepare an Android SDK and ARM64 emulator on macOS.
#
#   zsh testapp/install_tools_android.zsh              # install missing tools
#   zsh testapp/install_tools_android.zsh --check       # report only
#   zsh testapp/install_tools_android.zsh --print-env   # print environment
#
# The SDK is kept on the project volume by default. This script prepares the
# platform-tools/adb, Android NDK, and emulator components required to build and
# deliver the test apps. The Swift Android toolchain itself remains separate.
#
# 在 macOS 準備 Android SDK、platform-tools/adb、Android NDK 與 ARM64 emulator。預設將 SDK
# 放在 project volume；Swift Android toolchain 本身仍由另一個安裝腳本負責。

set -euo pipefail

script_path="${0:a}"
android_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${script_path:h:h:h}/.android-sdk}}"
sdkmanager="${ANDROID_SDKMANAGER:-/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager}"
avdmanager="${ANDROID_AVDMANAGER:-$android_root/cmdline-tools/latest/bin/avdmanager}"
emulator="$android_root/emulator/emulator"
avd_name="${ANDROID_AVD_NAME:-swift-cross-ui-api36}"
system_image="system-images;android-36;google_apis;arm64-v8a"
android_platform="platforms;android-36"
android_ndk_version="${ANDROID_NDK_VERSION:-27.0.12077973}"
android_ndk="ndk;$android_ndk_version"

check_only=0
print_env=0
case "${1:-}" in
    --check) check_only=1 ;;
    --print-env) print_env=1 ;;
    -h|--help) sed -n '2,14p' "$script_path" | sed 's/^# *//'; exit 0 ;;
    "") ;;
    *) print -u2 "usage: ${script_path:t} [--check|--print-env|--help]"; exit 64 ;;
esac

note() { print -r -- "==> $1"; }
die() { print -u2 -r -- "[error] $1"; exit 1; }

if [ "$print_env" -eq 1 ]; then
    print "export ANDROID_HOME=\"$android_root\""
    print 'export ANDROID_SDK_ROOT="$ANDROID_HOME"'
    print "export ANDROID_NDK_HOME=\"$android_root/ndk/$android_ndk_version\""
    print 'export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"'
    exit 0
fi

[ -x "$sdkmanager" ] || die "找不到 sdkmanager：$sdkmanager"

if [ "$check_only" -eq 0 ]; then
    mkdir -p "$android_root"
    yes 2>/dev/null | "$sdkmanager" --sdk_root="$android_root" --licenses >/dev/null 2>&1 || true
    ANDROID_HOME="$android_root" "$sdkmanager" --sdk_root="$android_root" \
        emulator platform-tools "$android_platform" "$system_image" "$android_ndk"
fi

[ -x "$emulator" ] || die "缺少 Android emulator：$emulator"
[ -x "$android_root/platform-tools/adb" ] || die "缺少 platform-tools/adb"
[ -x "$android_root/ndk/$android_ndk_version/ndk-build" ] \
    || die "缺少 Android NDK：$android_ndk"
[ -d "$android_root/system-images/android-36/google_apis/arm64-v8a" ] \
    || die "缺少 system image：$system_image"

if [ ! -x "$avdmanager" ]; then
    avdmanager="$(command -v avdmanager 2>/dev/null || true)"
fi
if [ -z "$avdmanager" ] && [ -x "${sdkmanager:h}/avdmanager" ]; then
    avdmanager="${sdkmanager:h}/avdmanager"
fi

if [ "$check_only" -eq 1 ]; then
    note "Android SDK ready at $android_root"
else
    note "Android SDK installed at $android_root"
fi

if [ -n "$avdmanager" ] && [ -x "$avdmanager" ]; then
    if "$avdmanager" list avd 2>/dev/null | grep -q "Name: $avd_name"; then
        note "AVD already exists: $avd_name"
    elif [ "$check_only" -eq 1 ]; then
        note "AVD missing: $avd_name (run without --check to create it)"
    else
        printf 'no\n' | ANDROID_HOME="$android_root" ANDROID_SDK_ROOT="$android_root" "$avdmanager" create avd \
            --force --name "$avd_name" --package "$system_image" --device "pixel_6" >/dev/null
        note "Created AVD: $avd_name"
    fi
else
    die "找不到 avdmanager：$avdmanager"
fi

print ""
print "export ANDROID_HOME=\"$android_root\""
print 'export ANDROID_SDK_ROOT="$ANDROID_HOME"'
print "export ANDROID_NDK_HOME=\"$android_root/ndk/$android_ndk_version\""
print 'export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"'
