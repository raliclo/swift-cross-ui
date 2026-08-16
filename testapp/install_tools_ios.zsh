#!/usr/bin/env zsh
# Prepares a macOS environment for building and running swift-cross-ui test apps
# on the iOS Simulator.
#
#   bash testapp/install_tools_ios.zsh              # check, install what is missing
#   bash testapp/install_tools_ios.zsh --check       # report only, change nothing
#   bash testapp/install_tools_ios.zsh --print-env   # print the values compile.zsh uses
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

# Captured at top level. zsh sets FUNCTION_ARGZERO by default, so inside a
# function $0 is the function's own name, not this file -- reading the header
# through $0 from a helper would try to open a file named after the function.
# 在頂層取得。zsh 預設啟用 FUNCTION_ARGZERO，函式內的 $0 是函式名稱而非本檔；
# 若從輔助函式以 $0 讀取檔頭，會去開一個以函式為名的檔案。
script_path="${0:a}"

# Named `note`, not `log`. `log` is a zsh builtin belonging to the zsh/watch
# module, so defining a function over it makes zsh try to load that module --
# and a relocatable zsh sets module_path from .zshenv, which any startup-file-
# skipping mode (`zsh -f`, `zsh -n`, a sandboxed run) never reads. It then
# falls back to the compile-time default path and reports
# "failed to load module `zsh/watch'". The module is present; the path is not.
#
# Installing anything does not fix it. Not colliding with the name does, and
# without depending on how the environment happens to be set up. The same rule
# applies to zsh's special parameters -- `path`, `status`, `options`, `watch`:
# pick `watch_list` over `watch`.
# 取名 note 而非 log。`log` 是 zsh/watch 模組的內建指令，覆寫它會使 zsh 嘗試載入
# 該模組；而可重定位的 zsh 由 .zshenv 設定 module_path，任何跳過啟動檔的模式
# （`zsh -f`、`zsh -n`、沙箱執行）都讀不到，於是退回編譯期預設路徑並報錯。模組是
# 存在的，缺的是路徑——所以裝模組解決不了，改名才能一勞永逸，且不依賴環境條件。
#
# Colour comes from `print -P`, zsh's own prompt expansion, rather than hand
# written ANSI escapes. The message itself goes through `print -r --` so a `%`
# in a device name or path is printed literally instead of being read as a
# prompt sequence.
# 顏色使用 zsh 自身的 prompt 展開 `print -P`，而非手寫 ANSI escape；訊息本體改走
# `print -r --`，讓裝置名稱或路徑中的 `%` 原樣輸出，不被當成 prompt 序列解讀。
note() { print -Pn '%F{cyan}==>%f ';    print -r -- "$1"; }
warn() { print -Pn '%F{yellow}[warn]%f ' >&2;  print -r -- "$1" >&2; }
die()  { print -Pn '%F{red}[error]%f ' >&2;    print -r -- "$1" >&2; exit 1; }

check_only=0
print_env=0
case "${1:-}" in
    -h|--help)
        # Printed from the header block, so the synopsis has one home and
        # cannot drift out of step with what the script accepts.
        # 由檔頭區塊印出，讓用法只有一個來源，不會與腳本實際接受的參數脫節。
        sed -n '2,12p' "$script_path" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    --check) check_only=1 ;;
    --print-env) print_env=1 ;;
    "") ;;
    *) die "usage: $(basename "$0") [--check|--print-env|--help]" ;;
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

    note "Xcode: $(xcodebuild -version 2>/dev/null | head -1) at $dir"
}

# ==============================================================================
# 2. An iOS Simulator SDK.
# ==============================================================================
require_sdk() {
    local sdk
    sdk="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)"
    [ -n "$sdk" ] || die "No iphonesimulator SDK. Install the iOS platform in Xcode."
    note "SDK: $(basename "$sdk")"
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

    note "Runtime: $(printf '%s' "$runtimes" | tail -1 | sed 's/ *(Ready)//')"
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
        note "Device: $DEVICE_NAME already exists"
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

    note "Creating device '$DEVICE_NAME' ($DEVICE_TYPE on ${runtime##*.})"
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

note "Ready. Device UDID: $udid"

cat <<EOF

$(printf '\033[32m')iOS build environment ready$(printf '\033[0m')

Build a test app for the simulator:

  sh testapp/compile.zsh -ios P11

Run it:

  xcrun simctl boot "$DEVICE_NAME"
  open -a Simulator

EOF
