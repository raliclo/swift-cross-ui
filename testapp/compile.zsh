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
            "" \
            "With no app names, every P*.swift is built." \
            "未指定 app 名稱時，會建置所有 P*.swift。" \
            "Release by default; BUILD_CONFIG=debug for an unoptimised build." \
            "預設 release；需要未最佳化 build 時設定 BUILD_CONFIG=debug。"
        exit 0
        ;;
esac

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
    compile_work_dir="$(windows_path "$script_dir/.compile-work")"
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
scui_debug_value="${SCUI_DEBUG:-}"

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

targets=""
for app_name in $manifest_app_names; do
    targets="$targets
        .executableTarget(
            name: \"$app_name\",
            dependencies: testAppDependencies
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
    done
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
        else
            echo "    Bundling reported success but no .app was found at $app_bundle" >&2
            exit 1
        fi
    done

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
    if [ "$force_gtk4" -eq 1 ]; then
        backend_suffix="-gtk4"
    else
        backend_suffix="-WinUI"
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

echo "Done. Output directory: $output_dir"
