// swift-tools-version:5.10

import CompilerPluginSupport
import Foundation
import PackageDescription

// ## Compile-time environment options
//
// - SCUI_DEFAULT_BACKEND : Sets the backend used by DefaultBackend
// - SCUI_LIBRARY_TYPE : Can be set to `static`, `dynamic` or `auto`, and defaults
//     to `auto`. Use this to control the linking mode of all library products
//     exposed by this package.
// - SCUI_HOT_RELOADING/SWIFT_BUNDLER_HOT_RELOADING : Enables hot reloading
//     support code if `1`. If not present then the output of the #hotReloadable and
//     @HotReloadable gets compiled out.
// - SCUI_BENCHMARK_VIZ : If `1`, LayoutPerformanceBenchmark gets compiled in
//     visualization mode instead of benchmarking mode. It will use DefaultBackend
//     to visualize a benchmark layout of your choosing (chosen at runtime via stdin).
// - SCUI_ANDROID : If `1`, includes AndroidBackend and AndroidBackendShim in the
//     package. Set it alongside `--swift-sdk <android-triple>` when cross-compiling
//     for Android. It is off by default because AndroidBackendShim is a C target
//     that includes <android/log.h>, which only the Android NDK provides: leaving
//     it in the package makes every non-Android build fail while scanning it.
// - SCUI_HOST_BACKENDS_ONLY : If `1`, drops the backends that cannot compile for
//     the host (WinUIBackend and UIKitBackend on macOS) from the package. For
//     running the test suite on a host that is not the target platform; see the
//     note beside the flag below.

let invokedByXcode: Bool
#if os(macOS)
    import Darwin

    let ppid = getppid()
    let PROC_PIDPATHINFO_MAXSIZE = 4096
    let pathBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: PROC_PIDPATHINFO_MAXSIZE)
    proc_pidpath(ppid, UnsafeMutableRawPointer(pathBuffer), UInt32(PROC_PIDPATHINFO_MAXSIZE))
    let parentProcessPath = String(cString: pathBuffer)
    let parentProcessName = URL(fileURLWithPath: parentProcessPath).lastPathComponent
    invokedByXcode = parentProcessName == "xcodebuild" || parentProcessName == "Xcode"
#else
    invokedByXcode = false
#endif

let env = ProcessInfo.processInfo.environment
let androidBackendSupported: Bool
#if compiler(>=6.2)
    // A manifest can't observe the target platform: when SwiftPM compiles it, the
    // arguments hold only -fileno/-context and the environment exposes just a host
    // SDKROOT, so `--swift-sdk aarch64-unknown-linux-android28` is invisible here.
    // Android targets are therefore opt-in. Including them unconditionally breaks
    // every other platform, because AndroidBackendShim is a C target including
    // <android/log.h>, and the build system scans C targets it will never link.
    //
    // xcodebuild can't handle non-Apple platform conditional dependencies for some weird
    // reason, so we have to remove AndroidBackend when we detect that we're being built
    // by xcodebuild.
    androidBackendSupported = !invokedByXcode && env["SCUI_ANDROID"] == "1"
#else
    androidBackendSupported = false
#endif

