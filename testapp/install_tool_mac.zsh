#!/usr/bin/env zsh
# Prepares a macOS host for building GtkBackend and for running the package's
# test suite.
#
#   zsh testapp/install_tool_mac.zsh              # check, install what is missing
#   zsh testapp/install_tool_mac.zsh --check      # report only, change nothing
#   zsh testapp/install_tool_mac.zsh --print-env  # print the values a test run needs
#   zsh testapp/install_tool_mac.zsh --test       # set up, then run the suite
#
# This is the macOS counterpart of install_tool_wsl.zsh. It is not about
# AppKitBackend, which needs nothing beyond Xcode, nor about the iOS Simulator,
# which install_tools_ios.zsh covers. It is about the two things that stop
# `swift test` from running on a Mac at all.
#
# 這是 install_tool_wsl.zsh 的 macOS 對應版本。它與 AppKitBackend 無關（後者除 Xcode 外
# 別無所需），也與 iOS 模擬器無關（那由 install_tools_ios.zsh 負責）。它處理的是「使
# `swift test` 在 Mac 上根本無法執行」的那兩件事。
#
# Everything here is idempotent, so re-running it is safe.
# 此處所有步驟皆為幂等，重複執行是安全的。
#
# What it deals with:
#
# - GTK 4 is not installed by default. Package.swift already names the remedy --
#   the CGtk system library declares `providers: [.brew(["gtk4"])]` -- so GTK on
#   macOS is intended, not a stretch. Without it GtkCHelpers cannot find
#   <gtk/gtk.h> and the whole package fails to configure.
#
# - libepoxy's headers are installed but not found, which looks like a missing
#   package and is not. gtk4.pc lists epoxy as a *private* requirement, so
#   `pkg-config --cflags gtk4` never mentions it; on Linux that costs nothing
#   because epoxy lands in /usr/include, which clang searches anyway. Homebrew
#   puts it in $(brew --prefix)/include, which clang does not search, and every
#   Homebrew .pc file points at Cellar paths rather than that directory. So
#   gtk_nv12_gl.c fails on `#include <epoxy/gl.h>` with the header sitting right
#   there. Passing `-Xcc -I$(brew --prefix)/include` is the fix, and it has to be
#   passed rather than installed.
#
# - `swift test` builds every target in the package, not just the test bundle
#   and what it imports. Two targets cannot compile for a macOS host at all:
#   WinUIBackend (swift-winui's CWinRT needs the Windows SDK's <wtypesbase.h>)
#   and UIKitBackend (UIKit has no macOS slice). SCUI_HOST_BACKENDS_ONLY=1 drops
#   both from the manifest; see the note beside that flag in Package.swift for
#   why it is opt-in rather than automatic.
#
# 它處理的問題：
#
# - GTK 4 預設未安裝。Package.swift 本身已指出解法——CGtk 系統程式庫宣告了
#   `providers: [.brew(["gtk4"])]`——因此在 macOS 上使用 GTK 是預期用法，並非勉強。
#   缺少它時 GtkCHelpers 找不到 <gtk/gtk.h>，整個套件連組態都無法完成。
#
# - libepoxy 的標頭檔已安裝卻找不到，看起來像套件缺失，實則不然。gtk4.pc 將 epoxy 列為
#   *private* requirement，因此 `pkg-config --cflags gtk4` 從不提及它；在 Linux 上這無關
#   痛癢，因為 epoxy 位於 clang 本就會搜尋的 /usr/include。Homebrew 則把它放在
#   $(brew --prefix)/include——clang 不搜尋該處，而每個 Homebrew 的 .pc 檔指向的都是
#   Cellar 路徑而非該目錄。於是 gtk_nv12_gl.c 會在 `#include <epoxy/gl.h>` 失敗，而標頭檔
#   就在那裡。解法是傳入 `-Xcc -I$(brew --prefix)/include`，且必須用「傳入」而非「安裝」。
#
# - `swift test` 會建置套件中的每一個 target，而非僅測試 bundle 及其 import 的部分。有兩個
#   target 在 macOS 主機上根本無法編譯：WinUIBackend（swift-winui 的 CWinRT 需要 Windows
#   SDK 的 <wtypesbase.h>）與 UIKitBackend（UIKit 沒有 macOS 切片）。SCUI_HOST_BACKENDS_ONLY=1
#   會將兩者自 manifest 中移除；其為何採 opt-in 而非自動，見 Package.swift 中該旗標旁的說明。
#
# One test fails afterwards, and it is not a regression:
#
#   "Ensure that a basic view has the expected dimensions under AppKitBackend"
#   expects ViewSize(92, 96) and gets ViewSize(102, 104).
#
# The numbers are AppKit's, not SwiftCrossUI's. That test lays out
# VStack { Button("Decrease"); Text("Count: 1"); Button("Increase") }.padding(),
# and on macOS 27 an NSButton with bezelStyle .regularSquare measures 82x24 for
# "Decrease" where the expectation was written against 72x20. The arithmetic
# closes exactly both ways: 82 + 10 + 10 = 102 wide, and 24 + 16 + 24 + 10 + 10
# (spacing) + 10 + 10 (padding) = 104 tall. The layout is doing the right thing
# with the sizes AppKit reports; the sizes changed underneath it. The test is
# upstream's and is skipped everywhere except macOS -- `#if canImport(AppKitBackend)`
# -- so no CI has ever caught this. The expectation is left alone here: editing
# it would make the suite pass on this machine and fail on an older one.
#
# 之後會有一個測試失敗，而那並非退步：
#
#   「Ensure that a basic view has the expected dimensions under AppKitBackend」
#   期望 ViewSize(92, 96)，實得 ViewSize(102, 104)。
#
# 這些數字屬於 AppKit，而非 SwiftCrossUI。該測試佈局的是
# VStack { Button("Decrease"); Text("Count: 1"); Button("Increase") }.padding()，
# 而在 macOS 27 上，bezelStyle 為 .regularSquare 的 NSButton 就「Decrease」而言量得 82x24，
# 當初撰寫期望值時則是 72x20。兩邊的算術都恰好吻合：寬 82 + 10 + 10 = 102；高
# 24 + 16 + 24 + 10 + 10（間距）+ 10 + 10（padding）= 104。佈局系統依 AppKit 回報的尺寸做出了
# 正確的結果，是尺寸在其底下改變了。該測試屬於 upstream，且除 macOS 外一律略過
# （`#if canImport(AppKitBackend)`），因此沒有任何 CI 曾經發現它。此處不更動該期望值：改了
# 會讓套件在這台機器上通過，卻在較舊的機器上失敗。

