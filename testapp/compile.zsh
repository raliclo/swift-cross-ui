#!/usr/bin/env zsh
set -euo pipefail

# zsh does not split unquoted scalar expansions by default, while this POSIX
# script uses whitespace-delimited app name lists below.
if [ -n "${ZSH_VERSION:-}" ]; then
    setopt SH_WORD_SPLIT
fi

host_uname="$(uname -s 2>/dev/null || printf unknown)"

windows_path() {
    case "$host_uname" in
        MINGW*|MSYS*|CYGWIN*) ;;
        *)
            printf '%s\n' "$1"
            return
            ;;
    esac

    case "$1" in
        /?/*)
            drive="$(printf '%s' "$1" | cut -c 2 | tr '[:lower:]' '[:upper:]')"
            rest="$(printf '%s' "$1" | cut -c 4-)"
            printf '%s:/%s\n' "$drive" "$rest"
            ;;
        /cygdrive/?/*)
            drive="$(printf '%s' "$1" | cut -c 11 | tr '[:lower:]' '[:upper:]')"
            rest="$(printf '%s' "$1" | cut -c 13-)"
            printf '%s:/%s\n' "$drive" "$rest"
            ;;
        \\cygdrive\\?\\*)
            drive="$(printf '%s' "$1" | cut -c 12 | tr '[:lower:]' '[:upper:]')"
            rest="$(printf '%s' "$1" | cut -c 14- | tr '\\' '/')"
            printf '%s:/%s\n' "$drive" "$rest"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

script_dir="$(windows_path "$(cd "$(dirname "$0")" && pwd)")"
repo_root="$(windows_path "$(cd "$script_dir/.." && pwd)")"
output_dir="$(windows_path "$script_dir/output")"
# Captured at TOP LEVEL because `$0` inside a zsh function is the FUNCTION's
# name -- FUNCTION_ARGZERO is on by default. Measured 2026-09-07 while testing
# the build manifest: a warning meant to read `run zsh .../compile.zsh
# --manifest` came out as `run zsh manifest_summary --manifest`, an instruction
# that cannot be followed and looks like a typo rather than a shell rule.
# 於「最上層」擷取，因為 `$0` 在 zsh 函式內是「該函式的名稱」——FUNCTION_ARGZERO 預設為開。
# 2026-09-07 於測試建置 manifest 時實測：一則本該印出 `run zsh .../compile.zsh --manifest`
# 的警告，印成了 `run zsh manifest_summary --manifest`；那是一條無法照做的指示，而且看起來
# 像打字錯誤，而不像一條 shell 規則。
script_self="$script_dir/$(basename "$0")"
# Android builds use the project volume by default, matching
# testapp/install_tools_android.zsh. Explicit ANDROID_HOME remains the first
# choice; ANDROID_SDK_ROOT is accepted as the equivalent spelling.
# Android build 預設使用 project volume，與 testapp/install_tools_android.zsh 一致；若使用者明確
# 設定 ANDROID_HOME，仍優先使用它；ANDROID_SDK_ROOT 則視為相同設定。
android_sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${repo_root:h}/.android-sdk}}"
android_triple="${ANDROID_TRIPLE:-aarch64-unknown-linux-android31}"
# `native`, not the default `swiftbuild`, and only for Android.
#
# swiftbuild rejects this package outright:
#
#   error: Swift package product 'SwiftJavaJNICore-product' is linked as a
#   static library by 'P12-product' and 'SwiftJava-product'. This will result
#   in duplication of library code.
#
# Six of those, and the build stops. It is not caused by anything in this tree
# -- the same errors appear at API 28 and at 31, so raising minSDK did not
# introduce them -- and it is not about Android either; it is swiftbuild
# refusing a static-linkage shape in swift-java that the native build system
# accepts. `native` is deprecated, so this is a workaround with an expiry date:
# when swiftbuild stops rejecting it, or swift-java changes shape, drop this.
#
# 使用 `native` 而非預設的 `swiftbuild`，且僅限 Android。
#
# swiftbuild 會直接拒絕這個 package，錯誤如上方英文所示，共六條，建置隨即停止。這並非由本樹中的
# 任何東西造成——在 API 28 與 31 下都會出現同樣的錯誤，因此調升 minSDK 並沒有引入它們——也與
# Android 無關；那是 swiftbuild 拒絕接受 swift-java 中某種靜態連結形狀，而 native 建置系統接受它。
# `native` 已標記為 deprecated，因此這是一個有到期日的權宜之計：待 swiftbuild 不再拒絕它，或
# swift-java 改變形狀時，即可移除。
android_build_system="${ANDROID_BUILD_SYSTEM:-native}"
android_ndk_version="${ANDROID_NDK_VERSION:-27.0.12077973}"
android_ndk_home="${ANDROID_NDK_HOME:-$android_sdk_root/ndk/$android_ndk_version}"
# Set after the flags are parsed, because -gtk4 needs its own tree. See the
# note there.
# 於旗標解析之後設定，因為 -gtk4 需要自己的目錄樹，理由見該處說明。
compile_work_dir=""
package_dir=""
sources_root=""

# An Android build needs a toolchain matching the Android SDK, and on a Mac
# `swift` is not it.
#
# Measured 2026-09-02: `swift` resolves to Xcode's 6.4, the installed Android
# SDK is 6.3.3, and the build fails with
#
#   error: module compiled with Swift 6.3.3 cannot be imported by the
#   Swift 6.4 compiler
#
# on every module that imports Foundation. This is not the SDK being out of
# date. swift.org's release list has android-sdk from 6.3 onward and stops at
# 6.3.3 (2026-06-29); there is no 6.4 Android SDK because 6.4 is not a
# published release -- Xcode ships ahead of that train. So the host compiler is
# the thing that is wrong for this job, not the SDK.
#
# Set SWIFT_BIN to a matching toolchain for Android, for example
#   SWIFT_BIN=~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift
#
# Android 建置需要與 Android SDK 相符的 toolchain，而在 Mac 上 `swift` 並不是它。
#
# 2026-09-02 實測：`swift` 解析到 Xcode 的 6.4，已安裝的 Android SDK 為 6.3.3，於是每一個 import
# Foundation 的 module 都以上方英文所示的錯誤失敗。這不是 SDK 過舊。swift.org 的 release 清單自
# 6.3 起才有 android-sdk，且停在 6.3.3（2026-06-29）；不存在 6.4 的 Android SDK，因為 6.4 並非
# 已發布的 release——Xcode 走在那條發布列車的前面。因此對這項工作而言，不對的是主機編譯器，而非 SDK。
#
# 請為 Android 將 SWIFT_BIN 指向相符的 toolchain，範例見上方英文。
swift_bin="${SWIFT_BIN:-swift}"
# Test apps default to release so GUI startup and interaction latency reflect
# normal usage. App-specific diagnostics should be controlled with flags such
# as --debug instead of relying on unoptimized debug builds.
#
# The default is the same on every platform. If a Windows release build is too
# expensive for an exploratory run, set BUILD_CONFIG=debug explicitly so the
# result cannot be mistaken for a normal latency measurement.
#
# 所有平台採用相同預設。若 Windows release build 對探索性執行過於昂貴，請明確設定
# BUILD_CONFIG=debug，避免其結果被誤讀為一般 latency 量測。
if [ -n "${BUILD_CONFIG:-}" ]; then
    build_config="$BUILD_CONFIG"
else
    build_config="release"
fi
needs_image_formats=0
target_platform="host"

# -gtk4 forces GtkBackend everywhere, including Windows, where WinUIBackend is
# otherwise the default. It is opt-in rather than automatic because P0-P16 are
# WinUI repro apps: switching them silently would make them reproduce nothing.
# WinUIBackend stays the baseline.
#
# There is no preference order to rely on. An earlier version of this comment
# claimed DefaultBackend already prefers Gtk over WinUI and that the flag merely
# made GtkBackend importable; that was wrong, and believing it is what made the
# flag ineffective for two full builds. Package.swift hard-codes one backend per
# platform -- WinUIBackend on Windows, GtkBackend on Linux -- so the flag has to
# do the selecting itself, which is what SCUI_DEFAULT_BACKEND below is for.
# -gtk4 會在所有平台強制使用 GtkBackend，包含原本預設為 WinUIBackend 的 Windows。此為
# 選擇性加入而非自動，因為 P0-P16 是 WinUI 的重現 app：若靜默切換，它們將什麼也重現不了。
# WinUIBackend 維持為 baseline。
#
# 並不存在可供依賴的優先順序。本註解的舊版本宣稱 DefaultBackend 本來就把 Gtk 排在 WinUI
# 之前、而本旗標只是讓 GtkBackend 可被 import；那是錯的，且正是這個誤信讓該旗標連續兩次
# 完整建置都未生效。Package.swift 是依平台寫死單一 backend——Windows 為 WinUIBackend、
# Linux 為 GtkBackend——因此旗標必須自行完成選擇，那正是下方 SCUI_DEFAULT_BACKEND 的用途。
force_gtk4=0

# -ios switches to an iOS Simulator build. It cannot go through `swift build`:
# passing an iOS SDK with -Xswiftc applies it to every target, including
# SwiftCrossUIMacrosPlugin, which is a compile-time tool that has to be built
# for the host, and the link then fails. xcodebuild distinguishes the two, so
# that is what the iOS path uses.
# -ios 會切換為 iOS 模擬器建置。此路徑無法使用 `swift build`：以 -Xswiftc 傳入
# iOS SDK 會套用到所有 target，包含必須為主機建置的編譯期工具
# SwiftCrossUIMacrosPlugin，連結因而失敗。xcodebuild 能區分兩者，故 iOS 路徑改用它。
# Answered before the toolchain is touched. A full build is minutes on Windows,
# so a wrong flag should cost a line of output rather than a compile.
# 在動用工具鏈之前先回答。Windows 上一次完整建置要數分鐘，打錯旗標應該只花一行輸出
# 的代價，而不是一次編譯。
# Matched anywhere in the arguments, not just first. `compile.zsh -gtk4 --help`
# used to fall past this, set up the GTK toolchain and then treat --help as an
# app name; the flag has to answer wherever it appears.
# 在所有引數中比對，而非僅限第一個。`compile.zsh -gtk4 --help` 過去會略過此處、先完成
# GTK 工具鏈設定，再把 --help 當成 app 名稱；此旗標無論出現在何處都必須先回答。
for arg in "$@"; do
    case "$arg" in -h|--help) set -- --help; break ;; esac
done

case "${1:-}" in
    -h|--help)
        printf '%s\n' \
            "Usage: compile.zsh [-ios|-android] [-gtk4] [P0 P1 ... Pn]" \
            "用法：compile.zsh [-ios|-android] [-gtk4] [P0 P1 ... Pn]" \
            "" \
            "  -ios   Build for the iOS Simulator via xcodebuild." \
            "  -ios   透過 xcodebuild 為 iOS 模擬器建置。" \
            "  -gtk4  Force GtkBackend on every platform, Windows included." \
            "         Needs GTK 4; on Windows run install_gtk4_windows.zsh first." \
            "  -gtk4  在所有平台強制使用 GtkBackend，包含 Windows。" \
            "         需要 GTK 4；Windows 上請先執行 install_gtk4_windows.zsh。" \
            "  -android  Build for Android with the Swift Android SDK." \
            "  -android  使用 Swift Android SDK 建置 Android。" \
            "  --manifest  Audit output/build-manifest.csv2 against output/ and" \
            "              exit non-zero on any disagreement. Builds nothing." \
            "              Add --prune to delete rows whose file is gone." \
            "  --manifest  以 output/ 稽核 output/build-manifest.csv2，只要有任何" \
            "              不一致就以非零狀態結束。不會建置任何東西。" \
            "              加上 --prune 可刪除「檔案已不存在」的資料列。" \
            "" \
            "With no app names, every P*.swift is built." \
            "未指定 app 名稱時，會建置所有 P*.swift。" \
            "Release by default; BUILD_CONFIG=debug for an unoptimised build." \
            "預設 release；需要未最佳化 build 時設定 BUILD_CONFIG=debug。" \
            "SCUI_DEBUG=1 by default, so -actionfile and --debug work in the" \
            "release build this produces. SCUI_DEBUG=0 builds without them." \
            "The two are independent: BUILD_CONFIG picks the optimiser," \
            "SCUI_DEBUG decides whether a replay exists in the binary at all." \
            "SCUI_DEBUG 預設為 1，因此此處產出的 release 建置中 -actionfile 與" \
            "--debug 都可用；SCUI_DEBUG=0 則建置為不含它們的版本。" \
            "兩者互相獨立：BUILD_CONFIG 決定最佳化，SCUI_DEBUG 決定重放是否" \
            "存在於執行檔之中。" \
            "Every artefact copied into output/ gets a row in" \
            "output/build-manifest.csv2 saying which configuration produced it." \
            "每一個複製進 output/ 的產物都會在 output/build-manifest.csv2 得到一列，" \
            "記下它是由哪一種組態產生的。"
        exit 0
        ;;
esac

# ---------------------------------------------------------------------------
# The build manifest: what this script produced, and how it produced it.
#
# output/ is a flat directory of binaries and nothing in a binary says which
# configuration built it. That is not a theoretical gap. Measured 2026-09-07:
# output/ held 43 `-gtk4.exe` files in two size clusters, 56-57 MB (33 files)
# and 80 MB (10 files). The todo list recorded ONE debug binary; there were ten.
# Three indirect checks were tried and all three had no discriminating power --
# an embedded build-config path (0 hits in both clusters), the string
# `Sources/SwiftCrossUI` (0 hits in both), and `.swift` string density (734 vs
# 664, no separation). "The check does not fire" is indistinguishable from "the
# files are the same". What settled it was rebuilding P7 at the default
# configuration and watching it move 80,582,656 -> 57,024,000 bytes: a
# 23-minute build spent to answer a question one recorded line answers free.
#
# So the value is written down at the moment it is known. This script already
# HAS the configuration -- `$build_config`, printed in its own --help -- so
# nothing here is derived or inferred.
#
# `.csv2` and `csv2`, because that is this project's format for machine-read
# records: two header rows, English then Traditional Chinese, one record per
# line. Never read or written with awk -F, / cut -d, / any other text tool;
# `csv2 -get` and `csv2 -contains` cannot mis-split a field, and that mistake
# has already been made twice in this repository.
#
# The manifest lives beside the artefacts it describes, so it is untracked for
# the same reason they are.
#
# ---------------------------------------------------------------------------
# 建置 manifest：本腳本產出了什麼，以及是怎麼產出的。
#
# output/ 是一個平坦的執行檔目錄，而執行檔本身不會說出自己是用哪一種組態建出來的。這並非
# 理論上的缺口。2026-09-07 實測：output/ 中有 43 個 `-gtk4.exe`，分成兩個尺寸叢集——
# 56-57 MB（33 個）與 80 MB（10 個）。待辦清單只記了「一個」debug 執行檔，實際上有十個。
# 當時嘗試了三種間接檢查，三種都不具鑑別力：內嵌的 build-config 路徑（兩邊皆 0 次命中）、
# 字串 `Sources/SwiftCrossUI`（兩邊皆 0）、以及 `.swift` 字串密度（734 對 664，無法分離）。
# 「檢查沒有觸發」與「兩邊檔案相同」看起來完全一樣。真正定案的方法是以預設組態重建 P7，
# 看著它從 80,582,656 變成 57,024,000 位元組：為了回答一個「寫下一行就免費得到答案」的問題，
# 付出了 23 分鐘的建置。
#
# 因此，在知道那個值的當下就把它寫下來。本腳本本來就「持有」該組態——`$build_config`，它
# 自己的 --help 也印出這件事——所以此處沒有任何東西是推導或猜測出來的。
#
# 採用 `.csv2` 與 `csv2`，因為那是本專案供機器讀取的紀錄格式：兩列標頭，先英文後繁體中文，
# 一筆紀錄一行。絕不以 awk -F, / cut -d, 或任何文字工具讀寫它；`csv2 -get` 與
# `csv2 -contains` 不可能把欄位切錯，而那個錯誤在本 repo 已經犯過兩次。
#
# manifest 與它所描述的產物放在一起，因此它未被納入版控的理由，與那些產物完全相同。
manifest_path="$output_dir/build-manifest.csv2"

case "$host_uname" in
    MINGW*|MSYS*|CYGWIN*) manifest_host_os="windows" ;;
    Darwin) manifest_host_os="macos" ;;
    Linux) manifest_host_os="linux" ;;
    *) manifest_host_os="unknown" ;;
esac

# Every artefact name this script can produce that actually exists on disk.
#
# Derived from testapp/P*.swift and the four naming rules further down, rather
# than from a glob over output/. A glob would be wrong here: output/ also holds
# run logs, a WebView2 user-data directory, Microsoft.Graphics.Canvas.dll and
# whatever else a test run dropped, and calling those "unrecorded artefacts"
# would make the audit cry wolf until nobody read it.
#
# 本腳本可能產出、且確實存在於磁碟上的每一個產物名稱。
#
# 由 testapp/P*.swift 與下方四條命名規則推導，而不是對 output/ 做 glob。在此 glob 是錯的：
# output/ 裡還有執行 log、WebView2 的使用者資料目錄、Microsoft.Graphics.Canvas.dll，以及
# 測試執行留下的其他東西；把那些叫做「未記錄的產物」會讓稽核一直誤報，直到沒有人再看它。
manifest_artefact_files() {
    for manifest_src in "$script_dir"/P*.swift; do
        [ -f "$manifest_src" ] || continue
        manifest_stem="$(basename "$manifest_src")"
        manifest_stem="${manifest_stem%.swift}"
        for manifest_candidate in \
            "$manifest_stem" \
            "${manifest_stem}-gtk4.exe" \
            "${manifest_stem}-WinUI.exe" \
            "${manifest_stem}-android" \
            "${manifest_stem}-ios.app"
        do
            [ -e "$output_dir/$manifest_candidate" ] || continue
            printf '%s\n' "$manifest_candidate"
        done
    done
}

# An iOS artefact is a .app DIRECTORY, so `wc -c` on the name is not its size.
# iOS 的產物是一個 .app「目錄」，因此對名稱下 `wc -c` 並不是它的大小。
manifest_bytes() {
    if [ -d "$1" ]; then
        find "$1" -type f -exec cat {} + | wc -c | tr -d ' '
    else
        wc -c < "$1" | tr -d ' '
    fi
}

manifest_have_csv2() {
    command -v csv2 >/dev/null 2>&1
}

manifest_ensure() {
    if [ -f "$manifest_path" ]; then
        return 0
    fi
    printf '%s\n' \
        'file,app,platform,backend,config,scui_debug,built,bytes' \
        '檔案,app,平台,backend,組態,scui_debug,建置時間,位元組' \
        | csv2 -r -si --headers 2 -t -o "$manifest_path"
}

manifest_record_count() {
    if [ ! -f "$manifest_path" ]; then
        printf '0\n'
        return 0
    fi
    csv2 -r -i "$manifest_path" | wc -l | tr -d ' '
}

# Upsert one artefact: drop whatever row named this file, then append the new
# one. Rewriting rather than editing in place is what keeps a rebuild honest --
# a release build over a debug build has to change `config`, `built` and
# `bytes` together, and one -append does all three.
#
# 覆寫式寫入一個產物：先移除指名該檔案的既有資料列，再附加新的一列。之所以重寫而非就地
# 修改，是為了讓「重建」保持誠實——release 蓋掉 debug 時，`config`、`built` 與 `bytes`
# 必須一起改變，而一次 -append 就同時完成三者。
manifest_record() {
    manifest_file="$1"
    manifest_app_col="$2"
    manifest_platform_col="$3"
    manifest_backend_col="$4"

    if ! manifest_have_csv2; then
        printf '    manifest: csv2 is not on PATH, so %s was not recorded\n' \
            "$manifest_file" >&2
        printf '    manifest：csv2 不在 PATH 上，因此未記錄 %s\n' \
            "$manifest_file" >&2
        return 0
    fi

    # `if ! manifest_ensure` rather than a bare call, for the same reason the
    # append below is guarded: errexit is suspended inside a condition, so a
    # csv2 that cannot create the file reports here instead of killing the run.
    # 以 `if ! manifest_ensure` 取代直接呼叫，理由與下方 append 加防護相同：條件式之內
    # errexit 會被暫停，因此無法建立檔案的 csv2 會在此回報，而不是直接殺掉整輪執行。
    if ! manifest_ensure; then
        printf '    manifest: could not create %s\n' "$manifest_path" >&2
        printf '    manifest：無法建立 %s\n' "$manifest_path" >&2
        return 0
    fi

    # -contains matches SUBSTRINGS, so every hit is re-checked with -get for an
    # exact cell value before anything is deleted. Deleting on a substring hit
    # would take out P15-gtk4.exe's row while recording P15-DARK-gtk4.exe.
    #
    # Collected in DESCENDING record order, because -delete renumbers: deleting
    # record 2 first would make the old record 5 into record 4.
    #
    # -contains 比對的是「子字串」，因此在刪除任何東西之前，每一個命中都先以 -get 取出
    # 儲存格原值做精確比對。若照子字串命中就刪，記錄 P15-DARK-gtk4.exe 時會順手刪掉
    # P15-gtk4.exe 的資料列。
    #
    # 以「遞減」的紀錄號收集，因為 -delete 會重新編號：先刪第 2 筆，原本的第 5 筆就變成第 4 筆。
    manifest_hits="$(csv2 -r -i "$manifest_path" -contains "$manifest_file" \
        --search-column file 2>/dev/null || true)"
    manifest_victims=""
    while IFS= read -r manifest_hit; do
        [ -n "$manifest_hit" ] || continue
        manifest_rec="${manifest_hit%%:*}"
        if [ "$(csv2 -i "$manifest_path" -get "${manifest_rec}:file")" = "$manifest_file" ]; then
            manifest_victims="$manifest_rec $manifest_victims"
        fi
    done <<EOF_MANIFEST_HITS
$manifest_hits
EOF_MANIFEST_HITS
    for manifest_rec in $manifest_victims; do
        if ! csv2 -i "$manifest_path" --in-place -delete "$manifest_rec"; then
            printf '    manifest: could not drop the old row for %s; it will now appear twice\n' \
                "$manifest_file" >&2
            printf '    manifest：無法移除 %s 的舊資料列，它接下來會出現兩次\n' \
                "$manifest_file" >&2
        fi
    done

    # Loud, but not fatal. `set -e` is on, so an unguarded csv2 failure here
    # would abort a build that had already SUCCEEDED -- and take the remaining
    # apps of a 45-app sweep with it, for a bookkeeping error. The row is
    # missing either way; manifest_summary's count check at the end of the run
    # is what stops that going quiet.
    # 出聲，但不致命。本腳本開了 `set -e`，因此此處若不加防護，csv2 一失敗就會中止一次
    # 「已經成功」的建置——並且為了一個記帳錯誤，把 45 支 app 的 sweep 剩下的部分一起帶走。
    # 無論如何那一列都會缺席；真正讓它不至於悄悄過去的，是執行結束時 manifest_summary 的
    # 數目檢查。
    if csv2 -i "$manifest_path" --in-place -append "$(printf '%s,%s,%s,%s,%s,%s,%s,%s' \
        "$manifest_file" \
        "$manifest_app_col" \
        "$manifest_platform_col" \
        "$manifest_backend_col" \
        "$build_config" \
        "${SCUI_DEBUG:-0}" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$(manifest_bytes "$output_dir/$manifest_file")")"
    then
        printf '    manifest: %s %s %s\n' \
            "$manifest_file" "$manifest_backend_col" "$build_config"
    else
        printf '    manifest: FAILED to record %s -- the manifest is now short a row\n' \
            "$manifest_file" >&2
        printf '    manifest：記錄 %s 失敗——manifest 現在少了一列\n' \
            "$manifest_file" >&2
    fi
}

# The three ways the manifest and the directory can disagree, and what each one
# means. None of them is silently accepted; a manifest that can disagree with
# its directory and not say so is the same defect as the one it exists to fix.
#
#   unrecorded  a file in output/ with no row. It was built before this
#               manifest existed, or copied in by hand. Its configuration is
#               genuinely unknown -- rebuild it, and do not guess from bytes.
#   orphan      a row whose file is gone. Deleted outside this script. --prune
#               removes the row; without it the row is only reported, because
#               a read-only audit that mutates is not one.
#   changed     the file exists but is not the size the row records. Something
#               other than compile.zsh replaced it, so the row's config and
#               timestamp describe a different binary. Never repaired
#               automatically: which side is right is a judgement, reporting
#               the disagreement is not.
#
# Exits non-zero on any of the three, so this is usable as a preflight.
#
# manifest 與目錄之間可能不一致的三種情形，以及各自的意義。三者都不會被靜默接受；一份能與
# 自己的目錄相左卻不出聲的 manifest，和它要修掉的那個缺陷是同一類。
#
#   unrecorded  output/ 中有檔案但沒有對應資料列。它建於本 manifest 出現之前，或是被手動
#               複製進來。它的組態是真的未知——請重建它，不要從位元組數去猜。
#   orphan      有資料列但檔案已不存在。它在本腳本之外被刪除。--prune 會移除該列；不加時
#               只回報，因為「會改動東西的唯讀稽核」不叫唯讀稽核。
#   changed     檔案存在，但大小與資料列所記不同。有 compile.zsh 以外的東西換掉了它，因此
#               該列的組態與時間戳描述的是另一個執行檔。絕不自動修復：哪一邊才對是判斷，
#               而回報這個不一致不是。
#
# 三者任一發生即以非零狀態結束，因此它可以當作前置檢查使用。
manifest_audit() {
    manifest_do_prune="${1:-0}"
    manifest_problems=0
    manifest_seen=""

    if ! manifest_have_csv2; then
        printf 'csv2 is not on PATH; the manifest cannot be audited\n' >&2
        printf 'csv2 不在 PATH 上，無法稽核 manifest\n' >&2
        return 2
    fi

    manifest_disk="$(manifest_artefact_files)"

    manifest_rows="$(manifest_record_count)"
    manifest_orphans=""
    manifest_n=1
    while [ "$manifest_n" -le "$manifest_rows" ]; do
        manifest_row_file="$(csv2 -i "$manifest_path" -get "${manifest_n}:file")"
        manifest_seen="$manifest_seen $manifest_row_file"
        if [ ! -e "$output_dir/$manifest_row_file" ]; then
            printf '%-11s %-28s %s\n' 'orphan' "$manifest_row_file" \
                'row has no file in output/'
            manifest_orphans="$manifest_n $manifest_orphans"
            manifest_problems=$((manifest_problems + 1))
        else
            manifest_row_bytes="$(csv2 -i "$manifest_path" -get "${manifest_n}:bytes")"
            manifest_now_bytes="$(manifest_bytes "$output_dir/$manifest_row_file")"
            if [ "$manifest_row_bytes" != "$manifest_now_bytes" ]; then
                printf '%-11s %-28s %s\n' 'changed' "$manifest_row_file" \
                    "row says $manifest_row_bytes bytes, file is $manifest_now_bytes"
                manifest_problems=$((manifest_problems + 1))
            fi
        fi
        manifest_n=$((manifest_n + 1))
    done

    while IFS= read -r manifest_disk_file; do
        [ -n "$manifest_disk_file" ] || continue
        case " $manifest_seen " in
            *" $manifest_disk_file "*) continue ;;
        esac
        printf '%-11s %-28s %s\n' 'unrecorded' "$manifest_disk_file" \
            'file in output/ has no row -- rebuild it to learn its configuration'
        manifest_problems=$((manifest_problems + 1))
    done <<EOF_MANIFEST_DISK
$manifest_disk
EOF_MANIFEST_DISK

    if [ "$manifest_do_prune" -eq 1 ] && [ -n "$manifest_orphans" ]; then
        for manifest_rec in $manifest_orphans; do
            csv2 -i "$manifest_path" --in-place -delete "$manifest_rec"
        done
        printf 'pruned %s orphan row(s)\n' "$(printf '%s\n' $manifest_orphans | wc -l | tr -d ' ')"
    fi

    if [ "$manifest_problems" -eq 0 ]; then
        printf '%s: %s row(s), consistent with %s\n' \
            "$manifest_path" "$manifest_rows" "$output_dir"
        return 0
    fi
    printf '%s disagreement(s); see above\n' "$manifest_problems" >&2
    return 1
}

# The cheap end-of-build check: record count against artefact count.
#
# NOT the full audit, which costs two csv2 calls per row -- about 130 ms each
# on this machine, so twelve seconds on a 45-row manifest. A warm incremental
# build of one app takes six seconds, and tripling that to re-derive something
# the build just wrote is the wrong trade. Every row this script writes is
# written from a file it has just copied, so for the counts to agree while the
# contents do not, someone must have deleted one artefact and added another
# between two builds. `--manifest` is there for when that is worth ruling out.
#
# 便宜的建置後檢查：資料列數對產物檔數。
#
# 這不是完整稽核；完整稽核每列要花兩次 csv2 呼叫——本機每次約 130 毫秒，45 列就是十二秒。
# 單一 app 的熱增量建置只要六秒，為了重新推導出建置剛剛才寫下的東西而讓它變成三倍，是不划算
# 的交換。本腳本寫下的每一列，都來自它剛剛複製過的檔案；因此若數目相符而內容不符，代表有人
# 在兩次建置之間刪掉了一個產物又加進了另一個。要排除那種情況時，`--manifest` 就在那裡。
manifest_summary() {
    if ! manifest_have_csv2; then
        return 0
    fi
    manifest_disk_count="$(manifest_artefact_files | wc -l | tr -d ' ')"
    manifest_row_total="$(manifest_record_count)"
    if [ "$manifest_disk_count" != "$manifest_row_total" ]; then
        printf 'manifest: %s artefact(s) in output/, %s row(s) in %s\n' \
            "$manifest_disk_count" "$manifest_row_total" "$manifest_path" >&2
        printf 'manifest: run `zsh %s --manifest` to see which disagree\n' \
            "$script_self" >&2
        printf 'manifest：output/ 有 %s 個產物，%s 有 %s 列\n' \
            "$manifest_disk_count" "$manifest_path" "$manifest_row_total" >&2
        printf 'manifest：執行 `zsh %s --manifest` 可看出是哪些不一致\n' "$script_self" >&2
    fi
}

# Answered before the toolchain is touched, for the same reason --help is: an
# audit reads two directories and must not cost a GTK probe or a compile.
# 與 --help 同理，在動用工具鏈之前先回答：一次稽核只讀兩個目錄，不該付出 GTK 探測或
# 一次編譯的代價。
manifest_only=0
manifest_prune=0
for arg in "$@"; do
    case "$arg" in
        --manifest) manifest_only=1 ;;
        --prune) manifest_prune=1 ;;
    esac
done
if [ "$manifest_only" -eq 1 ]; then
    # `|| manifest_status=$?`, not a bare call: `set -e` is on, and a bare call
    # returning 1 would exit here before the status could be forwarded -- which
    # happens to give the right code for a disagreement and the wrong one for
    # "csv2 is missing", the case worth telling apart.
    # 使用 `|| manifest_status=$?` 而非直接呼叫：本腳本開了 `set -e`，直接呼叫若回傳 1 會
    # 就地結束、來不及轉交狀態碼——那對「有不一致」剛好給對，對「csv2 不存在」則給錯，而
    # 那正是值得分辨的一種。
    manifest_status=0
    manifest_audit "$manifest_prune" || manifest_status=$?
    exit "$manifest_status"
fi
if [ "$manifest_prune" -eq 1 ]; then
    # Refused rather than ignored. Falling through would leave --prune in the
    # app-name list and the run would stop on `Missing source file: --prune`,
    # which points at the wrong thing.
    # 拒絕，而不是忽略。若讓它掉下去，--prune 會留在 app 名稱清單中，該次執行會以
    # `Missing source file: --prune` 中止，而那個訊息指向的是錯的東西。
    printf -- '--prune only means something with --manifest\n' >&2
    printf -- '--prune 只有與 --manifest 併用才有意義\n' >&2
    exit 1
fi

remaining_args=""
saw_flag=0
for arg in "$@"; do
    case "$arg" in
        -ios) target_platform="ios"; saw_flag=1 ;;
        -android) target_platform="android"; saw_flag=1 ;;
        -gtk4) force_gtk4=1; saw_flag=1 ;;
        *) remaining_args="$remaining_args $arg" ;;
    esac
done
if [ "$saw_flag" -eq 1 ]; then
    # shellcheck disable=SC2086
    set -- $remaining_args
fi

# With -gtk4 the Windows build needs GtkBackend in the package and the GTK
# include paths on the command line. SwiftPM does not apply a systemLibrary's
# pkgConfig cflags on Windows -- measured, the clang invocation for GtkCHelpers
# carried only its own include directory -- so they are collected here and
# passed with -Xcc. On Linux SwiftPM handles it and nothing extra is needed.
# 使用 -gtk4 時，Windows 建置需要在套件中加入 GtkBackend，並在命令列提供 GTK 的 include
# 路徑。SwiftPM 在 Windows 上不會套用 systemLibrary 的 pkgConfig cflags——實測
# GtkCHelpers 的 clang 呼叫只帶了自身的 include 目錄——因此在此收集並以 -Xcc 傳入。
# Linux 上由 SwiftPM 自行處理，不需額外動作。
# Each backend gets its own build tree. Sharing one is not merely slower, it is
# wrong: SwiftPM's incremental state records which modules a target depended on,
# so a -gtk4 build leaves references to GtkBackend behind and the next default
# build fails with `missing required modules: 'CGtk', 'GtkCHelpers'` even though
# its own Package.swift never mentions them. Measured on this machine, and it
# takes a `rm -rf .build` to clear. Separate trees also keep both warm, which is
# what makes an incremental comparison between the two possible at all.
# 每個 backend 使用各自的建置目錄樹。共用一個不只是比較慢，而是錯的：SwiftPM 的增量狀態
# 會記錄每個 target 曾依賴哪些模組，因此 -gtk4 的建置會留下對 GtkBackend 的參照，使下一次
# 預設建置以 `missing required modules: 'CGtk', 'GtkCHelpers'` 失敗——即使它自己的
# Package.swift 從未提及那些模組。本機實測如此，且必須 `rm -rf .build` 才能清除。分開的
# 目錄樹也讓兩者都保持溫熱，這正是兩個 backend 之間得以進行增量比較的前提。
if [ -n "${COMPILE_WORK_DIR:-}" ]; then
    compile_work_dir="$(windows_path "$COMPILE_WORK_DIR")"
elif [ "$force_gtk4" -eq 1 ]; then
    compile_work_dir="$(windows_path "$script_dir/.compile-work-gtk4")"
elif [ "$target_platform" = "android" ]; then
    compile_work_dir="$(windows_path "$script_dir/.compile-work-android")"
elif [ "$target_platform" = "ios" ]; then
    # iOS gets its own tree because it is the one path that RENAMES the package.
    # It names the package after the single app it builds, so that
    # `xcodebuild -scheme <product>` finds a matching scheme -- see the note
    # beside package_name below, and do not "fix" that by going back to
    # TestApps: bundling then fails with "does not contain a scheme named P12",
    # which reads like a missing target and is only a name mismatch.
    #
    # Sharing a tree with the WinUI and macOS builds therefore meant the
    # manifest flipped between `name: "P12"` and `name: "TestApps"` on every
    # alternation. The manifest is one of llbuild's three PackageStructure
    # inputs, so each flip re-planned the whole build -- the same cost measured
    # at 28-83s for a Pn switch and removed for -gtk4 in the commit before this.
    #
    # Separating the tree is what fixes it. Renaming the package would not: it
    # would trade a slow build for a broken one.
    #
    # iOS 使用自己的目錄樹，因為它是唯一會「更改套件名稱」的路徑。它以所建置的那個唯一 app
    # 為套件命名，好讓 `xcodebuild -scheme <product>` 找得到相符的 scheme——詳見下方
    # package_name 處的說明；請勿以「改回 TestApps」來「修正」它：那會使打包失敗並顯示
    # 「does not contain a scheme named P12」，該訊息讀起來像缺少 target，實則只是名稱不一致。
    #
    # 因此，與 WinUI、macOS 共用一棵樹，意味著 manifest 會在 `name: "P12"` 與
    # `name: "TestApps"` 之間來回翻動。manifest 是 llbuild 三個 PackageStructure input 之一，
    # 每翻動一次就重新規劃整個建置——即前一個 commit 為 -gtk4 所消除、實測 28 至 83 秒的那筆成本。
    #
    # 分開目錄樹才是解法。改套件名稱不是：那是拿「慢的建置」換「壞掉的建置」。
    compile_work_dir="$(windows_path "$script_dir/.compile-work-ios")"
else
    # Every tree is named after the backend it holds. There is deliberately no
    # suffix-less `.compile-work` any more.
    #
    # It used to be the fallback, and that made it the one directory whose
    # contents could not be read off its name: on Windows it held WinUI, on
    # Linux it held Gtk, and on macOS it held AppKit. A 12 GB directory that
    # answers "which backend is this?" with "depends where you ran it" is a
    # directory nobody can decide whether to delete -- which is how it reached
    # 12 GB, on a disk that then hit 100% and failed every build of the day with
    # `I/O error (code: 28)`, an ENOSPC that reads like a corrupt build database.
    #
    # If a new platform lands here, give it its own branch above rather than
    # letting it fall through. An unnamed tree is the bug.
    #
    # 每一棵樹都以它所存放的 backend 命名。此處刻意不再有無後綴的 `.compile-work`。
    #
    # 它從前是 fallback，而那使它成為「唯一無法從名字看出內容」的目錄：在 Windows 上放 WinUI、
    # 在 Linux 上放 Gtk、在 macOS 上放 AppKit。一個對「這是哪個 backend?」只能回答「看你在哪裡
    # 執行」的 12 GB 目錄，是沒有人能決定該不該刪的目錄——而它正是這樣長到 12 GB，接著把磁碟
    # 塞到 100%，使當天每一次建置都以 `I/O error (code: 28)` 失敗；那是一個 ENOSPC，讀起來
    # 卻像建置資料庫壞掉。
    #
    # 若日後有新平台落到此處，請在上方為它加一個分支，而不要讓它掉進來。沒有名字的樹本身就是 bug。
    #
    # Linux resolves to the SAME tree as -gtk4, not to a second one, because it
    # would hold the same thing: GtkBackend is already the default there, so
    # `compile.zsh P1` and `compile.zsh -gtk4 P1` build byte-identical trees on
    # Linux. Two directories for one backend is how the orphaned pair that
    # started this cleanup came to exist.
    #
    # Linux 解析到與 -gtk4 **同一棵樹**，而不是另建一棵，因為兩者存放的內容相同：GtkBackend
    # 在該平台本就是預設，因此在 Linux 上 `compile.zsh P1` 與 `compile.zsh -gtk4 P1` 建出的是
    # 位元組相同的樹。「一個 backend 兩個目錄」正是引發這次清理的那對孤兒目錄的由來。
    case "$host_uname" in
        MINGW*|MSYS*|CYGWIN*)
            compile_work_dir="$(windows_path "$script_dir/.compile-work-winui")"
            ;;
        Darwin)
            compile_work_dir="$(windows_path "$script_dir/.compile-work-appkit")"
            ;;
        *)
            compile_work_dir="$(windows_path "$script_dir/.compile-work-gtk4")"
            ;;
    esac
fi
package_dir="$compile_work_dir/TestApps"
sources_root="$package_dir/Sources"

# Drop SwiftPM's cached manifests when SCUI_DEBUG changes value.
#
# swift-cross-ui's own Package.swift reads `env["SCUI_DEBUG"]` and defines the
# `SCUI_DEBUG` compilation condition from it. SwiftPM caches the *result* of
# evaluating a manifest, keyed on the manifest's contents and the toolchain --
# not on the environment the manifest read. So flipping the variable between
# two runs changes nothing: the second run reuses the first run's answer.
#
# Measured 2026-09-02. `zsh compile.zsh -ios P12` with SCUI_DEBUG unset, run
# after a build with SCUI_DEBUG=1, produced a binary still containing the
# strings that only exist inside `#if SCUI_DEBUG`, and the debug-only
# actualView/rwdView control still appeared on screen. Nothing in the build
# output suggested a stale anything -- it recompiled, it just recompiled with
# the previous run's flags.
#
# The generated TestApps manifest cannot carry the signal, because it is
# written to be byte-identical between runs on purpose (see the manifest
# optimisation below); that is what keeps llbuild from re-planning the whole
# package on every alternation, and it is worth keeping.
#
# So the value is stamped in the work directory instead, and a change clears
# the manifest caches. Only the manifest caches: the build directory is left
# alone, so the cost is one re-evaluation rather than a full rebuild.
#
# 當 SCUI_DEBUG 的值改變時，清掉 SwiftPM 快取的 manifest。
#
# swift-cross-ui 自己的 Package.swift 會讀取 `env["SCUI_DEBUG"]`，並據以定義 `SCUI_DEBUG`
# 這個編譯條件。而 SwiftPM 快取的是「求值 manifest 的**結果**」，其鍵值取自 manifest 的內容
# 與工具鏈——不包含 manifest 所讀取的環境。因此在兩次執行之間翻動該變數不會有任何效果：第二次
# 執行會沿用第一次的答案。
#
# 2026-09-02 實測。在一次 SCUI_DEBUG=1 的建置之後，執行未設定 SCUI_DEBUG 的
# `zsh compile.zsh -ios P12`，產出的執行檔仍含有那些只存在於 `#if SCUI_DEBUG` 之內的字串，
# 而僅限 debug 的 actualView/rwdView 控制項也依然出現在畫面上。建置輸出中沒有任何跡象顯示有東西
# 是陳舊的——它確實重新編譯了，只是用的是上一次執行的旗標。
#
# 這個訊號無法由產生出來的 TestApps manifest 攜帶，因為它是刻意被寫成「兩次執行之間逐位元組相同」
# 的（見下方的 manifest 最佳化）；正是那一點讓 llbuild 不必在每次交替時重新規劃整個套件，而那是
# 值得保留的。
#
# 因此改為把該值蓋印在 work 目錄中，一旦改變就清除 manifest 快取。只清 manifest 快取：建置目錄
# 不予更動，因此代價是一次重新求值，而非一次完整重建。
scui_debug_stamp="$compile_work_dir/.scui-debug-value"
# ON by default here, which is the opposite of `swift build`'s default, and
# deliberately so. `Package.swift` leaves SCUI_DEBUG off because a *shipped*
# application should not carry a way to synthesise clicks into whatever window
# is in front -- see Sources/DebugFeatures/README.md. This script ships nothing.
# Everything it builds is a test app whose whole purpose is to be driven from
# `testapp/actions/`, and it already links `InputEvent` into every one of them
# unconditionally (see `testAppDependencies` below), so the two reasons the
# library default rests on -- size, and an input-injection tool in a released
# binary -- do not apply to anything produced here.
#
# What the old default produced was the silent failure this script's own
# comments describe twice over: `-c release` with no define, `-actionfile`
# accepted by the shell and by `CommandLine.arguments`, the replay code linked,
# and the one line that starts a replay compiled out of the backend. No error,
# no warning, not even the `replaying ...` line. A build flag whose absence
# turns a driven test into a silent no-op is not a safe default for a directory
# of driven tests.
#
# Note which axis this is on. The gate is the DEFINE, never the configuration:
# `BUILD_CONFIG=debug` does not define SCUI_DEBUG and never did, so "rebuild it
# in debug" was never the way to get a replay back. Release with the define is,
# and now that is what an unadorned run produces.
#
# `SCUI_DEBUG=0` still opts out, for the A/B scripts that need a build without
# the debug features as their control -- test_rootscroll_ios.zsh and
# test_rootscroll_android.zsh pass it for exactly that.
#
# 此處預設為「開」，與 `swift build` 的預設相反，且是刻意如此。`Package.swift` 之所以預設關閉
# SCUI_DEBUG，是因為「已出貨」的應用程式不應攜帶一套「向前方任何視窗合成點擊」的手段——詳見
# Sources/DebugFeatures/README.md。而本腳本不出貨任何東西：它建置的全是測試 app，其存在目的
# 正是要被 `testapp/actions/` 驅動，而且它本來就已無條件把 `InputEvent` 連結進其中每一個
# （見下方的 `testAppDependencies`）。因此該函式庫預設所倚賴的兩個理由——體積，以及「已發布
# 執行檔中的輸入注入工具」——對此處產出的任何東西都不成立。
#
# 舊的預設所造成的，正是本腳本自己的註解已描述過兩次的那種靜默失敗：`-c release` 而未帶定義、
# `-actionfile` 被 shell 與 `CommandLine.arguments` 雙雙接受、重放程式碼也連結進去了，而「啟動
# 重放的那一行」卻被編譯出了 backend 之外。沒有錯誤、沒有警告，連 `replaying ...` 都沒有。
# 一個「缺少它就會把受驅動的測試變成靜默 no-op」的建置旗標，不該是一整個受驅動測試目錄的預設。
#
# 請注意這是哪一條軸線。閘門一直是那個「定義」，而非「組態」：`BUILD_CONFIG=debug` 不會定義
# SCUI_DEBUG，而且從來沒有過——所以「用 debug 重建一次」從來就不是把重放找回來的方法。真正的
# 方法是「release 加上該定義」，而現在，一次不帶任何裝飾的執行產出的就是它。
#
# `SCUI_DEBUG=0` 仍可退出，供那些「需要一個不含 debug 功能的建置作為對照組」的 A/B 腳本使用——
# test_rootscroll_ios.zsh 與 test_rootscroll_android.zsh 傳的正是它。
scui_debug_value="${SCUI_DEBUG:-1}"

# Export it, or the cache invalidation above is the only thing that ever sees
# it. `Package.swift` reads `env["SCUI_DEBUG"]` to decide whether to define the
# `SCUI_DEBUG` compilation condition, and `swift build` runs as a child of this
# script: a value set on the command line as `SCUI_DEBUG=1 zsh compile.zsh ...`
# reaches this shell, but an unexported shell variable does not reach the child.
# Everything else here handled the flag correctly, which is what made the gap
# hard to see -- the stamp changed, the caches were dropped, the whole package
# was re-evaluated, and it was re-evaluated with the flag still unset.
#
# Measured 2026-09-03, and it cost most of an afternoon. GtkBackend guards its
# `ActionFileReplay.replayIfRequested()` call with `#if SCUI_DEBUG`, so every
# binary built here had the action-file replay compiled out. The failure is
# completely silent: `run.zsh -actionfile` accepts the path, the app launches
# and renders, and not one line is printed -- no error, no warning, not even the
# `replaying ...` the replay would emit. Three separate conclusions were drawn
# about a synthesiser change that had never once executed.
#
# 必須 export，否則上方的快取失效是唯一看得見這個值的東西。`Package.swift` 讀
# `env["SCUI_DEBUG"]` 來決定是否定義 `SCUI_DEBUG` 編譯條件，而 `swift build` 是本腳本的
# 子行程：以 `SCUI_DEBUG=1 zsh compile.zsh ...` 在命令列設定的值會到達本 shell，但未 export
# 的 shell 變數不會傳給子行程。此處其餘每一段都正確處理了這個旗標，而那正是這個缺口難以察覺的
# 原因——戳記變了、快取被清了、整個套件被重新求值，而重新求值時該旗標依然是未設定的。
#
# 2026-09-03 實測，代價是大半個下午。GtkBackend 以 `#if SCUI_DEBUG` 包住它呼叫
# `ActionFileReplay.replayIfRequested()` 之處，因此此處建出的每一個執行檔都把動作檔重放編譯掉
# 了。該失敗完全靜默：`run.zsh -actionfile` 接受了路徑、app 正常啟動並繪製，卻一行都不印
# ——沒有錯誤、沒有警告，連重放本該印出的 `replaying ...` 都沒有。有三個關於某項 synthesiser
# 改動的結論，就是在它從未被執行過的情況下做出的。
export SCUI_DEBUG="$scui_debug_value"

mkdir -p "$compile_work_dir"
if [ "$(cat "$scui_debug_stamp" 2>/dev/null || true)" != "$scui_debug_value" ]; then
    rm -rf "$package_dir/.build/manifest.db" \
        "$package_dir/.build/manifest.db-shm" \
        "$package_dir/.build/manifest.db-wal" \
        "$HOME/Library/Caches/org.swift.swiftpm/manifests" \
        "$HOME/.swiftpm/cache/manifests" \
        "$HOME/.cache/org.swift.swiftpm/manifests"
    printf '%s' "$scui_debug_value" > "$scui_debug_stamp"
fi

windows_gtk_product=""
gtk_build_flags=()
debug_feature_flags=()
if [ "${SCUI_DEBUG:-}" = "1" ]; then
    debug_feature_flags=(-Xswiftc -DSCUI_DEBUG)
fi

# The WinUI products a test app depends on directly, dropped entirely under
# -gtk4. Redirecting DefaultBackend is not enough on its own: the app names
# these four in its own dependency list, so they are pulled in regardless of
# what DefaultBackend resolves to. Measured -- with SCUI_DEFAULT_BACKEND set
# and these still listed, the app ran on GtkBackend while the build compiled 73
# WinUI steps and produced a 342 MB binary, so the flag delivered the backend
# switch without either of the savings that motivated it.
# 測試 app 直接依賴的 WinUI product，於 -gtk4 時整組移除。單靠改變 DefaultBackend 的解析
# 並不足夠：app 在自己的依賴清單中點名了這四個，因此無論 DefaultBackend 解析到誰，它們都
# 會被帶入。實測顯示：已設定 SCUI_DEFAULT_BACKEND 但仍列出這四項時，app 確實跑在
# GtkBackend 上，但建置仍編譯了 73 個 WinUI 步驟並產生 342 MB 的執行檔——該旗標達成了
# backend 切換，卻沒有帶來當初採用它的兩項效益中的任何一項。
windows_winui_products='.product(name: "WinUIBackend", package: "swift-cross-ui", condition: .when(platforms: [.windows])),
    .product(name: "WinUI", package: "swift-winui", condition: .when(platforms: [.windows])),
    .product(name: "UWP", package: "swift-winui", condition: .when(platforms: [.windows])),
    .product(name: "WindowsFoundation", package: "swift-winui", condition: .when(platforms: [.windows])),'

# Dropped as well under -gtk4, not just its products. A package dependency with
# nothing depending on it is still resolved and fetched.
# -gtk4 時連同套件依賴一起移除，而不只是它的 product。無人依賴的套件依賴仍會被解析與取回。
winui_package='.package(
            url: "https://github.com/moreSwift/swift-winui",
            .upToNextMinor(from: "0.2.1")
        ),'

if [ "$force_gtk4" -eq 1 ]; then
    # Gtk as well as GtkBackend. An app that only draws through SwiftCrossUI
    # needs neither, but one embedding a raw widget needs both: GtkBackend for
    # GtkWidgetRepresentable and Gtk for the widget type it wraps. P6-v2 wraps
    # NV12GLView to get the video onto the GPU.
    # 除了 GtkBackend 之外還需要 Gtk。若 app 僅透過 SwiftCrossUI 繪製則兩者皆不需要；但要嵌入
    # 原生 widget 的 app 兩者都要：GtkBackend 提供 GtkWidgetRepresentable，Gtk 提供被包裝的
    # widget 型別。P6-v2 即是包裝 NV12GLView 以將影像送上 GPU。
    windows_gtk_product='.product(name: "GtkBackend", package: "swift-cross-ui", condition: .when(platforms: [.windows])),
    .product(name: "Gtk", package: "swift-cross-ui", condition: .when(platforms: [.windows])),'
    windows_winui_products=""
    winui_package=""

    # This is what actually redirects the backend. Adding GtkBackend as a product
    # above only makes it available to link; it does not change what
    # `import DefaultBackend` resolves to, which Package.swift hard-codes per
    # platform (WinUIBackend on Windows, GtkBackend on Linux). Without this
    # export, -gtk4 on Windows linked *both* backends and the app still ran on
    # WinUI -- so the flag made the build slower rather than faster, and it died
    # emitting the WindowsFoundation module, a target the flag exists to avoid.
    # SCUI_DEFAULT_BACKEND is the hook Package.swift already provides for this.
    # 真正切換 backend 的是這一行。上方將 GtkBackend 加為 product 只是讓它可供連結，並不會
    # 改變 `import DefaultBackend` 解析到哪個 backend——那在 Package.swift 中依平台寫死
    # （Windows 為 WinUIBackend、Linux 為 GtkBackend）。少了這個 export，Windows 上的
    # -gtk4 會同時連結*兩個* backend，而 app 仍然跑在 WinUI 上——因此該旗標讓建置變慢而非
    # 變快，並且會在產生 WindowsFoundation 模組時失敗，而那正是此旗標意在避開的 target。
    # SCUI_DEFAULT_BACKEND 是 Package.swift 既有的鉤子。
    export SCUI_DEFAULT_BACKEND=GtkBackend

    if [ "$(uname -s 2>/dev/null)" != "Linux" ]; then
        gtk_prefix="${GTK4_PREFIX:-C:/gtk4}"
        gtk_pkgconfig="$gtk_prefix/bin/pkg-config.exe"
        if [ ! -x "$gtk_pkgconfig" ]; then
            printf 'GTK 4 not found at %s\n' "$gtk_prefix" >&2
            printf 'Run: zsh testapp/install_gtk4_windows.zsh\n' >&2
            exit 1
        fi
        for flag in $(PKG_CONFIG_PATH="$gtk_prefix/lib/pkgconfig" "$gtk_pkgconfig" --cflags gtk4 2>/dev/null); do
            case "$flag" in -I*) gtk_build_flags+=(-Xcc "$flag") ;; esac
        done

        # Exported, not just used for the line above. SwiftPM resolves the CGtk
        # systemLibrary itself and needs to find gtk4.pc, which is a separate
        # thing from the -Xcc include paths. Without it the build runs to
        # completion and then fails at the end with `couldn't find pc file for
        # gtk4` and `missing required modules: 'CGtk', 'GtkCHelpers'` -- 29
        # minutes on this machine before anything said so.
        # 必須 export，而不只是供上一行使用。SwiftPM 會自行解析 CGtk 這個 systemLibrary，
        # 因而需要找到 gtk4.pc，這與 -Xcc 的 include 路徑是兩回事。少了它，建置會一路跑完
        # 才在最後失敗，訊息為 `couldn't find pc file for gtk4` 與
        # `missing required modules: 'CGtk', 'GtkCHelpers'`——本機為此花了 29 分鐘才得知。
        export PKG_CONFIG_PATH="$gtk_prefix/lib/pkgconfig"

        # The GTK DLLs have to be findable when the app is launched, and putting
        # them on PATH here means a build and a run from the same shell agree.
        # 執行 app 時必須找得到 GTK 的 DLL；在此加入 PATH 可讓同一個 shell 中的建置與執行
        # 使用一致的設定。
        export PATH="$gtk_prefix/bin:$PATH"

        printf '==> Forcing GtkBackend with %s include flags from %s\n' \
            "$((${#gtk_build_flags[@]} / 2))" "$gtk_prefix"
    else
        printf '==> Forcing GtkBackend\n'
    fi
fi

mkdir -p "$output_dir" "$sources_root"

compile_app() {
    app_file="$1"
    source_path="$script_dir/$app_file"

    if [ ! -f "$source_path" ]; then
        echo "Missing source file: $source_path" >&2
        exit 1
    fi

    # Refused up front rather than left to fail at compile time. -gtk4 removes the
    # WinUI products, so an app importing them cannot build under it; without this
    # the failure arrives as `no such module 'UWP'` well into a build that costs
    # about thirteen minutes on this machine. P6 is the only such app today, and
    # it is Windows-specific by construction -- SwapChainPanel and a D3D11
    # composition swap chain have no GtkBackend equivalent, so this is a real
    # exclusion rather than a gap to close.
    # 提前拒絕，而非留到編譯時才失敗。-gtk4 會移除 WinUI 的 product，因此 import 它們的 app
    # 無法在該模式下建置；少了這道檢查，錯誤會以 `no such module 'UWP'` 的形式出現在一次
    # 於本機約需十三分鐘的建置中途。目前只有 P6 屬於此類，而它在設計上即為 Windows 專屬——
    # SwapChainPanel 與 D3D11 composition swap chain 在 GtkBackend 中沒有對應物，因此這是
    # 一項真實的排除，而非有待補上的缺口。
    # The two sides are NOT symmetric, and the reason is worth stating because
    # making them symmetric is the obvious wrong move -- it was made on
    # 2026-09-02 and P6 then failed with `no such module 'UWP'`.
    #
    # `-gtk4` removes the WinUI PRODUCTS but does not change the OS. P6's
    # `import UWP` sits under `#if os(Windows)`, which is still true, so the
    # import is compiled and the module is gone. An app naming the WinUI
    # products therefore cannot build under -gtk4 no matter what else it names.
    #
    # The other direction is different. P6's `import Gtk` sits under
    # `#if canImport(Gtk)`, which goes false by itself in the WinUI build. So
    # naming Gtk does NOT prevent a WinUI build -- only naming Gtk *and not the
    # WinUI products* marks an app as GTK-only.
    #
    # 兩側**並不**對稱，而理由值得寫下來，因為「把它們對稱化」正是那個顯而易見的錯誤做法——
    # 2026-09-02 這麼做過，隨後 P6 就以 `no such module 'UWP'` 失敗。
    #
    # `-gtk4` 移除的是 WinUI 的 **product**，但不改變 OS。P6 的 `import UWP` 位於
    # `#if os(Windows)` 之內，而該條件仍為真，於是那行 import 會被編譯，模組卻已不存在。因此，
    # 只要一支 app 指名了 WinUI product，無論它還指名了什麼，都無法在 -gtk4 下建置。
    #
    # 另一個方向則不同。P6 的 `import Gtk` 位於 `#if canImport(Gtk)` 之內，該條件在 WinUI 建置下
    # 會自行為假。因此「指名了 Gtk」並不妨礙 WinUI 建置——唯有「指名 Gtk **且未指名 WinUI
    # product**」才標示出一支 GTK 專屬的 app。
    imports_gtk=0
    imports_winui=0
    grep -qE '^import (Gtk|GtkBackend)$' "$source_path" && imports_gtk=1
    grep -qE '^import (UWP|WinUI|WinUIBackend|WindowsFoundation)$' "$source_path" \
        && imports_winui=1

    if [ "$force_gtk4" -eq 1 ] && [ "$imports_winui" -eq 1 ]; then
        printf '    skipping %s: it imports the WinUI products, which -gtk4 removes\n' "$app_file" >&2
        printf '    build it with: zsh compile.zsh %s\n' "${app_file%.swift}" >&2
        continue
    fi

    if [ "$force_gtk4" -eq 0 ] && [ "$imports_gtk" -eq 1 ] && [ "$imports_winui" -eq 0 ]; then
        # The build that lacks Gtk is whichever one is running, not always WinUI.
        # A macOS user was told "which the WinUI build lacks" while building for
        # macOS, which reads as a message meant for someone else.
        # 缺少 Gtk 的是「正在執行的那個建置」，未必總是 WinUI。曾有 macOS 使用者在為 macOS 建置時
        # 被告知「which the WinUI build lacks」，那讀起來像是一則寫給別人的訊息。
        printf '    skipping %s: it imports Gtk, which this build lacks\n' "$app_file" >&2
        printf '    build it with: zsh compile.zsh -gtk4 %s\n' "${app_file%.swift}" >&2
        continue
    fi



    app_name="${app_file%.swift}"

    target_dir="$sources_root/$app_name"
    mkdir -p "$target_dir"
    # Only when the content differs. An unconditional cp gives an unchanged file
    # a new mtime, and SwiftPM decides from mtimes -- see the note beside the
    # manifest write below, where the same mistake cost far more.
    # 僅在內容不同時才複製。無條件的 cp 會給未變更的檔案一個新的 mtime，而 SwiftPM 是依 mtime
    # 判斷的——見下方 manifest 寫入處的說明，同樣的錯誤在該處代價高得多。
    if ! cmp -s "$source_path" "$target_dir/main.swift" 2>/dev/null; then
        cp "$source_path" "$target_dir/main.swift"
    fi

    if grep -q '^import ImageFormats' "$source_path"; then
        needs_image_formats=1
    fi
}

if [ "$#" -gt 0 ]; then
    app_names=""
    for app in "$@"; do
        case "$app" in
            *.swift) app_file="$app" ;;
            *) app_file="$app.swift" ;;
        esac

        compile_app "$app_file"
        app_name="${app_file%.swift}"
        app_names="$app_names $app_name"
    done
else
    app_names=""
    found_any=0
    for source_path in "$script_dir"/P*.swift; do
        if [ ! -f "$source_path" ]; then
            continue
        fi

        found_any=1
        app_file="$(basename "$source_path")"
        compile_app "$app_file"
        app_name="${app_file%.swift}"
        app_names="$app_names $app_name"
    done

    if [ "$found_any" -eq 0 ]; then
        echo "No P*.swift files found in $script_dir" >&2
        exit 1
    fi
fi

# Which apps appear as TARGETS in the manifest, which is not the same question
# as which apps get built.
#
# Every buildable app, always, rather than only the ones requested. The manifest
# is one of llbuild's three PackageStructure inputs, so changing its contents
# re-plans the entire build. Listing only the requested apps meant that
# compiling a different Pn than last time rewrote the manifest and paid for a
# full re-plan. Measured on this machine, GTK4/Windows:
#
#     same app twice        6s, 7s
#     switch to P19        83s
#     switch back to P40   28s
#
# A sweep across ~26 apps therefore spent 13-35 minutes doing nothing but
# re-planning. Listing them all makes the manifest byte-identical between
# invocations, so the plan is computed once and every app after that builds
# warm. `swift build` still receives --product for the requested app alone, so
# nothing extra is compiled: a listed target is not a built target.
#
# Not applied to -ios, which names the package after the single app it builds
# and requires exactly one.
#
# 哪些 app 會以 target 形式出現在 manifest 中——這與「哪些 app 會被建置」是兩個不同的問題。
#
# 此處列出「每一個可建置的 app」，而非僅列出被請求的那些。manifest 是 llbuild 的
# PackageStructure 三個 input 之一，因此改動其內容會重新規劃整個建置。過去只列出被請求的 app，
# 意味著「這次編譯的 Pn 與上次不同」就會改寫 manifest，並付出一次完整重新規劃的代價。本機實測
# （GTK4/Windows）：同一個 app 連續兩次為 6、7 秒；切換到 P19 為 83 秒；切回 P40 為 28 秒。
#
# 因此一輪涵蓋約 26 個 app 的 sweep，光是重新規劃就花掉 13 至 35 分鐘。全部列出可使 manifest 在
# 各次呼叫之間逐位元組相同，於是建置計畫只算一次，之後每個 app 都是熱的。`swift build` 仍只收到
# 被請求 app 的 --product，因此不會多編譯任何東西：**被列出的 target 不等於被建置的 target**。
#
# 不套用於 -ios：該路徑會以它所建置的那個唯一 app 為套件命名，且要求恰好一個。
manifest_app_names="$app_names"
if [ "$target_platform" != "ios" ]; then
    manifest_app_names=""
    for source_path in "$script_dir"/P*.swift; do
        [ -f "$source_path" ] || continue
        candidate_file="$(basename "$source_path")"
        candidate="${candidate_file%.swift}"
        # The SAME rule compile_app uses, including its asymmetry. Two
        # predicates that disagree produce `error: no product named 'P6'` --
        # measured 2026-09-02, when this filter and compile_app briefly差了一步.
        # 與 compile_app 完全相同的規則，包含它的不對稱性。兩個判準若不一致，就會產生
        # `error: no product named 'P6'`——2026-09-02 實測，當時此處與 compile_app 差了一步。
        candidate_gtk=0
        candidate_winui=0
        grep -qE '^import (Gtk|GtkBackend)$' "$source_path" && candidate_gtk=1
        grep -qE '^import (UWP|WinUI|WinUIBackend|WindowsFoundation)$' "$source_path" \
            && candidate_winui=1
        if [ "$force_gtk4" -eq 1 ] && [ "$candidate_winui" -eq 1 ]; then
            continue
        fi
        if [ "$force_gtk4" -eq 0 ] && [ "$candidate_gtk" -eq 1 ] \
            && [ "$candidate_winui" -eq 0 ]; then
            continue
        fi


        mkdir -p "$sources_root/$candidate"
        if ! cmp -s "$source_path" "$sources_root/$candidate/main.swift" 2>/dev/null; then
            cp "$source_path" "$sources_root/$candidate/main.swift"
        fi
        if grep -q '^import ImageFormats' "$source_path"; then
            needs_image_formats=1
        fi
        manifest_app_names="$manifest_app_names $candidate"
    done
fi

# Android hides everything it does not export across a library boundary.
#
# An app's own library statically links SwiftCrossUI, AndroidBackend, SwiftJava
# and libwebp, and by default exports every public symbol in all of them:
# measured on P44's release APK, 151,047 dynamic symbols of which 31 have a
# caller outside the library. The names alone -- Swift mangling averages 76
# characters -- came to 15.81 MB across .dynstr, .dynsym, .gnu.hash and
# .gnu.version, 34% of a 46.4 MB library.
#
# Android only. The other platforms ship an executable rather than a library
# loaded by name from Java, they do not carry a 46 MB binary onto a phone, and
# a version script is GNU-linker syntax that Apple's ld does not take. The
# android manifest lives in its own work directory, so this does not perturb
# the byte-identical manifests the other paths rely on.
#
# 讓 Android 隱藏一切不需跨 library 邊界匯出的東西。
#
# app 自己的 library 靜態連結了 SwiftCrossUI、AndroidBackend、SwiftJava 與 libwebp，並預設匯出
# 其中每一個 public 符號：以 P44 的 release APK 實測，151,047 個動態符號中，只有 31 個在該
# library 之外有呼叫者。單是那些名字——Swift 的名稱修飾平均 76 個字元——在 .dynstr、.dynsym、
# .gnu.hash 與 .gnu.version 中合計 15.81 MB，佔一個 46.4 MB library 的 34%。
#
# 僅限 Android。其他平台出貨的是執行檔而非「由 Java 以名稱載入的 library」，它們也不會把一個
# 46 MB 的二進位檔搬上手機，而且 version script 是 GNU linker 的語法，Apple 的 ld 不接受。
# android 的 manifest 位於它自己的工作目錄，因此這不會擾動其他路徑所倚賴的「逐位元組相同的
# manifest」。
app_linker_settings=""
if [ "$target_platform" = "android" ]; then
    app_linker_settings=",
            linkerSettings: [
                .unsafeFlags([
                    \"-Xlinker\",
                    \"--version-script=$script_dir/android-exports.map\",
                ])
            ]"
fi

targets=""
for app_name in $manifest_app_names; do
    targets="$targets
        .executableTarget(
            name: \"$app_name\",
            dependencies: testAppDependencies$app_linker_settings
        ),"
done

# xcodebuild derives the scheme name from the package name, and Swift Bundler
# builds iOS targets by invoking `xcodebuild -scheme <product>`. A package named
# TestApps therefore has no scheme matching the app, and bundling fails with
# "does not contain a scheme named P12" -- which sounds like a missing target
# but is only a name mismatch. Naming the package after the app lines them up.
# The host path keeps the shared TestApps package, where one build covers every
# requested app.
# xcodebuild 依套件名稱推導 scheme 名稱，而 Swift Bundler 建置 iOS target 時會呼叫
# `xcodebuild -scheme <product>`。因此名為 TestApps 的套件不會有與 app 同名的
# scheme，打包時會失敗並顯示「does not contain a scheme named P12」；該訊息聽起來
# 像缺少 target，實際上只是名稱不一致。將套件以 app 命名即可對齊。
# 主機路徑仍使用共用的 TestApps 套件，一次建置即涵蓋所有請求的 app。
package_name="TestApps"
if [ "$target_platform" = "ios" ]; then
    ios_app_count="$(printf '%s' "$app_names" | wc -w | tr -d ' ')"
    if [ "$ios_app_count" -ne 1 ]; then
        echo "-ios builds one app at a time (the package is named after it); got:$app_names" >&2
        exit 1
    fi
    package_name="$(printf '%s' "$app_names" | tr -d ' ')"
fi

image_formats_product=""
image_formats_package=""
if [ "$needs_image_formats" -eq 1 ]; then
    image_formats_product='
    .product(name: "ImageFormats", package: "swift-image-formats"),'
    image_formats_package='
        .package(
            url: "https://github.com/stackotter/swift-image-formats",
            .upToNextMinor(from: "0.5.0")
        ),'
fi

# Written to a temporary file and moved into place only when it differs.
#
# This manifest's content is the same on almost every run -- same apps, same
# flags -- but writing it unconditionally gave it a new mtime every time, and
# SwiftPM decides what to rebuild from mtimes. So a run that changed nothing
# still re-planned the build and re-emitted every module. Measured on this
# machine: a -gtk4 rebuild of P24 with no source change took 118s, of which
# emitting the Gtk module alone -- the large GIR-generated bindings, which the
# WinUI path never builds -- was 16s. Confirmed by hashing: identical MD5 before
# and after a rerun, different mtime.
#
# That is also most of the answer to why -gtk4 looks so much slower than the
# WinUI path on Windows. Some of it is real (Gtk is a big module), and some of
# it was this.
#
# 先寫入暫存檔，僅在內容不同時才移入定位。
#
# 此 manifest 的內容在幾乎每一次執行中都相同——相同的 app、相同的旗標——但無條件寫入會使它每次都
# 取得新的 mtime，而 SwiftPM 正是依 mtime 決定要重建什麼。因此一次什麼都沒改的執行，仍會重新規劃
# 建置並重新 emit 每一個 module。本機實測：在原始碼未變更的情況下，-gtk4 重建 P24 耗時 118 秒，
# 其中光是 emit `Gtk` 模組——那個 GIR 產生的大型綁定模組，WinUI 路徑根本不會建它——就佔了 16 秒。
# 已以雜湊確認：重跑前後 MD5 完全相同，mtime 卻不同。
#
# 這也是「為何 -gtk4 在 Windows 上看起來比 WinUI 路徑慢這麼多」的大部分答案。其中一部分是真實的
# （Gtk 本來就是大模組），另一部分則是此處造成的。
package_manifest_tmp="$package_dir/.Package.swift.new"
cat > "$package_manifest_tmp" <<EOF_PACKAGE
// swift-tools-version:5.10

import PackageDescription

// swift-winui ships several separate products (WinUI, UWP, WindowsFoundation,
// WinAppSDK, CWinRT, ...). A test app can only import the ones listed here, so
// adding an import to P*.swift is not enough on its own -- the product has to
// be added below as well.
// swift-winui 提供數個獨立的 product（WinUI、UWP、WindowsFoundation、
// WinAppSDK、CWinRT 等）。測試程式只能 import 此處列出的模組，因此僅在
// P*.swift 加上 import 並不足夠，必須同時把該 product 加進下方清單。
let testAppDependencies: [Target.Dependency] = [
    .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
    .product(name: "DefaultBackend", package: "swift-cross-ui"),
    // Synthesised input from a CSV file, for -actionfile. Available to every
    // Pn rather than to a chosen few: which app needs driving next is not
    // knowable in advance, and the module costs nothing to link when unused.
    // 由 CSV 檔驅動的合成輸入，供 -actionfile 使用。開放給每一支 Pn 而非少數幾支：下一支需要被
    // 驅動的是哪一個無法事先得知，而未使用時連結此模組並無成本。
    .product(name: "InputEvent", package: "swift-cross-ui"),
    .product(name: "AppKitBackend", package: "swift-cross-ui", condition: .when(platforms: [.macOS])),
    $windows_winui_products
    $windows_gtk_product
    // Gtk, not GtkBackend: what a test app needs on Linux is the window type
    // itself, to cast the backend's window out of the environment. DefaultBackend
    // already pulls GtkBackend in, but a cast has to name Gtk.ApplicationWindow
    // and that needs this module imported directly.
    // 這裡是 Gtk 而非 GtkBackend：測試 app 在 Linux 上需要的是視窗型別本身，用來把
    // backend 的視窗自 environment 轉型出來。DefaultBackend 已經帶入 GtkBackend，但
    // 轉型必須指名 Gtk.ApplicationWindow，因此需要直接 import 此模組。
    .product(name: "Gtk", package: "swift-cross-ui", condition: .when(platforms: [.linux])),
    // GtkBackend on Linux for the same reason it is added on Windows under
    // -gtk4: GtkWidgetRepresentable lives there, and an app embedding a raw
    // widget cannot reach it through DefaultBackend alone.
    // Linux 上加入 GtkBackend 的理由與 Windows 在 -gtk4 下相同：
    // GtkWidgetRepresentable 位於該模組，而嵌入原生 widget 的 app 無法僅透過
    // DefaultBackend 取得它。
    .product(name: "GtkBackend", package: "swift-cross-ui", condition: .when(platforms: [.linux])),
    $image_formats_product
]

let package = Package(
    name: "$package_name",
    platforms: [.macOS(.v11), .iOS(.v13), .tvOS(.v13), .macCatalyst(.v13), .visionOS(.v1)],
    dependencies: [
        .package(path: "$repo_root"),
        $image_formats_package
        $winui_package
    ],
    targets: [$targets
    ]
)
EOF_PACKAGE

if cmp -s "$package_manifest_tmp" "$package_dir/Package.swift" 2>/dev/null; then
    rm -f "$package_manifest_tmp"
else
    mv "$package_manifest_tmp" "$package_dir/Package.swift"
fi

# SwiftPM does not notice a source file that has been ADDED.
#
# llbuild bakes the file list into `.build/debug.yaml` when it plans a build. A
# later build whose inputs are all unchanged reuses that plan, so a newly added
# file belongs to no compile command and is skipped -- with no error, no
# warning, and a build that finishes in seconds looking perfectly successful.
# Editing a file that already exists works fine, which is exactly why this can
# go unnoticed for a long time.
#
# Measured 2026-08-29. `Sources/GtkBackend/ZZProbe.swift` containing nothing but
# `#error` did not fire, three builds running. The same file compiled the moment
# debug.yaml was removed, and a clean `swift build --scratch-path` elsewhere
# compiled it immediately -- so this is llbuild's cached plan, not SwiftPM and
# not the toolchain.
#
# The mechanism, since knowing it is what makes this fix obviously right rather
# than a guess. llbuild's `PackageStructure` task -- the one that prints
# "Planning build" -- has exactly three inputs:
#
#     TestApps/Sources/<Pn>/      TestApps/Package.swift      TestApps/Package.resolved
#
# The path dependency's own Sources/ is not among them and is never watched. So
# adding a file to this repo's Sources/ cannot invalidate the plan, no matter
# what changes there. Confirm with:
#
#     grep -A3 '^  "PackageStructure":$' \
#         testapp/.compile-work-gtk4/TestApps/.build/debug.yaml
#
# Which means the manifest optimisation directly above -- only `mv` when the
# contents differ, so the mtime does not move -- is what allows this. That
# comment records the 118s it saves; this is the price. Touching
# TestApps/Package.swift would also work, and would cost the same re-plan.
#
# Hash the LIST of source paths, not their contents: content changes are what
# llbuild already tracks correctly, and hashing contents would throw the plan
# away on every edit and cost a full rebuild each time. Include SCUI_DEBUG
# because it changes the root package's conditional InputEvent dependencies.
#
# 機制本身，因為知道它才能看出這個修法是「顯然正確」而非猜測。llbuild 的 `PackageStructure`
# task——即印出 "Planning build" 的那一個——恰好只有三個 input：
#
#     TestApps/Sources/<Pn>/      TestApps/Package.swift      TestApps/Package.resolved
#
# path dependency 自己的 Sources/ 不在其中，從未被監看。因此無論本 repo 的 Sources/ 如何變動，
# 新增檔案都不可能使該計畫失效。
#
# 也就是說，上方那段 manifest 最佳化——僅在內容不同時才 `mv`，使 mtime 不動——正是讓此問題成立
# 的原因。那段註解記錄了它省下的 118 秒；此處記錄它的代價。
#
# SwiftPM 不會察覺「新增」的原始檔。
#
# llbuild 在規劃建置時，會把檔案清單烘焙進 `.build/debug.yaml`。之後只要所有輸入都未改變，
# 該計畫就會被重複使用，於是新增的檔案不屬於任何一道編譯指令而被略過——沒有錯誤、沒有警告，
# 而且建置會在數秒內完成、看起來完全成功。修改「既有」檔案則一切正常，這正是此問題能長期
# 不被察覺的原因。
#
# 2026-08-29 實測：`Sources/GtkBackend/ZZProbe.swift` 內容只有 `#error`，連續三次建置都未觸發；
# 一旦移除 debug.yaml，同一個檔案立刻編譯。而在他處以乾淨的 `swift build --scratch-path` 建置，
# 它也立即被編譯——因此問題出在 llbuild 的快取計畫，而非 SwiftPM，也非工具鏈。
#
# 此處雜湊的是原始檔路徑「清單」，而非其內容：內容變更本來就會被 llbuild 正確追蹤，而雜湊內容
# 會導致每次編輯都丟棄整個建置計畫，代價是每次都全量重建。另納入 SCUI_DEBUG，因為它會改變
# root package 的 conditional InputEvent dependencies。
source_list_hash_file="$package_dir/.source-list-hash"
source_list_hash="$(cd "$repo_root" && { find Sources -name '*.swift' -print | sort; printf 'SCUI_DEBUG=%s\n' "${SCUI_DEBUG:-0}"; } | cksum)"
if [[ ! -f "$source_list_hash_file" ]] \
    || [[ "$source_list_hash" != "$(cat "$source_list_hash_file" 2>/dev/null)" ]]; then
    rm -f "$package_dir/.build/debug.yaml" "$package_dir/.build/release.yaml"
    printf '%s\n' "$source_list_hash" > "$source_list_hash_file"
fi

# Swift Bundler needs a Bundler.toml to turn an executable target into an app
# bundle: a SwiftPM executable has no Info.plist or bundle identifier, so
# `simctl install` cannot accept it on its own. Generated alongside
# Package.swift so both stay in step with whichever apps were requested.
# Swift Bundler 需要 Bundler.toml 才能把可執行 target 打包成 app bundle：SwiftPM 的
# 可執行檔本身沒有 Info.plist 與 bundle identifier，simctl install 無法直接安裝。
# 此檔與 Package.swift 一同產生，確保兩者與所請求的 app 清單保持一致。
#
# For Android the per-app section also carries testapp/androidContainer's
# settings. Without them every API level came from swift-bundler's defaults and
# from whichever build-tools the SDK happened to have -- the last APK built that
# way reported compileSdk 35, which nobody had chosen. See that file for what
# each value is and why.
# Android 的 per-app 區段另外帶入 testapp/androidContainer 的設定。若無這些設定，每個 API level
# 都取自 swift-bundler 的預設值與「SDK 恰好安裝了哪個 build-tools」——以該方式建出的最後一個 APK
# 回報 compileSdk 35，而那是無人選擇的結果。各項數值的意義與理由見該檔。
android_container="$script_dir/androidContainer/Bundler.android.toml"
if [ "$target_platform" = "android" ] && [ ! -f "$android_container" ]; then
    echo "Missing Android settings: $android_container" >&2
    exit 1
fi

{
    printf 'format_version = 2\n'
    for app_name in $app_names; do
        printf '\n[apps.%s]\n' "$app_name"
        printf "identifier = 'dev.swiftcrossui.testapp.%s'\n" "$app_name"
        printf "product = '%s'\n" "$app_name"
        printf "version = '0.1.0'\n"
        if [ "$target_platform" = "android" ]; then
            printf '\n[apps.%s.android]\n' "$app_name"
            cat "$android_container"
        fi
    done
} > "$package_dir/Bundler.toml"

if [ "$target_platform" = "android" ]; then
    export ANDROID_HOME="$android_sdk_root"
    # **The host toolchain has to match the Android SDK's Swift version**, and
    # when it does not the failure is a wall of "module compiled with Swift X
    # cannot be imported by the Swift Y compiler" pointing at files nobody in
    # this repository wrote.
    #
    # Measured 2026-09-11: the host `swift` was 6.4, the installed SDK was
    # `swift-6.3.3-RELEASE_android.artifactbundle`, and every Android build had
    # been failing that way for long enough that five backend files were written
    # and committed without ever being compiled. Clearing `.build` did not help
    # and looked like it should -- the first error named a stale
    # `SwiftSyntax.swiftmodule` in the build directory, which is a symptom.
    #
    # A matching toolchain was installed all along, in ~/Library/Developer/
    # Toolchains. This finds one whose version matches the SDK's and selects it;
    # if there is none it says so rather than letting the module-format errors
    # be the message.
    #
    # **主機 toolchain 必須與 Android SDK 的 Swift 版本相符**，而當它們不符時，失敗會是一整面
    # 「module compiled with Swift X cannot be imported by the Swift Y compiler」的牆，指著一些
    # 本 repository 中沒有人寫過的檔案。
    #
    # 2026-09-11 量到:主機的 `swift` 是 6.4，安裝的 SDK 是
    # `swift-6.3.3-RELEASE_android.artifactbundle`，而每一次 Android 建置都以那種方式失敗——久到
    # 有五個 backend 檔案被寫出來、提交，卻從未被編譯過。清掉 `.build` 沒有用，而它看起來應該有用:
    # 第一個錯誤指名的是建置目錄裡一個過期的 `SwiftSyntax.swiftmodule`——那是症狀。
    #
    # 而一個相符的 toolchain 一直都裝在 ~/Library/Developer/Toolchains 裡。此處會找出版本與該 SDK
    # 相符的那一個並選用它;若一個都沒有，它會**說出來**，而不是讓那些 module 格式錯誤去當訊息。
    if [ -z "${TOOLCHAINS:-}" ]; then
        android_sdk_swift=$(
            ls -d "$HOME/Library/org.swift.swiftpm/swift-sdks/"*android.artifactbundle 2>/dev/null                 | head -1 | sed -E 's|.*/swift-([0-9.]+)-.*|\1|'
        )
        if [ -n "$android_sdk_swift" ]; then
            host_swift=$("$swift_bin" --version 2>/dev/null | sed -nE 's/.*Apple Swift version ([0-9.]+).*/\1/p' | head -1)
            if [ "$host_swift" != "$android_sdk_swift" ]; then
                for toolchain in "$HOME/Library/Developer/Toolchains/"*.xctoolchain; do
                    [ -x "$toolchain/usr/bin/swift" ] || continue
                    toolchain_swift=$("$toolchain/usr/bin/swift" --version 2>/dev/null | sed -nE 's/.*Apple Swift version ([0-9.]+).*/\1/p' | head -1)
                    if [ "$toolchain_swift" = "$android_sdk_swift" ]; then
                        export TOOLCHAINS=$(plutil -extract CFBundleIdentifier raw "$toolchain/Info.plist" 2>/dev/null)
                        echo "==> Android SDK is Swift $android_sdk_swift and the host is $host_swift; using toolchain $TOOLCHAINS"
                        break
                    fi
                done
                if [ -z "${TOOLCHAINS:-}" ]; then
                    echo "!! The Android SDK is Swift $android_sdk_swift and this host's swift is $host_swift." >&2
                    echo "!! No toolchain in ~/Library/Developer/Toolchains matches the SDK, so the build" >&2
                    echo "!! below will fail with \"module compiled with Swift $android_sdk_swift cannot be imported\"." >&2
                    echo "!! Install a Swift $android_sdk_swift toolchain, or an Android SDK built for $host_swift." >&2
                fi
            fi
        fi
    fi

    export ANDROID_SDK_ROOT="$android_sdk_root"
    export ANDROID_NDK_HOME="$android_ndk_home"
    export ANDROID_NDK_ROOT="$android_ndk_home"
    for app_name in $app_names; do
        echo "==> Compiling $app_name for Android ($android_triple)"
        SCUI_ANDROID=1 "$swift_bin" build \
            --build-system "$android_build_system" \
            --package-path "$package_dir" \
            --product "$app_name" \
            --swift-sdk "$android_triple" \
            -c "$build_config"
        android_binary="$package_dir/.build/$android_triple/$build_config/$app_name"
        [ -f "$android_binary" ] || {
            echo "Build succeeded but Android executable was not found: $android_binary" >&2
            exit 1
        }
        android_output="$output_dir/${app_name}-android"
        rm -f "$android_output"
        cp "$android_binary" "$android_output"
        chmod +x "$android_output"
        echo "    -> $android_output"
        manifest_record "${app_name}-android" "$app_name" android android
    done
    manifest_summary
    echo "Done. Android build tree: $package_dir/.build"
    exit 0