// `swift test` builds every target in the package, not just the test bundle and
// what it imports, so a target that cannot compile for the host stops the suite
// before a single test runs. On macOS two cannot: WinUIBackend pulls in
// swift-winui, whose CWinRT needs the Windows SDK's <wtypesbase.h>, and
// UIKitBackend imports UIKit, which has no macOS slice. Neither is fixable by
// installing anything.
//
// Conditioning their *dependencies* on a platform does not help -- that was
// tried, and the note on the WinUIBackend target below records why. What does
// help is not declaring the targets at all, which is what this gate does.
//
// It is opt-in, like SCUI_ANDROID above, and for the same reason: a gate that
// changes the manifest by default would change it for Windows, Linux, CI and
// the iOS build too, all of which need these targets. Set it only for a host
// test run:
//
//   SCUI_HOST_BACKENDS_ONLY=1 swift test -Xcc -I$(brew --prefix)/include
//
// testapp/install_tool_mac.zsh prints that command and explains the -Xcc flag.
//
// `swift test` 會建置套件中的每一個 target，而非僅測試 bundle 及其 import 的部分，
// 因此只要有一個 target 無法為主機平台編譯，整個測試套件在任何測試執行之前就會中止。
// 在 macOS 上有兩個屬於此類：WinUIBackend 會引入 swift-winui，其 CWinRT 需要 Windows
// SDK 的 <wtypesbase.h>；UIKitBackend 則 import UIKit，而 UIKit 沒有 macOS 切片。
// 這兩者都不是靠安裝任何東西能解決的。
//
// 為其「依賴項」加上平台條件並無幫助——這已試過，下方 WinUIBackend target 處的註解記錄了
// 原因。真正有效的是根本不宣告這些 target，而這正是本開關的作用。
//
// 它採用 opt-in，與上方的 SCUI_ANDROID 相同，理由也相同：預設就改變 manifest 會連
// Windows、Linux、CI 與 iOS 建置一併改變，而那些場合都需要這些 target。僅在主機端執行
// 測試時設定它（指令見上）。testapp/install_tool_mac.zsh 會印出該指令並說明 -Xcc 旗標。
let hostBackendsOnly = env["SCUI_HOST_BACKENDS_ONLY"] == "1"

var defaultBackendDependencies: [Target.Dependency]
if let backend = env["SCUI_DEFAULT_BACKEND"] {
    defaultBackendDependencies = [.target(name: backend)]
} else {
    // With no #if here, Windows and Linux dependencies are also compiled when building for
    // UIKit platforms.
    #if os(macOS)
        defaultBackendDependencies = [
            .target(name: "AppKitBackend", condition: .when(platforms: [.macOS])),
        ]
        // Named here only when the target still exists. A dependency on a target
        // the manifest has removed is a hard error, so the gate has to reach the
        // dependency list as well as the target list.
        // 僅在該 target 仍存在時才列出。依賴一個已被 manifest 移除的 target 會直接報錯，
        // 因此此開關必須同時作用於依賴清單與 target 清單。
        if !hostBackendsOnly {
            defaultBackendDependencies += [
                .target(
                    name: "UIKitBackend",
                    condition: .when(platforms: [.iOS, .tvOS, .macCatalyst, .visionOS])
                )
            ]
        }
    #else
        defaultBackendDependencies = [
            .target(name: "WinUIBackend", condition: .when(platforms: [.windows])),
            .target(name: "GtkBackend", condition: .when(platforms: [.linux])),
        ]
    #endif

    if androidBackendSupported {
        defaultBackendDependencies += [
            .target(
                name: "AndroidBackend",
                condition: .when(platforms: [.android])
            ),
        ]
    }
}

let hotReloadingEnabled: Bool
#if os(Windows)
    hotReloadingEnabled = false
#else
    hotReloadingEnabled =
        env["SWIFT_BUNDLER_HOT_RELOADING"] == "1"
            || env["SCUI_HOT_RELOADING"] == "1"
#endif

var swiftSettings: [SwiftSetting] = []
if hotReloadingEnabled {
    swiftSettings += [
        .define("HOT_RELOADING_ENABLED")
    ]
}

// SCUI_DEBUG decides whether a binary can be debugged and driven at all: the
// `--debug` flag, the diagnostic messages, and action-file replay.
//
// Off by default, and off means absent rather than disabled. See
// Sources/DebugFeatures/README.md -- the size saving is the lesser reason; the
// point is that a shipped application should not carry a way to synthesise
// clicks and keystrokes into whatever window is in front of it.
//
// SCUI_DEBUG 決定一個執行檔究竟能否被除錯與驅動：`--debug` 旗標、診斷訊息，以及動作檔重放。
//
// 預設為關閉，而「關閉」意味著「不存在」而非「已停用」。詳見
// Sources/DebugFeatures/README.md——體積是次要理由；重點在於，已出貨的應用程式不應該攜帶一套
// 「向當下位於前方的任何視窗合成點擊與按鍵」的手段。
let debugFeaturesEnabled = env["SCUI_DEBUG"] == "1" || env["SCUI_DEBUG"] == "true"
var debugSwiftSettings: [SwiftSetting] = swiftSettings
if debugFeaturesEnabled {
    debugSwiftSettings += [.define("SCUI_DEBUG")]
}