set -euo pipefail

# $0 inside a zsh function is the function's name, not the script, so the path
# is captured here at top level while it still means the file.
# zsh 中函式內的 $0 是函式名稱而非腳本本身，因此在頂層先捕捉路徑，此時它仍代表檔案。
script_path="${0:A}"
repo_root="${script_path:h:h}"

# Named `note`, not `log`: `log` belongs to the zsh/watch module, and defining a
# function over it makes zsh try to load that module. install_tools_ios.zsh
# carries the full account of how that fails.
# 取名 note 而非 log：`log` 屬於 zsh/watch 模組，覆寫它會使 zsh 嘗試載入該模組。
# 其失敗的完整經過記於 install_tools_ios.zsh。
note() { print -Pn '%F{cyan}==>%f ';         print -r -- "$1"; }
warn() { print -Pn '%F{yellow}[warn]%f ' >&2; print -r -- "$1" >&2; }
die()  { print -Pn '%F{red}[error]%f ' >&2;   print -r -- "$1" >&2; exit 1; }

check_only=0
print_env=0
run_tests=0
case "${1:-}" in
    -h|--help)
        # Printed from the header block, so the synopsis has one home and cannot
        # drift out of step with what the script accepts.
        # 由檔頭區塊印出，讓用法只有一個來源，不會與腳本實際接受的參數脫節。
        sed -n '2,9p' "$script_path" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    --check) check_only=1 ;;
    --print-env) print_env=1 ;;
    --test) run_tests=1 ;;
    "") ;;
    *) die "usage: $(basename "$0") [--check|--print-env|--test|--help]" ;;
esac

[ "$(uname -s)" = "Darwin" ] || die "This script is for macOS. On WSL or Linux use install_tool_wsl.zsh."

# ==============================================================================
# 1. Homebrew, which is how Package.swift says to get GTK.
# ==============================================================================
require_brew() {
    command -v brew >/dev/null 2>&1 \
        || die "Homebrew is not installed. See https://brew.sh -- Package.swift names brew as the provider for gtk4."
    brew_prefix="$(brew --prefix)"
    note "Homebrew: $(brew --version | head -1) at $brew_prefix"
}

