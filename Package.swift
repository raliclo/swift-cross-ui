// swift-tools-version:6.0

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
//     the host from the package -- which backends those are depends on the host.
//     For running the test suite; see the note beside the flag below.

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
// before a single test runs. Every host has some: WinUIBackend pulls in
// swift-winui, whose CWinRT needs the Windows SDK's <wtypesbase.h>; UIKitBackend
// imports UIKit; AppKitBackend imports AppKit; and GtkCHelpers includes
// <gtk/gtk.h>, which a bare `swift test` on Windows has no paths for. None of
// those headers is ours to supply -- they belong to the Windows SDK, to Apple's
// SDKs and to GTK -- so none of it is fixable by adding a file to this repo.
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
//   macOS    SCUI_HOST_BACKENDS_ONLY=1 swift test -Xcc -I$(brew --prefix)/include
//   Linux    SCUI_HOST_BACKENDS_ONLY=1 swift test
//   Windows  SCUI_HOST_BACKENDS_ONLY=1 swift test --scratch-path C:\scui-ht
//
// testapp/install_tool_mac.zsh prints the macOS command and explains its -Xcc
// flag. The Windows one needs a scratch path of its own for a reason unrelated
// to this gate: a -gtk4 build leaves GtkBackend in SwiftPM's incremental state,
// and the next default build in that same tree fails with `missing required
// modules: 'CGtk', 'GtkCHelpers'`. testapp/compile.zsh documents that and gives
// each backend its own tree for the same reason. Keep the path short -- an
// absolute --scratch-path deep under AppData came back as
// `\\?\C:\?\C:\Users\...` and every input file failed to open.
//
// `swift test` 會建置套件中的每一個 target，而非僅測試 bundle 及其 import 的部分，
// 因此只要有一個 target 無法為主機平台編譯，整個測試套件在任何測試執行之前就會中止。
// 每個主機都有這樣的 target：WinUIBackend 會引入 swift-winui，其 CWinRT 需要 Windows SDK
// 的 <wtypesbase.h>；UIKitBackend import UIKit；AppKitBackend import AppKit；而 GtkCHelpers
// include 了 <gtk/gtk.h>，未經設定的 Windows `swift test` 並沒有其路徑。這些標頭都不是我們
// 該提供的——它們分別屬於 Windows SDK、Apple 的 SDK 與 GTK——因此都不是在本 repo 新增檔案
// 所能解決的。
//
// 為其「依賴項」加上平台條件並無幫助——這已試過，下方 WinUIBackend target 處的註解記錄了
// 原因。真正有效的是根本不宣告這些 target，而這正是本開關的作用。
//
// 它採用 opt-in，與上方的 SCUI_ANDROID 相同，理由也相同：預設就改變 manifest 會連
// Windows、Linux、CI 與 iOS 建置一併改變，而那些場合都需要這些 target。僅在主機端執行
// 測試時設定它（三個平台的指令見上）。testapp/install_tool_mac.zsh 會印出 macOS 的指令並
// 說明其 -Xcc 旗標。Windows 之所以需要自己的 scratch path，理由與本開關無關：-gtk4 的建置
// 會在 SwiftPM 的增量狀態中留下 GtkBackend，同一個目錄樹中的下一次預設建置便會以
// `missing required modules: 'CGtk', 'GtkCHelpers'` 失敗；testapp/compile.zsh 記錄了此事，
// 並基於同一理由讓每個 backend 各用一棵目錄樹。路徑請保持簡短——曾以 AppData 下的深層絕對
// 路徑作為 --scratch-path，結果回傳成 `\\?\C:\?\C:\Users\...`，每個輸入檔都無法開啟。
let hostBackendsOnly = env["SCUI_HOST_BACKENDS_ONLY"] == "1"