var libraryType: Product.Library.LibraryType?
switch env["SCUI_LIBRARY_TYPE"] {
    case "static":
        libraryType = .static
    case "dynamic":
        libraryType = .dynamic
    case "auto":
        libraryType = nil
    case .some:
        print("Invalid SCUI_LIBRARY_TYPE, expected static, dynamic, or auto")
        libraryType = nil
    case nil:
        if hotReloadingEnabled {
            libraryType = .dynamic
        } else {
            libraryType = nil
        }
}

// When SCUI_BENCHMARK_VIZ is present, we include the DefaultBackend to allow
// viewing of each benchmark test case with an actual backend.
let additionalLayoutPerformanceBenchmarkDependencies: [Target.Dependency]
let layoutPerformanceSwiftSettings: [SwiftSetting]
if env["SCUI_BENCHMARK_VIZ"] == "1" {
    additionalLayoutPerformanceBenchmarkDependencies = ["DefaultBackend"]
    layoutPerformanceSwiftSettings = [.define("BENCHMARK_VIZ")]
} else {
    additionalLayoutPerformanceBenchmarkDependencies = []
    layoutPerformanceSwiftSettings = []
}

let package = Package(
    name: "swift-cross-ui",
    platforms: [.macOS(.v11), .iOS(.v13), .tvOS(.v13), .macCatalyst(.v13), .visionOS(.v1)],
    products: [
        .library(name: "SwiftCrossUI", type: libraryType, targets: ["SwiftCrossUI"]),
        .library(name: "AppKitBackend", type: libraryType, targets: ["AppKitBackend"]),
        .library(name: "GtkBackend", type: libraryType, targets: ["GtkBackend"]),
        .library(name: "WinUIBackend", type: libraryType, targets: ["WinUIBackend"]),
        .library(name: "DefaultBackend", type: libraryType, targets: ["DefaultBackend"]),
        .library(name: "UIKitBackend", type: libraryType, targets: ["UIKitBackend"]),
        .library(name: "Gtk", type: libraryType, targets: ["Gtk"]),
        .library(name: "InputEvent", type: libraryType, targets: ["InputEvent"]),
        .library(name: "DebugFeatures", type: libraryType, targets: ["DebugFeatures"]),
        .executable(name: "GtkExample", targets: ["GtkExample"]),
        // CursesBackend, QtBackend and LVGLBackend were commented out here and
        // in the target list. Removed rather than left as text: a commented
        // declaration reads as "temporarily disabled" and invites someone to
        // uncomment it, and none of the three can be: their package
        // dependencies -- TermKit, qlift, LVGLSwift -- are not declared either,
        // so uncommenting produces an unresolvable manifest rather than a
        // build.
        //
        // Their source directories are still in Sources/ and are untouched by
        // this. Deleting them is a separate decision.
    ],
    dependencies: [
        .package(
            url: "https://github.com/CoreOffice/XMLCoder",
            from: "0.17.1"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-docc-plugin",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            "601.0.0"..<"604.0.0"
        ),
        .package(
            url: "https://github.com/stackotter/swift-macro-toolkit",
            .upToNextMinor(from: "0.9.0")
        ),
        .package(
            url: "https://github.com/stackotter/swift-image-formats",
            .upToNextMinor(from: "0.5.0")
        ),
        .package(
            url: "https://github.com/moreSwift/swift-winui",
            .upToNextMinor(from: "0.2.1")
        ),
        .package(
            url: "https://github.com/stackotter/swift-benchmark",
            .upToNextMinor(from: "0.2.0")
        ),
        .package(
            url: "https://github.com/swhitty/swift-mutex",
            .upToNextMinor(from: "0.0.6")
        ),
        // .package(
        //     url: "https://github.com/stackotter/TermKit",
        //     revision: "163afa64f1257a0c026cc83ed8bc47a5f8fc9704"
        // ),
        // .package(
        //     url: "https://github.com/PADL/LVGLSwift",
        //     revision: "19c19a942153b50d61486faf1d0d45daf79e7be5"
        // ),
        // .package(
        //     url: "https://github.com/Longhanks/qlift",
        //     revision: "ddab1f1ecc113ad4f8e05d2999c2734cdf706210"
        // ),
    ],
    targets: [
        .target(
            name: "SwiftCrossUI",
            dependencies: [
                "SwiftCrossUIMacrosPlugin",
                "SwiftCrossUIMetadataSupport",
                .product(name: "ImageFormats", package: "swift-image-formats"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Mutex", package: "swift-mutex"),

                // This import is purely required to fix a linker issue and a plugin build
                // error that occur on macOS when building for non-Android platforms now that
                // we've added the AndroidBackend. Providing the '--disable-experimental-prebuilts'
                // flag when building SwiftCrossUI apps doesn't seem to be sufficient to fix
                // the issues, even though I would've thought that was the effect that adding
                // this dependency has.
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            exclude: [
                "Builders/ViewBuilder.swift.gyb",
                "Builders/SceneBuilder.swift.gyb",
                "Builders/TableRowBuilder.swift.gyb",
                "Views/TupleView.swift.gyb",
                "Views/TupleViewChildren.swift.gyb",
                "Views/TableRowContent.swift.gyb",
                "Scenes/TupleScene.swift.gyb",
            ],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "InputEventTests",
            dependencies: ["InputEvent"]
        ),
        .testTarget(
            name: "SwiftCrossUITests",
            dependencies: [
                "SwiftCrossUI",
                "DummyBackend",
                "SwiftCrossUIMacrosPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .target(name: "AppKitBackend", condition: .when(platforms: [.macOS])),
            ]
        ),
        .target(name: "SwiftCrossUIMetadataSupport"),
        .target(
            name: "DefaultBackend",
            dependencies: defaultBackendDependencies
        ),
        // InputEvent only when the debug features are on, exactly as
        // GtkBackend does below and for the same reason -- see the note there.
        // AppKitBackend gained the dependency when -actionfile learned to
        // replay on macOS.
        // 僅在 debug 功能開啟時才依賴 InputEvent，與下方 GtkBackend 的做法及理由完全相同——見該處
        // 的說明。AppKitBackend 是在 -actionfile 學會於 macOS 上重放時取得此依賴的。
        .target(
            name: "AppKitBackend",
            dependencies: ["SwiftCrossUI"] + (debugFeaturesEnabled ? ["InputEvent"] : []),
            swiftSettings: debugSwiftSettings
        ),
        .target(
            name: "GtkBackend",
            // InputEvent only when the debug features are on. Dropping the
            // dependency rather than only the code is the whole reason this
            // lives in the manifest: SwiftPM cannot make a target conditional,
            // but the manifest is Swift, so the list is built from the
            // environment and a release build does not link the module at all.
            // 僅在 debug 功能開啟時才依賴 InputEvent。「連依賴一起移除」而非「只移除程式碼」，
            // 正是此邏輯必須位於 manifest 中的全部理由：SwiftPM 無法讓 target 帶條件，但 manifest
            // 本身就是 Swift，因此該清單可由環境變數建構，release 建置根本不會連結該模組。
            dependencies: ["SwiftCrossUI", "Gtk", "CGtk", "DebugFeatures"]
                + (debugFeaturesEnabled ? ["InputEvent"] : []),
            swiftSettings: debugSwiftSettings
        ),
        .systemLibrary(
            name: "CGtk",
            pkgConfig: "gtk4",
            providers: [
                .brew(["gtk4"]),
                .apt(["libgtk-4-dev clang"]),
            ]
        ),
        .target(
            name: "Gtk",
            dependencies: ["CGtk", "GtkCHelpers"],
            exclude: ["LICENSE.md"]
        ),
        .executableTarget(
            name: "GtkExample",
            dependencies: ["Gtk"],
            resources: [.copy("GTK.png")]
        ),
        // Gtk helpers that we've implemented in C because they'd be difficult
        // or impossible to recreate in Swift
        .target(
            name: "GtkCHelpers",
            dependencies: ["CGtk"],
            // libepoxy, for the NV12 shader in gtk_nv12_gl.c. Not a new
            // dependency: GTK 4 already links it for its own renderer, so it is
            // present wherever GTK is. It is named explicitly because gtk4.pc
            // lists it as a private requirement, which pkg-config does not put
            // into --libs for a dynamically linked consumer.
            // libepoxy，供 gtk_nv12_gl.c 中的 NV12 shader 使用。這並非新的依賴：GTK 4 本身
            // 就為其算繪器連結它，因此凡有 GTK 之處必有它。此處明確指名，是因為 gtk4.pc 將
            // 它列為 private requirement，而 pkg-config 不會把這類項目放進動態連結消費者的
            // --libs 中。
            linkerSettings: [.linkedLibrary("epoxy")]
        ),
        // Synthesised input, driven from a CSV file. Depends on nothing in this
        // package: it takes a window origin and a size and posts events, which
        // keeps it testable without a running app and stops backend concepts
        // leaking into it.
        //
        // README.md and plan/ are excluded because SwiftPM treats unrecognised
        // files in a target directory as resources and warns about them.
        .target(
            name: "InputEvent",
            exclude: ["README.md", "plan"]
        ),
        .target(
            name: "DebugFeatures",
            exclude: ["README.md"],
            swiftSettings: debugSwiftSettings
        ),
        .executableTarget(
            name: "GtkCodeGen",
            dependencies: [
                "XMLCoder",
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ],
            exclude: ["GirFiles"]
        ),
        .target(name: "UIKitBackend", dependencies: ["SwiftCrossUI"]),
        .target(
            name: "WinUIBackend",
            dependencies: [
                "SwiftCrossUI",
                "WinUIInterop",
                // Conditioning these on Windows was tried and did not help:
                // `swift test` builds every target in the package, so
                // WinUIBackend itself is compiled on Linux and swift-winui is
                // pulled in whatever the dependency conditions say. Tests run
                // on Windows instead. Left unconditional rather than carrying a
                // change that only looks like it does something.
                .product(name: "WinUI", package: "swift-winui"),
                .product(name: "UWP", package: "swift-winui"),
                .product(name: "CWinRT", package: "swift-winui"),
                .product(name: "WinAppSDK", package: "swift-winui"),
                .product(name: "WindowsFoundation", package: "swift-winui"),
                .product(name: "Mutex", package: "swift-mutex"),
            ] + (debugFeaturesEnabled ? ["InputEvent"] : []),
            swiftSettings: debugSwiftSettings,
            linkerSettings: [
                .linkedLibrary("d3d11", .when(platforms: [.windows])),
                .linkedLibrary("dxgi", .when(platforms: [.windows])),
            ]
        ),
        .target(
            name: "WinUIInterop",
            dependencies: []
        ),
        .target(name: "DummyBackend", dependencies: ["SwiftCrossUI"]),

        .executableTarget(
            name: "LayoutPerformanceBenchmark",
            dependencies: [
                .product(name: "Benchmark", package: "swift-benchmark"),
                "SwiftCrossUI",
                "DummyBackend",
            ] + additionalLayoutPerformanceBenchmarkDependencies,
            path: "Benchmarks/LayoutPerformanceBenchmark",
            swiftSettings: layoutPerformanceSwiftSettings
        ),
        .macro(
            name: "SwiftCrossUIMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "MacroToolkit", package: "swift-macro-toolkit"),
            ],
            swiftSettings: swiftSettings
        ),

    ]
)

// Newer versions of swift-log only support Swift >=6.1, and SwiftPM doesn't
// seem to want to use the tools-version of the package during resolution
// (even though I could swear it has in the past), so we have to change the
// version requirement based on compiler version.
#if compiler(<6.1)
    package.dependencies.append(
        .package(
            url: "https://github.com/apple/swift-log.git",
            .upToNextMinor(from: "1.6.4")
        )
    )
#else
    package.dependencies.append(
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.6.4"
        )
    )