fi

# NOTE: linking these as GUI-subsystem executables
# (-Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup) removes the
# console window that Explorer opens alongside the app, but it makes things
# worse rather than better while the app still spawns children through
# Foundation's Process: that passes only CREATE_UNICODE_ENVIRONMENT, never
# CREATE_NO_WINDOW, and offers no way to change it. A console child inherits its
# parent's console when there is one and creates its own window when there is
# not, so removing P6's console gives ffmpeg and ffplay a console window each,
# visible for as long as they run. Suppressing those needs the children to be
# spawned with CreateProcessW and CREATE_NO_WINDOW instead of Foundation.
# 註：把這些連結成 GUI 子系統的執行檔
# （-Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup）雖然可以消掉檔案
# 總管啟動時一併開出的主控台視窗，但只要程式仍以 Foundation 的 Process 產生子行程，
# 結果反而更糟：它只傳 CREATE_UNICODE_ENVIRONMENT、不傳 CREATE_NO_WINDOW，也沒有
# 提供修改的途徑。主控台子行程在父行程有主控台時會繼承，沒有時則自己開一個視窗；
# 因此拿掉 P6 的主控台，會讓 ffmpeg 與 ffplay 各自開出一個、且在其執行期間都存在的
# 主控台視窗。要抑制它們，必須改以 CreateProcessW 搭配 CREATE_NO_WINDOW 產生子行程，
# 而非使用 Foundation。
if [ "$target_platform" = "ios" ]; then
    if [ "$(uname -s)" != "Darwin" ]; then
        echo "-ios requires macOS" >&2
        exit 1
    fi

    # Provision the simulator before building rather than after: a missing
    # device is the common case on a fresh machine, and finding out only once
    # the build has finished wastes several minutes.
    # 先備妥模擬器再建置：全新機器上最常見的情況就是尚無裝置，若等到建置完成才
    # 發現，會白白浪費數分鐘。
    echo "==> Checking the iOS build environment"
    # This helper is a zsh script: it uses zsh path modifiers and zsh arrays.
    # Invoke it with its declared interpreter instead of `sh`, which makes
    # `${0:a}` fail under shells that do not support zsh modifiers.
    # 此輔助腳本是 zsh 腳本：使用 zsh 路徑修飾語與 zsh 陣列。必須使用其宣告的
    # interpreter，不可用 `sh`，否則不支援 zsh 修飾語的 shell 會讓 `${0:a}` 失敗。
    if ! zsh "$script_dir/install_tools_ios.zsh"; then
        echo "iOS environment is not ready; see the messages above" >&2
        exit 1
    fi

    # Swift Bundler produces the .app bundle that a bare xcodebuild cannot: it
    # writes the Info.plist and bundle identifier that simctl requires. It lives
    # in Vendor/swift-bundler as a submodule; build it via the Android installer
    # script, which already knows how to patch its ZIPFoundationModern
    # dependency for Swift 6.3+.
    # Swift Bundler 能產生單靠 xcodebuild 無法得到的 .app bundle：它會寫入 simctl
    # 所需的 Info.plist 與 bundle identifier。它以 submodule 形式位於
    # Vendor/swift-bundler，可透過 Android 安裝腳本建置，該腳本已知道如何為
    # Swift 6.3+ 修補其 ZIPFoundationModern 依賴。
    sim_device="${IOS_SIM_DEVICE:-swift-cross-ui}"
    bundler_bin="$repo_root/swift-bundler"
    if [ ! -x "$bundler_bin" ]; then
        echo "Swift Bundler is required to build an installable iOS app." >&2
        echo "Build it with:" >&2
        echo "  bash Scripts/build-tool-install-android-on-Mac.sh" >&2
        exit 1
    fi

    for app_name in $app_names; do
        echo "==> Bundling $app_name for the iOS Simulator"
        (
            cd "$package_dir"
            "$bundler_bin" bundle "$app_name" \
                --platform iOSSimulator \
                -c "$build_config"
        )

        app_bundle="$package_dir/.build/bundler/apps/$app_name/$app_name.app"
        if [ -d "$app_bundle" ]; then
            ios_output="$output_dir/${app_name}-ios.app"
            rm -rf "$ios_output"
            cp -R "$app_bundle" "$ios_output"
            echo "    -> $ios_output"
            manifest_record "${app_name}-ios.app" "$app_name" ios uikit
        else
            echo "    Bundling reported success but no .app was found at $app_bundle" >&2
            exit 1
        fi
    done

    manifest_summary
    cat <<EOF_IOS
