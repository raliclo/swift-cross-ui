#!/usr/bin/env sh
set -euo pipefail

# zsh does not split unquoted scalar expansions by default, while this POSIX
# script uses whitespace-delimited app name lists below.
if [ -n "${ZSH_VERSION:-}" ]; then
    setopt SH_WORD_SPLIT
fi

windows_path() {
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
# optimisation, so allow release builds: BUILD_CONFIG=release sh compile.sh P6
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
    name: "TestApps",
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

    sim_device="${IOS_SIM_DEVICE:-swift-cross-ui}"
    ios_config="$(printf '%s' "$build_config" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
    ios_derived="$compile_work_dir/ios-build"

    # A SwiftPM package exposes one scheme named after the package, not one per
    # executable target, so every app in Sources/ is compiled together. Passing
    # an app name as -scheme fails with "Supported platforms for the buildables
    # in the current scheme is empty", which reads like a platform problem but
    # only means the scheme does not exist.
    # SwiftPM package 只會提供一個與套件同名的 scheme，而非每個可執行 target 各一個，
    # 因此 Sources/ 下的所有 app 會一起編譯。若把 app 名稱當作 -scheme 傳入，會出現
    # 「Supported platforms for the buildables in the current scheme is empty」，
    # 該訊息看似平台問題，實際上只代表該 scheme 不存在。
    # xcodebuild resolves the scheme from the working directory, so it has to run
    # inside the generated package. From the repo root it finds the swift-cross-ui
    # workspace instead and reports that no TestApps scheme exists.
    # xcodebuild 會依工作目錄解析 scheme，因此必須在產生出來的套件目錄內執行。
    # 若從專案根目錄執行，它會找到 swift-cross-ui 的 workspace，並回報找不到
    # TestApps scheme。
    echo "==> Compiling for the iOS Simulator:$app_names"
    (
        cd "$package_dir"
        xcodebuild \
            -scheme TestApps \
            -destination "platform=iOS Simulator,name=$sim_device" \
            -derivedDataPath "$ios_derived" \
            -configuration "$ios_config" \
            build \
            | grep -E "error:|BUILD" || true
    )

    products="$ios_derived/Build/Products/${ios_config}-iphonesimulator"
    for app_name in $app_names; do
        if [ -d "$products/$app_name.app" ]; then
            rm -rf "$output_dir/$app_name.app"
            cp -R "$products/$app_name.app" "$output_dir/$app_name.app"
            echo "    -> $output_dir/$app_name.app"
        elif [ -f "$products/$app_name" ]; then
            # Compiled, but a bare Mach-O executable rather than a bundle. A
            # SwiftPM executableTarget has no Info.plist or bundle identifier,
            # so simctl cannot install it. Say so instead of implying otherwise.
            # 已編譯，但產物是裸的 Mach-O 執行檔而非 bundle。SwiftPM 的
            # executableTarget 沒有 Info.plist 與 bundle identifier，simctl 無法安裝，
            # 因此據實說明而非含混帶過。
            cp "$products/$app_name" "$output_dir/$app_name-ios"
            echo "    -> $output_dir/$app_name-ios (executable, not an installable .app)"
            echo "       To install on the simulator, bundle it:" >&2
            echo "         ./swift-bundler bundle $app_name --platform iOS" >&2
        else
            echo "    No product found for $app_name in $products" >&2
        fi
    done

    echo "Done. Output directory: $output_dir"
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