#endif

// Declared unconditionally, unlike the Android targets below. SwiftPM prunes
// Package.resolved to the dependencies the manifest actually reaches, so gating
// these too made the lockfile depend on SCUI_ANDROID: resolving without it
// dropped nine Android pins (24 -> 15), and resolving with it put them back.
// Every ordinary build rewrote the file. Keeping the declarations here costs an
// unused dependency on non-Android hosts and keeps the lockfile stable.
package.dependencies += [
    .package(
        url: "https://github.com/moreSwift/AndroidKit",
        .upToNextMinor(from: "0.8.1")
    ),
    .package(
        url: "https://github.com/stackotter/swift-java",
        .upToNextMinor(from: "0.5.1")
    ),
]

// Add AndroidBackend if the Swift version is new enough and we're not using xcodebuild
if androidBackendSupported {
    package.products.append(
        .library(name: "AndroidBackend", type: libraryType, targets: ["AndroidBackend"])
    )

    package.targets += [
        .target(
            name: "AndroidBackend",
            dependencies: [
                "SwiftCrossUI",
                "AndroidBackendShim",
                .product(name: "Mutex", package: "swift-mutex"),

                // These two dependencies have to be marked as only included on Android
                // (even though this target is only used on Android) because SwiftPM requires
                // every library product to only include dependencies matching the package's
                // minimum platform requirements (even when not compiling said product)
                .product(
                    name: "AndroidKit",
                    package: "AndroidKit",
                    condition: .when(platforms: [.android])
                ),
                .product(
                    name: "SwiftJava",
                    package: "swift-java",
                    condition: .when(platforms: [.android])
                ),
            ],
            exclude: ["Kotlin"]
        ),
        .target(name: "AndroidBackendShim"),
    ]
}

