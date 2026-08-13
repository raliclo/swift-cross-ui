#!/bin/bash

# Installs everything needed to build swift-cross-ui for Android on macOS, then
# verifies the result by cross-compiling and bundling CounterExample into an APK.
#
# Idempotent: every step is skipped when its output already exists, so it is safe
# to re-run after a partial failure.
#
#   Scripts/build-tool-install-android-on-Mac.sh             # install, then verify
#   Scripts/build-tool-install-android-on-Mac.sh --verify     # verify only
#   Scripts/build-tool-install-android-on-Mac.sh --print-env  # print env exports

set -euo pipefail

# ==============================================================================
# Versions. The Swift toolchain and the Android SDK must be the SAME snapshot:
# a Swift SDK is built against one specific compiler and its module format is
# not compatible across versions.
# ==============================================================================
SWIFT_SNAPSHOT="swift-6.3-DEVELOPMENT-SNAPSHOT-2026-06-07-a"
SWIFT_ANDROID_SDK_CHECKSUM="16bbdf1d75b651488c0c478218fff1a5fa86f3d5572ec2572a1a5759f8fc87db"
NDK_VERSION="r27d"

# The Android API level that the Swift SDK exposes. Note this is 28, not the 24
# that an older comment in .github/workflows/build-test-and-docs.yml implies.
ANDROID_API=28
ANDROID_TRIPLE="aarch64-unknown-linux-android${ANDROID_API}"

# Google's SDK components. Only API 36 is installed: compile_sdk is 36 for every
# app in Examples/Bundler.toml because AndroidBackendHelpers.kt calls
# TimeZone.getIanaID (API 36) behind a runtime SDK_INT check, and resolving that
# symbol still needs API 36 at compile time. Older platform images are never
# consulted, so installing them just wastes ~130MB each.
BUILD_TOOLS_VERSION="34.0.0"
ANDROID_PLATFORMS=("platforms;android-36")

TOOLCHAIN_DIR="$HOME/Library/Developer/Toolchains/${SWIFT_SNAPSHOT}.xctoolchain"
TOOLCHAIN_BIN="$TOOLCHAIN_DIR/usr/bin"
SDK_BUNDLE="$HOME/Library/org.swift.swiftpm/swift-sdks/${SWIFT_SNAPSHOT}_android.artifactbundle"
ANDROID_SDK_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
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
[ "${1:-}" = "--verify" ] && verify_only=1

# ==============================================================================
# 1. Swift toolchain
#
# The Android SDK requires an open source toolchain; Xcode's own Swift cannot
# cross-compile for Android. Note there is no open source Swift 6.4 -- the "Apple
# Swift version 6.4" reported by Xcode 27 is Apple's own numbering, and
# swift.org's API returns 404 for a 6.4 Android SDK. 6.3 is the newest usable
# branch. Installed to the user's home, so no sudo is needed.
# ==============================================================================
install_toolchain() {
    if [ -x "$TOOLCHAIN_BIN/swift" ]; then
        log "Swift toolchain already installed: $SWIFT_SNAPSHOT"
        return
    fi

    log "Downloading Swift toolchain ($SWIFT_SNAPSHOT, ~1.7GB)"
    mkdir -p "$work_dir"
    local pkg="$work_dir/swift-toolchain.pkg"
    curl -fSL --progress-bar -o "$pkg" \
        "https://download.swift.org/swift-6.3-branch/xcode/${SWIFT_SNAPSHOT}/${SWIFT_SNAPSHOT}-osx.pkg"

    log "Installing to home directory (no sudo required)"
    installer -pkg "$pkg" -target CurrentUserHomeDirectory >/dev/null
    rm -f "$pkg"

    [ -x "$TOOLCHAIN_BIN/swift" ] || die "Toolchain install failed"
}