# ==============================================================================
# 2. GTK 4 and libepoxy.
#
# libepoxy is named explicitly even though gtk4 pulls it in, so that --check can
# say which of the two is missing rather than reporting "gtk4" for either.
# 即使 gtk4 會一併帶入 libepoxy，此處仍明確指名，讓 --check 能指出兩者中缺的是哪一個，
# 而非一律回報「gtk4」。
# ==============================================================================
ensure_packages() {
    local missing=()
    local formula
    for formula in gtk4 libepoxy; do
        brew list --formula "$formula" >/dev/null 2>&1 || missing+=("$formula")
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        note "Installed: gtk4 $(brew list --versions gtk4 | awk '{print $2}'), libepoxy $(brew list --versions libepoxy | awk '{print $2}')"
        return
    fi

    if [ "$check_only" -eq 1 ]; then
        warn "Missing: ${missing[*]}; run without --check to install"
        return
    fi

    note "Installing: ${missing[*]}"
    brew install "${missing[@]}"
}

# ==============================================================================
# 3. pkg-config can see gtk4, which is what SwiftPM actually asks.
#
# Checked separately from the brew install: a formula can be present while
# pkg-config cannot find its .pc file, and SwiftPM reports that as "you may be
# able to install gtk4 using your system-packager" -- advice that is already
# followed, and so reads as a dead end.
# 與 brew 安裝分開檢查：formula 可能已存在，pkg-config 卻找不到其 .pc 檔；SwiftPM 對此的
# 回報是「you may be able to install gtk4 using your system-packager」——一個已經照做過的
# 建議，因而讀起來像是死路一條。
# ==============================================================================
verify_pkgconfig() {
    command -v pkg-config >/dev/null 2>&1 || die "pkg-config is not on PATH; SwiftPM needs it to find gtk4."
    pkg-config --exists gtk4 \
        || die "pkg-config cannot find gtk4 even though the formula is installed. Check PKG_CONFIG_PATH."
    note "pkg-config: gtk4 $(pkg-config --modversion gtk4)"
}

# ==============================================================================
# 4. The epoxy header is where the -I flag says it is.
#
# Verified by looking rather than assumed, because this is the one piece the
# flag has to compensate for; if Homebrew ever links it elsewhere the flag is
# silently useless and the failure resurfaces as a missing header.
# 以實際查看而非假設來驗證，因為這正是該旗標所要彌補的環節；若 Homebrew 日後改連結到別處，
# 該旗標會靜默失效，而問題會以「標頭檔找不到」的形式重新浮現。
# ==============================================================================
verify_epoxy_header() {
    local header="$brew_prefix/include/epoxy/gl.h"
    [ -f "$header" ] || die "$header does not exist, so -I$brew_prefix/include will not help. Try 'brew link libepoxy'."
    note "Header: $header"
}

if [ "$print_env" -eq 1 ]; then
    require_brew >/dev/null
    printf 'SCUI_HOST_BACKENDS_ONLY=1\n'
    printf 'SCUI_TEST_CFLAGS=-I%s/include\n' "$brew_prefix"
    exit 0
fi

require_brew
ensure_packages
verify_pkgconfig
verify_epoxy_header

test_command=(env SCUI_HOST_BACKENDS_ONLY=1 swift test -Xcc "-I$brew_prefix/include")

if [ "$run_tests" -eq 1 ]; then
    note "Running: ${test_command[*]}"
    cd "$repo_root"
    # Not exec'd. The suite is expected to report one failure (the AppKit
    # dimensions test explained in the header), so the reminder below has to be
    # printed after it, where it will be read.
    # 不使用 exec。測試套件預期會回報一項失敗（檔頭說明的 AppKit 尺寸測試），因此下方的
    # 提醒必須印在其後，才會被看見。
    "${test_command[@]}" || true
    print
    note "A failing \"basic view has the expected dimensions\" test is expected here; see the header of this script."
    exit 0
fi

cat <<EOF

$(print -P '%F{green}macOS test environment ready%f')

Run the package test suite:

  ${test_command[*]}

Build a GTK app on this Mac:

  swift build -Xcc -I$brew_prefix/include

One failure is expected in the suite -- "basic view has the expected
dimensions" -- and is an AppKit metrics change, not a regression. Run this
script with --help for the arithmetic.

EOF