// Remove the backends this host cannot compile. See SCUI_HOST_BACKENDS_ONLY at
// the top of this file for what this is for and why it is opt-in.
//
// Done here rather than by editing the literals above because `Package` is a
// class whose members are mutable, and the AndroidBackend block directly above
// already establishes that shape -- the arrays are built once and adjusted
// afterwards. The package *dependencies* are deliberately left in place: they
// are what Package.resolved is computed from, and dropping them here would make
// the resolved file drift between a normal build and a host test run. Nothing
// is built from a dependency no target names.
//
// 移除本主機無法編譯的 backend。用途與為何採 opt-in，見本檔開頭的 SCUI_HOST_BACKENDS_ONLY。
//
// 於此處處理而非直接修改上方的字面陣列，是因為 `Package` 是類別且其成員可變，而正上方的
// AndroidBackend 區塊已確立此種寫法——陣列先建好，之後再調整。套件層級的 dependencies 則
// 刻意保留：Package.resolved 是由它們計算而來，在此移除會使該檔在一般建置與主機測試執行
// 之間產生漂移。沒有任何 target 指名的 dependency 不會被建置。
if hostBackendsOnly {
    let unbuildableOnHost: Set<String> = ["WinUIBackend", "UIKitBackend"]
    package.targets.removeAll { unbuildableOnHost.contains($0.name) }
    package.products.removeAll { unbuildableOnHost.contains($0.name) }
}
