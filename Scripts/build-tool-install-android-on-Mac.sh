#!/bin/bash

# Installs everything needed to build swift-cross-ui for Android on macOS, then
# verifies the result by cross-compiling and bundling CounterExample into an APK.
#
# Idempotent: every step is skipped when its output already exists, so it is safe
# to re-run after a partial failure.
#
#   Scripts/build-tool-install-android-on-Mac.sh             # install, then verify
#   Scripts/build-tool-install-android-on-Mac.sh -cleanup    # same, and remove older versions
#   Scripts/build-tool-install-android-on-Mac.sh --verify     # verify only
#   Scripts/build-tool-install-android-on-Mac.sh --print-env  # print env exports
#
# Since 2026-10-05 the Swift toolchain, the Swift Android SDK, the NDK and Google's
# SDK are installed by testapp/install_tools_android.zsh, which this calls; this
# script keeps Swift Bundler and the CounterExample check. It used to pin its own
# 6.3 snapshot, NDK r27d and API 28, which disagreed with the testapp scripts
# (6.3.3 release, API 31) and would have put back what the other one removed.
#
# 自 2026-10-05 起，Swift toolchain、Swift Android SDK、NDK 與 Google 的 SDK 由
# testapp/install_tools_android.zsh 安裝，本腳本呼叫它；本腳本只保留 Swift Bundler 與 CounterExample
# 的驗證。它原本自己釘住 6.3 snapshot、NDK r27d 與 API 28，與 testapp 的腳本（6.3.3 release、API 31）
# 不一致，而且會把另一支剛移除的東西裝回去。

set -euo pipefail

# ==============================================================================
# Versions live in testapp/install_tools_android.zsh: the Swift toolchain and the
# Android SDK must be the SAME version, and one place keeps them so. It points
# `swift-latest` at the toolchain it installs, which is what this uses.
# ==============================================================================

# The API level the testapp scripts build for (compile.zsh, test_android.zsh,
# androidContainer/Bundler.android.toml). This said 28 while they said 31.
ANDROID_API=31
ANDROID_TRIPLE="aarch64-unknown-linux-android${ANDROID_API}"

# Google's SDK components. Only API 36 is installed: compile_sdk is 36 for every
# app in Examples/Bundler.toml because AndroidBackendHelpers.kt calls
# TimeZone.getIanaID (API 36) behind a runtime SDK_INT check, and resolving that
# symbol still needs API 36 at compile time. Older platform images are never
# consulted, so installing them just wastes ~130MB each.
BUILD_TOOLS_VERSION="34.0.0"
ANDROID_PLATFORMS=("platforms;android-36")

TOOLCHAIN_DIR="$HOME/Library/Developer/Toolchains/swift-latest.xctoolchain"
TOOLCHAIN_BIN="$TOOLCHAIN_DIR/usr/bin"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
# Where install_tools_android.zsh keeps Google's SDK: the project volume.
ANDROID_SDK_HOME="${ANDROID_HOME:-$(cd "$repo_root/.." && pwd)/.android-sdk}"
work_dir="${TMPDIR:-/tmp}/scui-android-install"
# Records which Vendor commits the checked-in swift-bundler binary was built
# from, so a submodule bump forces a rebuild instead of reusing a stale binary.
bundler_stamp="$repo_root/.swift-bundler-stamp"

log()  { printf '\033[36m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[33m[warn]\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[31m[error]\033[0m %s\n' "$1" >&2; exit 1; }

print_env() {
    cat <<EOF
export ANDROID_HOME="$ANDROID_SDK_HOME"
export SCUI_ANDROID=1
export PATH="$TOOLCHAIN_BIN:\$PATH"
EOF
}

if [ "${1:-}" = "--print-env" ]; then
    print_env
    exit 0
fi

verify_only=0
cleanup_flag=()
case "${1:-}" in
    --verify) verify_only=1 ;;
    -cleanup|--cleanup) cleanup_flag=(-cleanup) ;;
esac

# ==============================================================================
# 1-4. The Swift toolchain, the Swift Android SDK, the NDK and Google's SDK.
#
# One installer for all four, so versions cannot drift between two scripts:
# testapp/install_tools_android.zsh (Swift 6.4.0, NDK r30 since 2026-10-05).
# `-cleanup` is passed through and removes older versions there.
# ==============================================================================
install_android_tools() {
    log "Installing the Android toolchain, SDK and NDK (testapp/install_tools_android.zsh)"
    zsh "$repo_root/testapp/install_tools_android.zsh" ${cleanup_flag[@]+"${cleanup_flag[@]}"} \
        || die "testapp/install_tools_android.zsh failed"
}

