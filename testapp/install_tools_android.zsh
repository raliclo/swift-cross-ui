#!/usr/bin/env zsh
# Prepare an Android SDK and ARM64 emulator on macOS.
#
#   zsh testapp/install_tools_android.zsh              # install missing tools
#   zsh testapp/install_tools_android.zsh --check       # report only
#   zsh testapp/install_tools_android.zsh --print-env   # print environment
#   zsh testapp/install_tools_android.zsh --keep-old    # install, keep older versions
#
# Older versions are removed by default once the current ones are in place
# (-cleanup, which made it opt-in, was tried once on 2026-10-05 and is now the
# default; the flag is still accepted).
# 當前版本就緒後預設移除舊版本（2026-10-05 先以 -cleanup 明確指定試過一次，現為預設；該旗標仍可用）。
#
# The SDK is kept on the project volume by default. This script prepares the
# platform-tools/adb, Android NDK, and emulator components required to build and
# deliver the test apps, and -- since 2026-10-05 -- the swift.org toolchain and
# Swift Android SDK that must match each other exactly (Swift 6.4.0, NDK r30).
#
# 在 macOS 準備 Android SDK、platform-tools/adb、Android NDK 與 ARM64 emulator。預設將 SDK
# 放在 project volume；自 2026-10-05 起也負責彼此必須完全相符的 swift.org toolchain 與 Swift
# Android SDK（Swift 6.4.0、NDK r30）。

set -euo pipefail

script_path="${0:a}"
android_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${script_path:h:h:h}/.android-sdk}}"
sdkmanager="${ANDROID_SDKMANAGER:-/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager}"
avdmanager="${ANDROID_AVDMANAGER:-$android_root/cmdline-tools/latest/bin/avdmanager}"
emulator="$android_root/emulator/emulator"
avd_name="${ANDROID_AVD_NAME:-swift-cross-ui-api36b}"
system_image="system-images;android-36;google_apis;arm64-v8a"
android_platform="platforms;android-36"
android_build_tools_version="${ANDROID_BUILD_TOOLS_VERSION:-34.0.0}"
android_build_tools="build-tools;$android_build_tools_version"
# NDK r30 LTS, which the Swift 6.4 Android SDK requires. Not from sdkmanager: on
# 2026-10-05 its channel listed only `30.0.14904198 rc1`, not the release. The
# release comes from Google's DMG, the one macOS download with a published
# checksum (the zip has none); see install_ndk below.
# NDK r30 LTS，Swift 6.4 的 Android SDK 需要它。不經 sdkmanager：2026-10-05 它的頻道只列出
# `30.0.14904198 rc1`，沒有正式版。正式版取自 Google 的 DMG——macOS 唯一有公布 checksum 的下載
# （zip 沒有）；見下方 install_ndk。
android_ndk_version="${ANDROID_NDK_VERSION:-30.0.16248370}"
android_ndk_dmg_url="${ANDROID_NDK_DMG_URL:-https://dl.google.com/android/repository/android-ndk-r30-darwin.dmg}"
android_ndk_dmg_sha1="${ANDROID_NDK_DMG_SHA1:-48591224b6657f46eebbc9d95d4af09bbed8d107}"

check_only=0
print_env=0
cleanup=1
case "${1:-}" in
    --check) check_only=1 ;;
    --print-env) print_env=1 ;;
    -cleanup|--cleanup) cleanup=1 ;;
    --keep-old) cleanup=0 ;;
    -h|--help) sed -n '2,22p' "$script_path" | sed 's/^# *//'; exit 0 ;;
    "") ;;
    *) print -u2 "usage: ${script_path:t} [--check|--print-env|--keep-old|-cleanup|--help]"; exit 64 ;;
esac

note() { print -r -- "==> $1"; }
die() { print -u2 -r -- "[error] $1"; exit 1; }

if [ "$print_env" -eq 1 ]; then
    print "export ANDROID_HOME=\"$android_root\""
    print 'export ANDROID_SDK_ROOT="$ANDROID_HOME"'
    print "export ANDROID_NDK_HOME=\"$android_root/ndk/$android_ndk_version\""
    print 'export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"'
    # xcode-select 指向 CommandLineTools 時，swift-bundler 缺 `xcstringstool` 而建不起來（2026-10-06）。
    # With xcode-select on CommandLineTools, swift-bundler lacks `xcstringstool` and fails (2026-10-06).
    if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* && -d /Applications/Xcode.app ]]; then
        print 'export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer'
    fi
    exit 0
