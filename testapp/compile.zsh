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
# Per-pixel work such as P6's RGBA conversion is dramatically slower without
# optimisation, so allow release builds: BUILD_CONFIG=release sh compile.zsh P6
build_config="${BUILD_CONFIG:-debug}"
needs_image_formats=0
target_platform="host"

# -ios switches to an iOS Simulator build. It cannot go through `swift build`:
# passing an iOS SDK with -Xswiftc applies it to every target, including
# SwiftCrossUIMacrosPlugin, which is a compile-time tool that has to be built
# for the host, and the link then fails. xcodebuild distinguishes the two, so
# that is what the iOS path uses.
# -ios 會切換為 iOS 模擬器建置。此路徑無法使用 `swift build`：以 -Xswiftc 傳入
# iOS SDK 會套用到所有 target，包含必須為主機建置的編譯期工具
# SwiftCrossUIMacrosPlugin，連結因而失敗。xcodebuild 能區分兩者，故 iOS 路徑改用它。
remaining_args=""
for arg in "$@"; do
    case "$arg" in
        -ios) target_platform="ios" ;;
        *) remaining_args="$remaining_args $arg" ;;
    esac
done
if [ "$target_platform" = "ios" ]; then
    # shellcheck disable=SC2086
    set -- $remaining_args
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
    if ! sh "$script_dir/install_tools_ios.sh"; then
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
        -c "$build_config"

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