# ==============================================================================
# 5. Swift Bundler (optional -- only needed to produce an APK)
#
# Both sources live in Vendor/ as submodules, so the versions are pinned by this
# repository rather than resolved at install time.
#
# Swift Bundler's ZIPFoundationModern dependency does not compile under Swift
# 6.3+: it uses `.append(contentsOf: .init(repeating:count:))`, whose implicit
# type can no longer be inferred. Upstream 0.0.9 still has the bug, so
# Vendor/ZIPFoundationModern tracks a fork carrying the one-line fix, and it is
# injected with `swift package edit`, which leaves Swift Bundler's manifest
# untouched.
# ==============================================================================
install_swift_bundler() {
    local bundler_dir="$repo_root/Vendor/swift-bundler"
    local zip_dir="$repo_root/Vendor/ZIPFoundationModern"

    # Check out the submodules first: the staleness check below reads their
    # commits, so it cannot run against empty directories.
    if [ ! -f "$bundler_dir/Package.swift" ] || [ ! -f "$zip_dir/Package.swift" ]; then
        log "Checking out Vendor submodules"
        (cd "$repo_root" && git submodule update --init --recursive Vendor)
    fi

    [ -f "$bundler_dir/Package.swift" ] || die "Vendor/swift-bundler is empty; run: git submodule update --init --recursive"

    # The binary is only reusable if it was built from the Vendor commits that
    # are checked out right now. Testing for mere existence would silently keep
    # a stale binary after a submodule bump.
    local want
    want="$(git -C "$bundler_dir" rev-parse HEAD)+$(git -C "$zip_dir" rev-parse HEAD)"

    if [ -x "$repo_root/swift-bundler" ] && [ "$(cat "$bundler_stamp" 2>/dev/null)" = "$want" ]; then
        log "Swift Bundler already built from the current Vendor commits"
        return
    fi

    if [ -x "$repo_root/swift-bundler" ]; then
        log "Vendor commits changed, rebuilding Swift Bundler"
    else
        log "Building Swift Bundler"
    fi

    (
        cd "$bundler_dir"

        # `swift package edit` and the build both rewrite Package.resolved.
        # Snapshot it and put the snapshot back on the way out, rather than
        # running `git checkout --`: the file may already carry edits that are
        # not ours, and discarding those would be silent data loss. The trap
        # also covers a failed build, which an unconditional restore after the
        # build would skip.
        resolved_backup=""
        if [ -f Package.resolved ]; then
            resolved_backup="$(mktemp)"
            cp Package.resolved "$resolved_backup"
        fi
        restore_resolved() {
            if [ -n "$resolved_backup" ] && [ -f "$resolved_backup" ]; then
                if ! cmp -s "$resolved_backup" Package.resolved; then
                    cp "$resolved_backup" Package.resolved
                fi
                rm -f "$resolved_backup"
            fi
        }
        trap restore_resolved EXIT

        # Uses the host Swift (Xcode) on purpose: Swift Bundler is a macOS tool,
        # only the cross-compilation itself needs the open source toolchain.
        [ -L Packages/ZIPFoundationModern ] || swift package edit ZIPFoundationModern --path "$zip_dir"
        swift build -c debug --product swift-bundler
        cp .build/debug/swift-bundler "$repo_root/swift-bundler"
    )

    printf '%s\n' "$want" >"$bundler_stamp"
}

# ==============================================================================
# 6. Verification -- compile, then package.
#
# SCUI_ANDROID=1 opts AndroidBackend and AndroidBackendShim into the package.
# They are excluded by default because AndroidBackendShim includes
# <android/log.h>, and the build system scans every C target regardless of the
# platform being built for, so leaving them in breaks macOS/Linux/Windows builds.
# ==============================================================================
verify() {
    log "Cross-compiling CounterExample ($ANDROID_TRIPLE)"
    (
        cd "$repo_root/Examples"
        SCUI_ANDROID=1 "$TOOLCHAIN_BIN/swift" build \
            --swift-sdk "$ANDROID_TRIPLE" --product CounterExample
    )

    local binary="$repo_root/Examples/.build/$ANDROID_TRIPLE/debug/CounterExample"
    [ -f "$binary" ] || die "Binary was not produced"
    if ! file "$binary" | grep -q "ARM aarch64"; then
        die "Wrong architecture: $(file "$binary")"
    fi
    log "Compiled:$(file "$binary" | cut -d: -f2- | cut -c1-58)"

    # Failing here rather than warning: a --verify run that silently skips APK
    # packaging would report success while having proven only half the pipeline.
    if [ ! -x "$repo_root/swift-bundler" ]; then
        die "Swift Bundler is missing, so the APK step cannot run. Re-run without --verify to build it."
    fi

    log "Bundling APK"
    (
        cd "$repo_root/Examples"
        ANDROID_HOME="$ANDROID_SDK_HOME" SCUI_ANDROID=1 \
            "$repo_root/swift-bundler" bundle CounterExample --platform Android
    )

    local apk="$repo_root/Examples/.build/bundler/apps/CounterExample/CounterExample.apk"
    [ -f "$apk" ] || die "APK was not produced"
    log "APK: $(du -h "$apk" | cut -f1), $(unzip -l "$apk" | tail -1 | awk '{print $2}') files"
}

# ==============================================================================
main() {
    if [ "$(uname -s)" != "Darwin" ]; then
        die "This script targets macOS"
    fi

    if [ "$verify_only" -eq 0 ]; then
        install_android_tools
        install_swift_bundler
    fi

    verify

    cat <<EOF

$(printf '\033[32m')Android build environment ready$(printf '\033[0m')

Add this to your shell to build manually:

$(print_env)

Then:

  cd Examples
  swift build --swift-sdk $ANDROID_TRIPLE --product CounterExample
  ../swift-bundler bundle CounterExample --platform Android

EOF
}

main
