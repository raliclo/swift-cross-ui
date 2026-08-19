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
compile_work_dir="$(windows_path "${COMPILE_WORK_DIR:-$script_dir/.compile-work}")"
package_dir="$compile_work_dir/TestApps"
sources_root="$package_dir/Sources"

swift_bin="${SWIFT_BIN:-swift}"
# Test apps default to release so GUI startup and interaction latency reflect
# normal usage. App-specific diagnostics should be controlled with flags such
# as --debug instead of relying on unoptimized debug builds.
build_config="${BUILD_CONFIG:-release}"
needs_image_formats=0
target_platform="host"

# -gtk4 forces GtkBackend everywhere, including Windows, where WinUIBackend is
# otherwise the default. It is opt-in rather than automatic because P0-P16 are
# WinUI repro apps: switching them silently would make them reproduce nothing.
# WinUIBackend stays the baseline.
#
# DefaultBackend already prefers Gtk over WinUI, so the flag does not select a
# backend directly -- it makes GtkBackend importable on Windows, and the
# existing preference order does the rest.
# -gtk4 會在所有平台強制使用 GtkBackend，包含原本預設為 WinUIBackend 的 Windows。此為
# 選擇性加入而非自動，因為 P0-P16 是 WinUI 的重現 app：若靜默切換，它們將什麼也重現不了。
# WinUIBackend 維持為 baseline。
#
# DefaultBackend 本來就把 Gtk 排在 WinUI 之前，因此本旗標並非直接選擇 backend——它讓
# GtkBackend 在 Windows 上成為可 import，其餘交由既有的優先順序決定。
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
case "${1:-}" in
    -h|--help)
        printf '%s\n' \
            "Usage: compile.zsh [-ios] [-gtk4] [P0 P1 ... Pn]" \
            "用法：compile.zsh [-ios] [-gtk4] [P0 P1 ... Pn]" \
            "" \
            "  -ios   Build for the iOS Simulator via xcodebuild." \
            "  -ios   透過 xcodebuild 為 iOS 模擬器建置。" \
            "  -gtk4  Force GtkBackend on every platform, Windows included." \
            "         Needs GTK 4; on Windows run install_gtk4_windows.zsh first." \
            "  -gtk4  在所有平台強制使用 GtkBackend，包含 Windows。" \
            "         需要 GTK 4；Windows 上請先執行 install_gtk4_windows.zsh。" \
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
windows_gtk_product=""
gtk_build_flags=()
if [ "$force_gtk4" -eq 1 ]; then
    windows_gtk_product='.product(name: "GtkBackend", package: "swift-cross-ui", condition: .when(platforms: [.windows])),'

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

    app_name="${app_file%.swift}"
    target_dir="$sources_root/$app_name"
    mkdir -p "$target_dir"
    cp "$source_path" "$target_dir/main.swift"

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

targets=""
for app_name in $app_names; do
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

cat > "$package_dir/Package.swift" <<EOF_PACKAGE
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
    .product(name: "AppKitBackend", package: "swift-cross-ui", condition: .when(platforms: [.macOS])),
    .product(name: "WinUIBackend", package: "swift-cross-ui", condition: .when(platforms: [.windows])),
    $windows_gtk_product
    // Gtk, not GtkBackend: what a test app needs on Linux is the window type
    // itself, to cast the backend's window out of the environment. DefaultBackend
    // already pulls GtkBackend in, but a cast has to name Gtk.ApplicationWindow
    // and that needs this module imported directly.
    // 這裡是 Gtk 而非 GtkBackend：測試 app 在 Linux 上需要的是視窗型別本身，用來把
    // backend 的視窗自 environment 轉型出來。DefaultBackend 已經帶入 GtkBackend，但
    // 轉型必須指名 Gtk.ApplicationWindow，因此需要直接 import 此模組。
    .product(name: "Gtk", package: "swift-cross-ui", condition: .when(platforms: [.linux])),
    $image_formats_product
    .product(name: "WinUI", package: "swift-winui", condition: .when(platforms: [.windows])),
    .product(name: "UWP", package: "swift-winui", condition: .when(platforms: [.windows])),
    .product(name: "WindowsFoundation", package: "swift-winui", condition: .when(platforms: [.windows])),
]

let package = Package(
    name: "$package_name",
    platforms: [.macOS(.v11), .iOS(.v13), .tvOS(.v13), .macCatalyst(.v13), .visionOS(.v1)],
    dependencies: [
        .package(path: "$repo_root"),
        $image_formats_package
        .package(
            url: "https://github.com/moreSwift/swift-winui",
            .upToNextMinor(from: "0.2.1")
        ),
    ],
    targets: [$targets
    ]
)
EOF_PACKAGE

# Swift Bundler needs a Bundler.toml to turn an executable target into an app
# bundle: a SwiftPM executable has no Info.plist or bundle identifier, so
# `simctl install` cannot accept it on its own. Generated alongside
# Package.swift so both stay in step with whichever apps were requested.
# Swift Bundler 需要 Bundler.toml 才能把可執行 target 打包成 app bundle：SwiftPM 的
# 可執行檔本身沒有 Info.plist 與 bundle identifier，simctl install 無法直接安裝。
# 此檔與 Package.swift 一同產生，確保兩者與所請求的 app 清單保持一致。
{
    printf 'format_version = 2\n'
    for app_name in $app_names; do
        printf '\n[apps.%s]\n' "$app_name"
        printf "identifier = 'dev.swiftcrossui.testapp.%s'\n" "$app_name"
        printf "product = '%s'\n" "$app_name"
        printf "version = '0.1.0'\n"
    done
} > "$package_dir/Bundler.toml"

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
    if ! sh "$script_dir/install_tools_ios.zsh"; then
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
            rm -rf "$output_dir/$app_name.app"
            cp -R "$app_bundle" "$output_dir/$app_name.app"
            echo "    -> $output_dir/$app_name.app"
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
  xcrun simctl install "$sim_device" "$output_dir/<app>.app"
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
        "${gtk_build_flags[@]}"

    exe_path=""
    triple_dir="$(find "$package_dir/.build" -maxdepth 1 -type d -name '*-*-*' | head -n 1 || true)"
    if [ -n "$triple_dir" ] && [ -f "$triple_dir/$build_config/$app_name.exe" ]; then
        exe_path="$triple_dir/$build_config/$app_name.exe"
        output_path="$output_dir/$app_name.exe"
    elif [ -n "$triple_dir" ] && [ -f "$triple_dir/$build_config/$app_name" ]; then
        exe_path="$triple_dir/$build_config/$app_name"
        output_path="$output_dir/$app_name"
    elif [ -f "$package_dir/.build/$build_config/$app_name.exe" ]; then
        exe_path="$package_dir/.build/$build_config/$app_name.exe"
        output_path="$output_dir/$app_name.exe"
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
done

echo "Done. Output directory: $output_dir"