fi

[ -x "$sdkmanager" ] || die "找不到 sdkmanager：$sdkmanager"

if [ "$check_only" -eq 0 ]; then
    mkdir -p "$android_root"
    yes 2>/dev/null | "$sdkmanager" --sdk_root="$android_root" --licenses >/dev/null 2>&1 || true
    # `cmdline-tools;latest` 裝進 SDK root：Homebrew 的 avdmanager 對這個 SDK root 建 AVD 會以
    # "Package path is not valid" 失敗，SDK root 裡自己的那一份才行（2026-10-06 實測）。
    # `cmdline-tools;latest` goes into the SDK root: Homebrew's avdmanager fails to create an AVD
    # against this SDK root with "Package path is not valid"; the copy inside the root works
    # (measured 2026-10-06).
    ANDROID_HOME="$android_root" "$sdkmanager" --sdk_root="$android_root" \
        emulator platform-tools "cmdline-tools;latest" "$android_platform" "$android_build_tools" "$system_image"
fi

# The NDK from the official DMG, checked against Google's published SHA-1 before
# anything is copied out of it. A mismatch deletes the download and stops.
# 由官方 DMG 安裝 NDK；先比對 Google 公布的 SHA-1，才從裡面複製任何東西。不符就刪掉下載檔並停止。
ndk_dir="$android_root/ndk/$android_ndk_version"
if [ ! -x "$ndk_dir/ndk-build" ] && [ "$check_only" -eq 0 ]; then
    note "Installing Android NDK $android_ndk_version from ${android_ndk_dmg_url:t} (1.0 GB)"
    downloads="$android_root/.downloads"
    mkdir -p "$downloads" "$android_root/ndk"
    dmg="$downloads/${android_ndk_dmg_url:t}"
    if [ ! -f "$dmg" ]; then
        curl -fL --retry 3 -o "$dmg.part" "$android_ndk_dmg_url" || die "NDK download failed"
        mv "$dmg.part" "$dmg"
    fi
    read -r ndk_sum _ < <(shasum -a 1 "$dmg")
    if [ "$ndk_sum" != "$android_ndk_dmg_sha1" ]; then
        rm -f "$dmg"
        die "NDK DMG SHA-1 is $ndk_sum, expected $android_ndk_dmg_sha1; the download was deleted"
    fi
    ndk_mount="$(mktemp -d)"
    hdiutil attach -nobrowse -readonly -mountpoint "$ndk_mount" "$dmg" >/dev/null \
        || die "could not mount $dmg"
    ndk_src=("$ndk_mount"/*.app/Contents/NDK(N/))
    if [ "${#ndk_src}" -ne 1 ]; then
        hdiutil detach "$ndk_mount" >/dev/null 2>&1 || true
        die "the NDK DMG does not hold exactly one *.app/Contents/NDK; layout changed?"
    fi
    rm -rf "$ndk_dir.part"
    ditto "$ndk_src[1]" "$ndk_dir.part" || { hdiutil detach "$ndk_mount" >/dev/null 2>&1; die "copying the NDK failed"; }
    hdiutil detach "$ndk_mount" >/dev/null 2>&1 || true
    mv "$ndk_dir.part" "$ndk_dir"
    rm -f "$dmg"
fi
if [ -f "$ndk_dir/source.properties" ]; then
    ndk_revision="$(sed -nE 's/^Pkg\.Revision *= *//p' "$ndk_dir/source.properties")"
    [ "$ndk_revision" = "$android_ndk_version" ] \
        || die "NDK at $ndk_dir reports $ndk_revision, expected $android_ndk_version"
fi

[ -x "$emulator" ] || die "缺少 Android emulator：$emulator"
[ -x "$android_root/platform-tools/adb" ] || die "缺少 platform-tools/adb"
[ -x "$android_root/build-tools/$android_build_tools_version/aapt2" ] \
    || die "缺少 Android build-tools：$android_build_tools"
if [ ! -x "$android_root/ndk/$android_ndk_version/ndk-build" ]; then
    # --check reports and goes on, so the rest of the state is still shown.
    # --check 只回報並繼續，讓其餘狀態仍然看得到。
    [ "$check_only" -eq 1 ] || die "缺少 Android NDK $android_ndk_version"
    note "Android NDK missing: $android_ndk_version (run without --check to install it)"
fi
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
    # Whole-name match. `grep -q "Name: …api36"` also matched "…api36b", so --check
    # reported a deleted AVD as present (2026-10-05).
    # 比對完整名稱。`grep -q "Name: …api36"` 也會比對到「…api36b」，於是 --check 把一個已刪除的
    # AVD 回報成存在（2026-10-05）。
    if "$avdmanager" list avd 2>/dev/null | grep -qE "Name: ${avd_name}\$"; then
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
# One version number drives the toolchain, the SDK and their URLs, because they
# must match exactly. 6.3.3 until 2026-10-05; the checksum is the one swift.org
# publishes for 6.4.0 and must be supplied with any other version.
# 同一個版本號決定 toolchain、SDK 與它們的網址，因為兩者必須完全相符。2026-10-05 之前是 6.3.3；
# checksum 是 swift.org 為 6.4.0 公布的那一個，換其他版本時必須一併提供。
swift_android_version="${SWIFT_ANDROID_VERSION:-6.4.0}"
swift_android_sdk="${SWIFT_ANDROID_SDK:-swift-${swift_android_version}-RELEASE_android}"
swift_android_url="${SWIFT_ANDROID_SDK_URL:-https://download.swift.org/swift-${swift_android_version}-release/android-sdk/swift-${swift_android_version}-RELEASE/swift-${swift_android_version}-RELEASE_android.artifactbundle.tar.gz}"
if [ "$swift_android_version" = 6.4.0 ]; then
    swift_android_checksum="${SWIFT_ANDROID_SDK_CHECKSUM:-21fb555122a3d801ad943d48df7ebffdd8824de61c25c180bb792d3edaee0b43}"
else
    swift_android_checksum="${SWIFT_ANDROID_SDK_CHECKSUM:?set SWIFT_ANDROID_SDK_CHECKSUM for Swift $swift_android_version}"
fi
swift_toolchain_name="swift-${swift_android_version}-RELEASE.xctoolchain"
swift_toolchain_dir="${SWIFT_ANDROID_TOOLCHAIN_DIR:-$HOME/Library/Developer/Toolchains/$swift_toolchain_name}"
swift_toolchain_pkg_url="${SWIFT_TOOLCHAIN_PKG_URL:-https://download.swift.org/swift-${swift_android_version}-release/xcode/swift-${swift_android_version}-RELEASE/swift-${swift_android_version}-RELEASE-osx.pkg}"
# Kept on the project volume beside the Android SDK and linked into
# ~/Library/Developer/Toolchains: a toolchain is several GB and the system volume
# had 11 GB free on 2026-10-05. Android builds depend on this volume already.
# 放在 project volume、與 Android SDK 並列，再連結進 ~/Library/Developer/Toolchains：toolchain 有
# 好幾 GB，而 2026-10-05 系統磁碟只剩 11 GB。Android 建置本來就依賴這顆磁碟。
swift_toolchain_store="${SWIFT_TOOLCHAIN_STORE:-${script_path:h:h:h}/.swift-toolchains}"

# A toolchain that matches the SDK, not Xcode's.
#
# `swift` on a Mac is Xcode's, which runs ahead of swift.org's release train --
# 6.4 against an Android SDK of 6.3.3 on 2026-09-02. Every module importing
# Foundation then fails with "module compiled with Swift 6.3.3 cannot be
# imported by the Swift 6.4 compiler", which reads as an out-of-date SDK and is
# not: swift.org had published no 6.4 Android SDK because 6.4 was not a release.
# (6.4.0 is released now, and swift.org's guide still says the same thing: a
# cross-compilation SDK needs an open-source toolchain of exactly its version, so
# Xcode's 6.4 will not do even beside a 6.4.0 SDK. Checked 2026-10-05.)
#
# 需要與 SDK 相符的 toolchain，而非 Xcode 的那個。
#
# Mac 上的 `swift` 是 Xcode 的，它走在 swift.org 發布列車的前面——2026-09-02 時是 6.4，而 Android
# SDK 是 6.3.3。於是每個 import Foundation 的 module 都以「module compiled with Swift 6.3.3
# cannot be imported by the Swift 6.4 compiler」失敗，那讀起來像是 SDK 過舊，實則不然：swift.org
# 當時沒有發布 6.4 的 Android SDK，因為 6.4 還不是一個 release。（現在 6.4.0 已發布，而 swift.org
# 的指南仍然這麼說：cross-compilation SDK 需要版本**完全相同**的 open-source toolchain，所以即使有
# 6.4.0 的 SDK，Xcode 的 6.4 也不行。2026-10-05 查證。）
#
# The toolchain is installed from swift.org's signed .pkg: the signature is
# checked with pkgutil, the payload is expanded onto the project volume, and
# `swift-latest` is pointed at it, because test_android.zsh builds with
# `swift-latest`.
# toolchain 由 swift.org 簽章過的 .pkg 安裝：先以 pkgutil 檢查簽章，再把 payload 解開到 project
# volume，並把 `swift-latest` 指向它——因為 test_android.zsh 用 `swift-latest` 建置。
if [ ! -x "$swift_toolchain_dir/usr/bin/swift" ] && [ "$check_only" -eq 0 ]; then
    note "Installing the swift.org $swift_android_version toolchain (1.6 GB download)"
    mkdir -p "$swift_toolchain_store/.downloads" "${swift_toolchain_dir:h}"
    pkg="$swift_toolchain_store/.downloads/${swift_toolchain_pkg_url:t}"
    if [ ! -f "$pkg" ]; then
        curl -fL --retry 3 -o "$pkg.part" "$swift_toolchain_pkg_url" || die "toolchain download failed"
        mv "$pkg.part" "$pkg"
    fi
    pkg_signature="$(pkgutil --check-signature "$pkg" 2>&1 || true)"
    if ! print -r -- "$pkg_signature" | grep -q 'Status: signed by a developer certificate issued by Apple'; then
        print -u2 -r -- "$pkg_signature"
        rm -f "$pkg"
        die "the toolchain .pkg is not signed by an Apple-issued developer certificate; deleted"
    fi
    note "$(print -r -- "$pkg_signature" | grep -m1 -E '^ *1\. ' | sed 's/^ *//')"
    expand_dir="$(mktemp -d "$swift_toolchain_store/.expand.XXXXXX")"
    pkgutil --expand-full "$pkg" "$expand_dir/pkg" || die "pkgutil --expand-full failed"
    found_swift=("$expand_dir"/pkg/**/Payload/**/usr/bin/swift(N))
    [ "${#found_swift}" -eq 1 ] || die "expected one usr/bin/swift in the .pkg payload, found ${#found_swift}"
    toolchain_root="${found_swift[1]:h:h:h}"
    rm -rf "$swift_toolchain_store/$swift_toolchain_name"
    mv "$toolchain_root" "$swift_toolchain_store/$swift_toolchain_name"
    rm -rf "$expand_dir" "$pkg"
    ln -sfn "$swift_toolchain_store/$swift_toolchain_name" "$swift_toolchain_dir"
fi
if [ -x "$swift_toolchain_dir/usr/bin/swift" ] && [ "$check_only" -eq 0 ]; then
    latest="${swift_toolchain_dir:h}/swift-latest.xctoolchain"
    previous="$(readlink "$latest" 2>/dev/null || true)"
    target="$(readlink "$swift_toolchain_dir" 2>/dev/null || print -r -- "$swift_toolchain_dir")"
    if [ "$previous" != "$target" ]; then
        ln -sfn "$target" "$latest"
        note "swift-latest now -> $target (was ${previous:-unset})"
    fi
fi
if [ -x "$swift_toolchain_dir/usr/bin/swift" ]; then
    note "Swift toolchain for Android: $("$swift_toolchain_dir/usr/bin/swift" --version 2>&1 | head -1)"
elif [ "$check_only" -eq 1 ]; then
    note "Swift toolchain missing: $swift_toolchain_dir (run without --check to install it)"
    note "Not checking the Swift Android SDK: it is listed through that toolchain"
    exit 0
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
if [ -n "$other_sdks" ] && [ "$cleanup" -eq 0 ]; then
    # Not a warning only: with two bundles offering the triple, SwiftPM 6.4 refuses
    # the build ("matched multiple SDKs"), measured 2026-10-05. -cleanup removes them.
    # 不只是警告：兩個 bundle 提供同一 triple 時，SwiftPM 6.4 直接拒絕建置（「matched multiple
    # SDKs」，2026-10-05 實測）。-cleanup 會移除它們。
    note "Other Android SDKs are installed (--keep-old); builds will refuse until they are removed:"
    print -r -- "$other_sdks" | sed 's/^/      /'
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

# Older versions out, once the current ones are all in place (2026-10-05, the
# user's rule). Three kinds, each only what this script manages: other Swift
# Android SDKs, other NDKs under $android_root/ndk, and swift.org toolchains in
# ~/Library/Developer/Toolchains whose `swift --version` is older than this one
# -- decided by the version the toolchain reports, never by its name. Nothing is
# removed unless the new toolchain, SDK and NDK are present; --check only lists
# what would go, and --keep-old skips this. It was opt-in (-cleanup) for one
# trial on 2026-10-05: that run removed exactly the 6.3.3 SDK, NDK 27 and the 6.3
# snapshot toolchain, and P76 compiled for Android on 6.4.0 afterwards.
# 當前版本全部就緒之後，移除舊版本（2026-10-05，使用者的規則）。三類，且只動本腳本管理的：其他的
# Swift Android SDK、$android_root/ndk 下其他版本的 NDK，以及 ~/Library/Developer/Toolchains 裡
# `swift --version` 比這一版舊的 swift.org toolchain——以 toolchain 自己回報的版本判斷，從不看名稱。
# 新的 toolchain、SDK、NDK 沒有全部就緒就什麼都不刪；--check 只列出會刪什麼，--keep-old 跳過整段。
# 2026-10-05 曾以 -cleanup 明確指定試過一次：那次剛好移除 6.3.3 SDK、NDK 27 與 6.3 snapshot
# toolchain，之後 P76 以 6.4.0 為 Android 編譯成功。
current_ready=0
if [ -x "$swift_toolchain_dir/usr/bin/swift" ] && [ -x "$ndk_dir/ndk-build" ] \
    && print -r -- "$installed_sdks" | grep -qx "$swift_android_sdk"; then
    current_ready=1
fi
if { [ "$cleanup" -eq 1 ] || [ "$check_only" -eq 1 ]; } && [ "$current_ready" -eq 1 ]; then
    autoload -Uz is-at-least
    remove() {
        # $1 = what, $2 = path or name; prints in both modes, acts only when installing.
        if [ "$check_only" -eq 1 ]; then
            note "Would remove old $1: $2"
        else
            note "Removing old $1: $2"
        fi
        [ "$check_only" -eq 1 ]
    }
    for name in ${(f)other_sdks}; do
        [ -n "$name" ] || continue
        remove "Swift Android SDK" "$name" || "${swift_sdk_cmd[@]}" remove "$name" >/dev/null
    done
    for old_ndk in "$android_root"/ndk/*(N/); do
        [ "${old_ndk:t}" = "$android_ndk_version" ] && continue
        remove "NDK" "$old_ndk" || rm -rf -- "${old_ndk:?}"
    done
    current_target="$(readlink "$swift_toolchain_dir" 2>/dev/null || print -r -- "$swift_toolchain_dir")"
    for old_tc in "${swift_toolchain_dir:h}"/swift-*.xctoolchain(N); do
        [ "${old_tc:t}" = swift-latest.xctoolchain ] && continue
        [ "$old_tc" = "$swift_toolchain_dir" ] && continue
        old_target="$(readlink "$old_tc" 2>/dev/null || print -r -- "$old_tc")"
        [ "$old_target" = "$current_target" ] && continue
        [ -x "$old_tc/usr/bin/swift" ] || continue
        old_version="$("$old_tc/usr/bin/swift" --version 2>&1 | sed -nE 's/.*Swift version ([0-9][0-9.]*).*/\1/p' | head -1)"
        [ -n "$old_version" ] || continue
        is-at-least "$swift_android_version" "$old_version" && continue
        if ! remove "toolchain (Swift $old_version)" "$old_tc"; then
            if [ -L "$old_tc" ]; then
                rm -f -- "${old_tc:?}"
                case "$old_target" in "$swift_toolchain_store"/*) rm -rf -- "${old_target:?}" ;; esac
            else
                rm -rf -- "${old_tc:?}"
            fi
        fi
    done
elif [ "$cleanup" -eq 1 ]; then
    note "Not removing old versions: the current toolchain, SDK and NDK are not all present yet"
fi

print ""
print "export ANDROID_HOME=\"$android_root\""
print 'export ANDROID_SDK_ROOT="$ANDROID_HOME"'
print "export ANDROID_NDK_HOME=\"$android_root/ndk/$android_ndk_version\""
print 'export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"'