var defaultBackendDependencies: [Target.Dependency]
if let backend = env["SCUI_DEFAULT_BACKEND"] {
    defaultBackendDependencies = [.target(name: backend)]
} else {
    // With no #if here, Windows and Linux dependencies are also compiled when building for
    // UIKit platforms.
    #if os(macOS)
        // No hostBackendsOnly guard here, or in the branch below. A dependency
        // on a target the manifest has removed is a hard error, but the removal
        // at the bottom of this file now sweeps every dependency list for
        // mentions of what it dropped. Guarding a site by hand is what this
        // used to do, and the site beside this one never got the guard.
        // 此處與下方分支都不再有 hostBackendsOnly 防護。依賴一個已被 manifest 移除的 target
        // 確實會直接報錯，但本檔結尾的移除邏輯現在會掃過每一份 dependency 清單，清除其所移除
        // 者的所有提及。逐處手動防護正是此處原本的做法，而緊鄰的另一個分支從未被加上防護。
        defaultBackendDependencies = [
            .target(name: "AppKitBackend", condition: .when(platforms: [.macOS])),
            .target(
                name: "UIKitBackend",
                condition: .when(platforms: [.iOS, .tvOS, .macCatalyst, .visionOS])
            ),
        ]
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
            linkerSettings: [
                .linkedLibrary("epoxy"),
                // dwmapi, for the dark title bar in gtk_titlebar_theme.c. Windows
                // only, and not a new dependency there either -- it ships with the
                // OS and every windowed app already loads it through the shell.
                // dwmapi，供 gtk_titlebar_theme.c 中的深色標題列使用。僅限 Windows，且在該處也不是
                // 新的相依：它隨作業系統提供，任何具視窗的 app 都已透過 shell 載入它。
                .linkedLibrary("dwmapi", .when(platforms: [.windows])),
            ]
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
                    name: "SwiftJavaStatic",
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
    // Which targets the host cannot compile, per host. This used to be the
    // macOS answer written as a constant, which is why the flag worked there
    // and nowhere else. On Linux it left AppKitBackend in the package, and
    // `import AppKit` is unguarded. On Windows it removed WinUIBackend -- the
    // one backend that host actually builds -- while leaving GtkCHelpers to
    // look for <gtk/gtk.h>, which is where a Windows `swift test` stops.
    //
    // Neither of those headers is ours to supply. <wtypesbase.h> comes with the
    // Windows SDK and <gtk/gtk.h> with GTK 4; vendoring either would mean
    // shipping someone else's SDK, and a lone header would not compile anyway.
    // The fix is to not build the target on a host that cannot.
    //
    // 本主機無法編譯的 target，依主機而定。此處原本寫死的是 macOS 的答案，這正是該旗標只在
    // macOS 有效的原因。在 Linux 上它會把 AppKitBackend 留在套件中，而其 `import AppKit`
    // 並無條件防護；在 Windows 上它移除的是 WinUIBackend——該主機唯一真正會建置的 backend
    // ——卻留下 GtkCHelpers 去尋找 <gtk/gtk.h>，而 Windows 上的 `swift test` 正是停在該處。
    //
    // 這兩個標頭都不是我們該提供的：<wtypesbase.h> 隨 Windows SDK 發布、<gtk/gtk.h> 隨 GTK 4
    // 發布，內建任一個都等同散布他人的 SDK，而且單獨一個標頭本來也無法編譯。正確的做法是
    // 不要在無法編譯它的主機上建置該 target。
    #if os(macOS)
        let unbuildableOnHost: Set<String> = ["WinUIBackend", "UIKitBackend"]
    #elseif os(Windows)
        // GTK can be installed on Windows and testapp/compile.zsh -gtk4 does
        // exactly that, so these are not unbuildable in principle -- they are
        // unbuildable for a bare `swift test`, which sets none of the pkg-config
        // and -Xcc paths that build needs. Dropping them is what this flag is
        // for: the host backend here is WinUIBackend.
        //
        // GTK 在 Windows 上是可以安裝的，testapp/compile.zsh -gtk4 正是在做這件事，因此這些
        // target 並非原理上無法建置——它們是對「未經設定的 `swift test`」而言無法建置，因為
        // 該指令不會設定建置所需的 pkg-config 與 -Xcc 路徑。移除它們正是此旗標的用途：此處的
        // 主機 backend 是 WinUIBackend。
        let unbuildableOnHost: Set<String> = [
            "AppKitBackend", "UIKitBackend",
            "GtkBackend", "Gtk", "GtkExample", "GtkCHelpers", "CGtk",
        ]
    #else
        let unbuildableOnHost: Set<String> = [
            "AppKitBackend", "UIKitBackend", "WinUIBackend",
        ]
    #endif

    package.targets.removeAll { unbuildableOnHost.contains($0.name) }
    package.products.removeAll { unbuildableOnHost.contains($0.name) }

    // Then drop every dependency naming one of them, wherever it appears.
    //
    // A dependency on a target the manifest does not declare is a hard error,
    // so removing a target means finding its every mention. That was done by
    // hand, at one site, guarded by `if !hostBackendsOnly` -- and the guard was
    // written into the macOS branch of defaultBackendDependencies and not the
    // branch beside it, so on Linux the flag failed with "Source files for
    // target WinUIBackend should be located under 'Sources/WinUIBackend'". A
    // sweep cannot miss a site the way a hand-written guard can, and it is why
    // no such guard is needed above.
    //
    // 接著移除任何指名這些 target 的 dependency，無論它出現在何處。
    //
    // 依賴一個 manifest 未宣告的 target 會直接報錯，因此移除 target 就必須找出它的每一處提及。
    // 該工作原本是手動完成的，只處理了一個位置，以 `if !hostBackendsOnly` 防護——而該防護寫在
    // defaultBackendDependencies 的 macOS 分支中，卻沒有寫進緊鄰的另一個分支，於是在 Linux 上
    // 此旗標會以「Source files for target WinUIBackend should be located under
    // 'Sources/WinUIBackend'」失敗。全面掃過一遍不會像手寫防護那樣漏掉某處，這也是上方不再
    // 需要任何此類防護的原因。
    for target in package.targets {
        target.dependencies.removeAll { dependency in
            switch dependency {
                case .targetItem(let name, _), .byNameItem(let name, _):
                    return unbuildableOnHost.contains(name)
                default:
                    return false
            }
        }
    }
}

