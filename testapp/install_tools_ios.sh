#!/bin/bash
# Prepares a macOS environment for building and running swift-cross-ui test apps
# on the iOS Simulator.
#
#   bash testapp/install_tools_ios.sh              # check, install what is missing
#   bash testapp/install_tools_ios.sh --check       # report only, change nothing
#   bash testapp/install_tools_ios.sh --print-env   # print the values compile.zsh uses
#
# compile.zsh calls this automatically when given -ios, so running it by hand is
# only needed to see what is missing or to install ahead of time.
#
# Everything here is idempotent, so re-running it is safe.
#
# What it deals with, learned while getting UIKitBackend to build:
#
# - `swift build -Xswiftc -sdk <iphonesimulator>` does NOT work. That flag is
#   global, so it applies the iOS SDK to every target including
#   SwiftCrossUIMacrosPlugin, which is a compile-time tool that has to be built
#   for the host. The link then fails. xcodebuild with an iOS destination is the
#   supported route, because it distinguishes host tools from target code.
# - `simctl list devices available` reporting nothing does not mean no runtime
#   is installed. It lists devices, and a fresh Xcode has runtimes but no
#   devices created from them. Check `simctl runtime list` instead.
# - Command Line Tools alone are not enough: a full Xcode is required for
#   iPhoneSimulator SDKs and for xcodebuild.

set -euo pipefail

DEVICE_NAME="${IOS_SIM_DEVICE:-swift-cross-ui}"
DEVICE_TYPE="${IOS_SIM_DEVICE_TYPE:-iPhone 16}"

log()  { printf '\033[36m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[33m[warn]\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[31m[error]\033[0m %s\n' "$1" >&2; exit 1; }

check_only=0
print_env=0
case "${1:-}" in
    --check) check_only=1 ;;
    --print-env) print_env=1 ;;
    "") ;;
    *) die "usage: $(basename "$0") [--check|--print-env]" ;;
esac

# ==============================================================================
# 1. A full Xcode, not just Command Line Tools.
# ==============================================================================
require_xcode() {
    local dir
    dir="$(xcode-select -p 2>/dev/null || true)"

    if [ -z "$dir" ] || [ ! -d "$dir/Platforms/iPhoneSimulator.platform" ]; then
        die "$(printf '%s\n' \
            "xcode-select points at '${dir:-nothing}', which has no iPhoneSimulator platform." \
            "Install Xcode, then point at it:" \
            "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer")"
    fi

    log "Xcode: $(xcodebuild -version 2>/dev/null | head -1) at $dir"
}

# ==============================================================================
# 2. An iOS Simulator SDK.
# ==============================================================================
require_sdk() {
    local sdk
    sdk="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)"
    [ -n "$sdk" ] || die "No iphonesimulator SDK. Install the iOS platform in Xcode."
    log "SDK: $(basename "$sdk")"
}

# ==============================================================================
# 3. An iOS runtime.
#
# Runtimes ship with Xcode or are downloaded separately. `xcodebuild
# -downloadPlatform iOS` fetches one, but it is several GB, so this only offers
# the command rather than running it unprompted.
# ==============================================================================
require_runtime() {
    local runtimes
    runtimes="$(xcrun simctl runtime list 2>/dev/null | grep -E '^iOS .*\(Ready\)' || true)"

    if [ -z "$runtimes" ]; then
        die "$(printf '%s\n' \
            "No iOS runtime is ready. Download one with:" \
            "  xcodebuild -downloadPlatform iOS" \
            "(several GB; check 'xcrun simctl runtime list' afterwards)")"
    fi

    log "Runtime: $(printf '%s' "$runtimes" | tail -1 | sed 's/ *(Ready)//')"
}

# ==============================================================================
# 4. A simulator device.
#
# This is the piece Xcode does not create for you, and its absence is what makes
# `simctl list devices available` look as though nothing is installed.
# ==============================================================================
ensure_device() {
    local existing
    existing="$(xcrun simctl list devices 2>/dev/null | grep -F "$DEVICE_NAME (" | head -1 || true)"

    if [ -n "$existing" ]; then
        log "Device: $DEVICE_NAME already exists"
        return
    fi

    if [ "$check_only" -eq 1 ]; then
        warn "Device '$DEVICE_NAME' does not exist; run without --check to create it"
        return
    fi

    local runtime
    runtime="$(xcrun simctl list runtimes 2>/dev/null \
        | grep -E '^iOS' \
        | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.[^ ]+' \
        | tail -1)"
    [ -n "$runtime" ] || die "Could not determine a runtime identifier"

    log "Creating device '$DEVICE_NAME' ($DEVICE_TYPE on ${runtime##*.})"
    xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$runtime" >/dev/null \
        || die "Failed to create the device. Try a different IOS_SIM_DEVICE_TYPE; see 'xcrun simctl list devicetypes'."
}

device_udid() {
    xcrun simctl list devices 2>/dev/null \
        | grep -F "$DEVICE_NAME (" \
        | head -1 \
        | grep -oE '[0-9A-F-]{36}'
}

if [ "$print_env" -eq 1 ]; then
    printf 'IOS_SIM_DEVICE=%s\n' "$DEVICE_NAME"
    printf 'IOS_SIM_UDID=%s\n' "$(device_udid || true)"
    printf 'IOS_SDK_PATH=%s\n' "$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)"
    exit 0
fi

require_xcode
require_sdk
require_runtime
ensure_device

udid="$(device_udid || true)"
if [ -z "$udid" ]; then
    # Only reachable under --check, where ensure_device declines to create one.
    # Reporting "ready" here would be a false pass: compile.zsh -ios needs the
    # device to install onto.
    warn "No device yet, so the environment is not ready. Re-run without --check."
    exit 1
fi

log "Ready. Device UDID: $udid"

cat <<EOF

$(printf '\033[32m')iOS build environment ready$(printf '\033[0m')

Build a test app for the simulator:

  sh testapp/compile.zsh -ios P11

Run it:

  xcrun simctl boot "$DEVICE_NAME"
  open -a Simulator

EOF
