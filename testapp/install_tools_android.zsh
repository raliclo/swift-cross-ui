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
android_build_tools_version="${ANDROID_BUILD_TOOLS_VERSION:-34.0.0}"
android_build_tools="build-tools;$android_build_tools_version"
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
        emulator platform-tools "$android_platform" "$android_build_tools" "$system_image" "$android_ndk"
fi

[ -x "$emulator" ] || die "缺少 Android emulator：$emulator"
[ -x "$android_root/platform-tools/adb" ] || die "缺少 platform-tools/adb"
[ -x "$android_root/build-tools/$android_build_tools_version/aapt2" ] \
    || die "缺少 Android build-tools：$android_build_tools"
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


# ==============================================================================
# The Swift Android SDK, and the three things about it that are not obvious.
#
# Everything above installs Google's SDK. None of it gives you a Swift compiler
# that can target Android -- that is a separate artefact from swift.org, and
# every one of the checks below corresponds to a way a build failed on
# 2026-09-02 with an error naming something other than the cause. The full
# accounts are in testapp/build_time_android.md.
#
# ==============================================================================
# Swift 的 Android SDK，以及關於它三件並不顯而易見的事。
#
# 以上所有步驟安裝的是 Google 的 SDK，其中沒有任何一項能給你「可以編譯到 Android 的 Swift
# 編譯器」——那是來自 swift.org 的另一項產物。下方每一項檢查，都對應到 2026-09-02 當天一次
# 「錯誤訊息指向真正原因以外之處」的建置失敗。完整說明見 testapp/build_time_android.md。
swift_android_sdk="${SWIFT_ANDROID_SDK:-swift-6.3.3-RELEASE_android}"
swift_android_url="${SWIFT_ANDROID_SDK_URL:-https://download.swift.org/swift-6.3.3-release/android-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_android.artifactbundle.tar.gz}"
swift_android_checksum="${SWIFT_ANDROID_SDK_CHECKSUM:-d160cc3206dd1886dae3fef2337af5e25ec034692cd0ec225721c56cc69da7f5}"
swift_toolchain_dir="${SWIFT_ANDROID_TOOLCHAIN_DIR:-$HOME/Library/Developer/Toolchains/swift-latest.xctoolchain}"

# A toolchain that matches the SDK, not Xcode's.
#
# `swift` on a Mac is Xcode's, which runs ahead of swift.org's release train --
# 6.4 against an Android SDK of 6.3.3 on 2026-09-02. Every module importing
# Foundation then fails with "module compiled with Swift 6.3.3 cannot be
# imported by the Swift 6.4 compiler", which reads as an out-of-date SDK and is
# not: swift.org has published no 6.4 Android SDK because 6.4 is not a release.
#
# 需要與 SDK 相符的 toolchain，而非 Xcode 的那個。
#
# Mac 上的 `swift` 是 Xcode 的，它走在 swift.org 發布列車的前面——2026-09-02 時是 6.4，而 Android
# SDK 是 6.3.3。於是每個 import Foundation 的 module 都以「module compiled with Swift 6.3.3
# cannot be imported by the Swift 6.4 compiler」失敗，那讀起來像是 SDK 過舊，實則不然：swift.org
# 從未發布 6.4 的 Android SDK，因為 6.4 並非一個 release。
if [ -x "$swift_toolchain_dir/usr/bin/swift" ]; then
    note "Swift toolchain for Android: $("$swift_toolchain_dir/usr/bin/swift" --version 2>&1 | head -1)"
else
    die "找不到可用於 Android 的 Swift toolchain：$swift_toolchain_dir
Install a swift.org toolchain matching the Android SDK; Xcode's own will not do."
fi

swift_sdk_cmd=("$swift_toolchain_dir/usr/bin/swift" sdk)
installed_sdks="$("${swift_sdk_cmd[@]}" list 2>/dev/null || true)"

if print -r -- "$installed_sdks" | grep -qx "$swift_android_sdk"; then
    note "Swift Android SDK present: $swift_android_sdk"
elif [ "$check_only" -eq 1 ]; then
    note "Swift Android SDK missing: $swift_android_sdk (run without --check to install it)"
else
    note "Installing the Swift Android SDK (318 MB)"
    "${swift_sdk_cmd[@]}" install "$swift_android_url" --checksum "$swift_android_checksum" \
        || die "swift sdk install failed"
    installed_sdks="$("${swift_sdk_cmd[@]}" list 2>/dev/null || true)"
fi

# One SDK, not several.
#
# Two bundles offering the same triple make every build print "multiple Swift
# SDKs match target triple" and pick one for you. It picked correctly here, but
# "picks one for you" is not a property to build on.
#
# 只留一個 SDK，不要多個。
#
# 兩個 bundle 同時提供相同的 triple，會使每次建置都印出「multiple Swift SDKs match target
# triple」並替你選一個。此處它選對了，但「替你選一個」不是一個可以拿來當基礎的性質。
other_sdks="$(print -r -- "$installed_sdks" | grep -i android | grep -vx "$swift_android_sdk" || true)"
if [ -n "$other_sdks" ]; then
    note "Other Android SDKs are installed; builds will warn that several match:"
    print -r -- "$other_sdks" | sed 's/^/      /'
    print "      remove with: swift sdk remove <name>"
fi

# The release bundle ships no NDK -- link the local one in.
#
# This is the check most worth having, because without it the failure looks
# like a corrupt download: `sdkRootPath` points at `ndk-sysroot`, the release
# bundle does not contain one, and every C target fails with
# "'sys/types.h' file not found". The snapshot bundles did contain an NDK,
# so this only started mattering when the SDK moved to a release.
#
# release bundle 不附帶 NDK——必須把本機的連結進去。
#
# 這是最值得保留的一項檢查，因為少了它，失敗看起來會像下載損毀：`sdkRootPath` 指向
# `ndk-sysroot`，而 release bundle 並不包含它，於是每個 C target 都以「'sys/types.h' file not
# found」失敗。snapshot bundle 內含 NDK，因此這件事是在 SDK 換成 release 之後才開始重要。
swift_sdk_bundle="$HOME/Library/org.swift.swiftpm/swift-sdks/${swift_android_sdk}.artifactbundle/swift-android"
if [ -d "$swift_sdk_bundle" ]; then
    if [ -d "$swift_sdk_bundle/ndk-sysroot/usr" ]; then
        note "ndk-sysroot already linked"
    elif [ "$check_only" -eq 1 ]; then
        note "ndk-sysroot not linked (run without --check to link it)"
    else
        note "Linking ndk-sysroot to the local NDK"
        ANDROID_NDK_HOME="$android_root/ndk/$android_ndk_version" \
            bash "$swift_sdk_bundle/scripts/setup-android-sdk.sh" \
            || die "setup-android-sdk.sh failed"
    fi
fi

print ""
print "export ANDROID_HOME=\"$android_root\""
print 'export ANDROID_SDK_ROOT="$ANDROID_HOME"'
print "export ANDROID_NDK_HOME=\"$android_root/ndk/$android_ndk_version\""
print 'export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"'