# ==============================================================================
# 2. Swift Android SDK
# ==============================================================================
install_swift_android_sdk() {
    if [ -d "$SDK_BUNDLE" ]; then
        log "Swift Android SDK already installed"
        return
    fi

    log "Installing Swift Android SDK"
    "$TOOLCHAIN_BIN/swift" sdk install \
        "https://download.swift.org/swift-6.3-branch/android-sdk/${SWIFT_SNAPSHOT}/${SWIFT_SNAPSHOT}_android.artifactbundle.tar.gz" \
        --checksum "$SWIFT_ANDROID_SDK_CHECKSUM"
}

# ==============================================================================
# 3. Android NDK
#
# The Swift SDK ships without an NDK and links to one through ndk-sysroot. The
# NDK is Google's C/C++ toolchain and cannot be built from Swift sources.
# ==============================================================================
install_ndk() {
    local ndk_dir="$SDK_BUNDLE/swift-android/android-ndk-${NDK_VERSION}"
    if [ -d "$SDK_BUNDLE/swift-android/ndk-sysroot" ] && [ -d "$ndk_dir" ]; then
        log "Android NDK already linked: $NDK_VERSION"
        return
    fi

    if [ ! -d "$ndk_dir" ]; then
        log "Downloading Android NDK ($NDK_VERSION, ~800MB)"
        mkdir -p "$work_dir"
        local zip="$work_dir/ndk.zip"
        curl -fSL --progress-bar -o "$zip" \
            "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-darwin.zip"
        log "Extracting NDK"
        (cd "$work_dir" && rm -rf "android-ndk-${NDK_VERSION}" && unzip -qo "$zip")
        mv "$work_dir/android-ndk-${NDK_VERSION}" "$SDK_BUNDLE/swift-android/"
        rm -f "$zip"
    fi

    log "Linking NDK into the Swift SDK"
    (cd "$SDK_BUNDLE/swift-android" && ANDROID_NDK_HOME="$ndk_dir" ./scripts/setup-android-sdk.sh)
}

# ==============================================================================
# 4. Google's Android SDK -- only needed to package an APK, not to compile Swift.
# ==============================================================================
install_android_sdk() {
    if [ ! -x "$ANDROID_SDK_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
        command -v brew >/dev/null || die "Homebrew is required to install the Android SDK"
        log "Installing Android command line tools"
        brew install --cask android-commandlinetools
    else
        log "Android command line tools already installed"
    fi

    local sdkmanager="$ANDROID_SDK_HOME/cmdline-tools/latest/bin/sdkmanager"
    local missing=()
    [ -d "$ANDROID_SDK_HOME/build-tools/$BUILD_TOOLS_VERSION" ] || missing+=("build-tools;$BUILD_TOOLS_VERSION")
    [ -d "$ANDROID_SDK_HOME/platform-tools" ] || missing+=("platform-tools")
    for platform in "${ANDROID_PLATFORMS[@]}"; do
        [ -d "$ANDROID_SDK_HOME/platforms/${platform#platforms;}" ] || missing+=("$platform")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        log "Android SDK components already installed"
        return
    fi

    log "Accepting licenses"
    yes 2>/dev/null | ANDROID_HOME="$ANDROID_SDK_HOME" "$sdkmanager" --licenses >/dev/null 2>&1 || true

    log "Installing SDK components: ${missing[*]}"
    ANDROID_HOME="$ANDROID_SDK_HOME" "$sdkmanager" "${missing[@]}" >/dev/null
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
        # Uses the host Swift (Xcode) on purpose: Swift Bundler is a macOS tool,
        # only the cross-compilation itself needs the open source toolchain.
        [ -L Packages/ZIPFoundationModern ] || swift package edit ZIPFoundationModern --path "$zip_dir"
        swift build -c debug --product swift-bundler
        cp .build/debug/swift-bundler "$repo_root/swift-bundler"
        # `swift package edit` rewrites Package.resolved. Restore it so the
        # submodule does not report as modified; the Packages/ symlink that
        # actually drives the override is covered by the submodule's .gitignore.
        git checkout -- Package.resolved 2>/dev/null || true
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
        install_toolchain
        install_swift_android_sdk
        install_ndk
        install_android_sdk
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