Done. Output directory: $output_dir

Install and launch on the simulator:

  xcrun simctl boot "$sim_device"
  open -a Simulator
  xcrun simctl install "$sim_device" "$output_dir/<app>-ios.app"
  xcrun simctl launch "$sim_device" dev.swiftcrossui.testapp.<app>
EOF_IOS
    exit 0
fi

for app_name in $app_names; do
    echo "==> Compiling $app_name"
    "$swift_bin" build \
        --package-path "$package_dir" \
        --product "$app_name" \
        -c "$build_config" \
        "${debug_feature_flags[@]}" \
        "${gtk_build_flags[@]}"

    # On Windows the same app name can be built against either backend, and the
    # two executables are indistinguishable once copied here. That has already
    # cost real time: a wincap capture matched a window by title and photographed
    # a leftover GTK process while the WinUI build was the thing under test, and
    # the resulting screenshot looked like a perfectly good result. So the
    # backend goes in the filename.
    #
    # Windows only. On Linux and macOS a build is one backend by construction --
    # there is no second one to confuse it with -- and suffixing there would
    # break every path that already names the plain executable for no gain.
    #
    # 在 Windows 上，同一個 app 名稱可以對兩個 backend 各建置一次，而複製到此處之後，兩個執行檔
    # 完全無法分辨。這已經造成過實際損失：wincap 依標題比對視窗，拍到了殘留的 GTK process，而當時
    # 受測的是 WinUI 建置——那張截圖看起來完全像一個正常的結果。因此把 backend 放進檔名。
    #
    # 僅限 Windows。Linux 與 macOS 上，一次建置在結構上就只有一個 backend，沒有第二個可混淆；在那裡
    # 加後綴只會弄壞每一條已經以純檔名指涉執行檔的路徑，而毫無所得。
    # The suffix and the manifest's `backend` column answer the same question,
    # so they are decided in one place. They are not the same string: only
    # Windows has two backends and therefore a suffix, while the manifest names
    # a backend on every platform, because a row that said only "the default"
    # would need the host to interpret it -- the exact property that made the
    # suffix-less .compile-work directory undeletable.
    # 後綴與 manifest 的 `backend` 欄回答同一個問題，因此在同一處決定。兩者不是同一個字串：
    # 只有 Windows 有兩個 backend、因而才有後綴，而 manifest 在每個平台都指名 backend——
    # 因為一列只寫「預設」的紀錄需要靠主機來解讀，而那正是讓無後綴的 .compile-work 目錄
    # 沒人敢刪的那個性質。
    if [ "$force_gtk4" -eq 1 ]; then
        backend_suffix="-gtk4"
        manifest_backend="gtk4"
    else
        backend_suffix="-WinUI"
        case "$manifest_host_os" in
            macos) manifest_backend="appkit" ;;
            linux) manifest_backend="gtk4" ;;
            *) manifest_backend="WinUI" ;;
        esac
    fi

    exe_path=""
    triple_dir="$(find "$package_dir/.build" -maxdepth 1 -type d -name '*-*-*' | head -n 1 || true)"
    if [ -n "$triple_dir" ] && [ -f "$triple_dir/$build_config/$app_name.exe" ]; then
        exe_path="$triple_dir/$build_config/$app_name.exe"
        output_path="$output_dir/$app_name$backend_suffix.exe"
    elif [ -n "$triple_dir" ] && [ -f "$triple_dir/$build_config/$app_name" ]; then
        exe_path="$triple_dir/$build_config/$app_name"
        output_path="$output_dir/$app_name"
    elif [ -f "$package_dir/.build/$build_config/$app_name.exe" ]; then
        exe_path="$package_dir/.build/$build_config/$app_name.exe"
        output_path="$output_dir/$app_name$backend_suffix.exe"
    elif [ -f "$package_dir/.build/$build_config/$app_name" ]; then
        exe_path="$package_dir/.build/$build_config/$app_name"
        output_path="$output_dir/$app_name"
    else
        echo "Build succeeded but executable was not found for $app_name" >&2
        exit 1
    fi

    rm -f "$output_path"
    cp "$exe_path" "$output_path"
    echo "    -> $output_path"
    manifest_record "$(basename "$output_path")" "$app_name" \
        "$manifest_host_os" "$manifest_backend"

    for resource_dir in \
        "$triple_dir/$build_config/swift-winui_CWinAppSDK.resources" \
        "$triple_dir/$build_config/swift-winui_CWinAppSDK.bundle" \
        "$package_dir/.build/$build_config/swift-winui_CWinAppSDK.resources" \
        "$package_dir/.build/$build_config/swift-winui_CWinAppSDK.bundle"
    do
        if [ -d "$resource_dir" ]; then
            resource_name="$(basename "$resource_dir")"
            rm -rf "$output_dir/$resource_name"
            cp -R "$resource_dir" "$output_dir/$resource_name"
            echo "    -> $output_dir/$resource_name"
            break
        fi
    done

    if [ "$target_platform" = "host" ] && [ "$force_gtk4" -eq 0 ] && [ "${output_path:e}" = "exe" ]; then
        win2d_dll="${WIN2D_DLL:-}"
        if [ -z "$win2d_dll" ]; then
            win2d_dll="$(find "$HOME/.nuget/packages/microsoft.graphics.win2d" \
                -path '*/runtimes/win-x64/native/Microsoft.Graphics.Canvas.dll' \
                -print 2>/dev/null | sort -V | tail -n 1 || true)"
        fi
        if [ -n "$win2d_dll" ] && [ -f "$win2d_dll" ]; then
            cp "$win2d_dll" "$output_dir/Microsoft.Graphics.Canvas.dll"
            echo "    -> $output_dir/Microsoft.Graphics.Canvas.dll"
        fi
    fi
done

manifest_summary
echo "Done. Output directory: $output_dir"
