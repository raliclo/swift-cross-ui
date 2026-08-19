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

var defaultBackendDependencies: [Target.Dependency]
if let backend = env["SCUI_DEFAULT_BACKEND"] {
    defaultBackendDependencies = [.target(name: backend)]
} else {
    // With no #if here, Windows and Linux dependencies are also compiled when building for
    // UIKit platforms.
    #if os(macOS)
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
        .executable(name: "GtkExample", targets: ["GtkExample"]),
        // .library(name: "CursesBackend", type: libraryType, targets: ["CursesBackend"]),
        // .library(name: "QtBackend", type: libraryType, targets: ["QtBackend"]),
        // .library(name: "LVGLBackend", type: libraryType, targets: ["LVGLBackend"]),
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
        .target(name: "AppKitBackend", dependencies: ["SwiftCrossUI"]),
        .target(
            name: "GtkBackend",
            dependencies: ["SwiftCrossUI", "Gtk", "CGtk"]
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
            dependencies: ["CGtk"]
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
                .product(name: "WinUI", package: "swift-winui"),
                .product(name: "UWP", package: "swift-winui"),
                .product(name: "CWinRT", package: "swift-winui"),
                .product(name: "WinAppSDK", package: "swift-winui"),
                .product(name: "WindowsFoundation", package: "swift-winui"),
                .product(name: "Mutex", package: "swift-mutex"),
            ],
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

        // .target(
        //     name: "CursesBackend",
        //     dependencies: ["SwiftCrossUI", "TermKit"]
        // ),
        // .target(
        //     name: "QtBackend",
        //     dependencies: ["SwiftCrossUI", .product(name: "Qlift", package: "qlift")]
        // ),
        // .target(
        //     name: "LVGLBackend",
        //     dependencies: [
        //         "SwiftCrossUI",
        //         .product(name: "LVGL", package: "LVGLSwift"),
        //         .product(name: "CLVGL", package: "LVGLSwift"),
        //     ]
        // ),
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