// Swift 5 language mode, for now, on every target that takes Swift settings.
//
// The manifest declares tools-version 6.0, which does two things. It refuses an
// older toolchain outright -- the point of the upgrade -- and it makes Swift 6
// the default language mode for every target in this package. The second is a
// migration, not a flag: measured 2026-08-27 with the mode actually on, this
// package has 1 site in SwiftCrossUI, 98 errors in GtkBackend and 1274 in
// WinUIBackend, with AppKitBackend and UIKitBackend unmeasurable on a Windows
// host. Landing that as one change would mean a tree nobody could build while
// it was in progress.
//
// So the mode is pinned back to v5 here and lifted per target as each one is
// migrated -- delete a target's entry from `stillOnSwift5` and it goes to v6
// alone, compiling and testing on its own. The list is the remaining work, and
// an empty list is the end of it.
//
// Applied as a sweep rather than written into each target for the same reason
// the dependency sweep above exists: several targets pass no swiftSettings at
// all, and those are exactly the ones a by-hand pass forgets. A target that
// takes no Swift settings -- the C and systemLibrary ones -- is left alone.
//
// 暫時將所有可接受 Swift 設定的 target 固定為 Swift 5 語言模式。
//
// 本 manifest 宣告 tools-version 6.0，這做了兩件事：其一是直接拒絕較舊的工具鏈——正是本次升級的
// 目的；其二是使 Swift 6 成為此套件中每個 target 的預設語言模式。後者是一場遷移，而非一個旗標：
// 於 2026-08-27 在該模式確實開啟的情況下實測，本套件在 SwiftCrossUI 有 1 處、GtkBackend 有 98 個
// 錯誤、WinUIBackend 有 1274 個，而 AppKitBackend 與 UIKitBackend 在 Windows 主機上無從量測。
// 若將其作為單一變更落地，過程中將出現一棵無人能建置的樹。
//
// 因此此處把模式釘回 v5，並在每個 target 完成遷移後逐一解除——從 `stillOnSwift5` 中刪掉某個
// target，它便單獨切換為 v6，可獨立建置與測試。該清單即是剩餘的工作，清單清空之時即為完成之日。
//
// 採「掃描套用」而非逐 target 寫入，理由與上方的 dependency 掃描相同：有數個 target 根本不傳
// swiftSettings，而那些正是逐一手動處理時會漏掉的。不接受 Swift 設定的 target（C 與
// systemLibrary 類）則不予變更。
let stillOnSwift5: Set<String> = Set(package.targets.map(\.name))

for target in package.targets where stillOnSwift5.contains(target.name) {
    switch target.type {
        case .system, .binary:
            continue
        default:
            target.swiftSettings = (target.swiftSettings ?? []) + [.swiftLanguageMode(.v5)]
    }
}
