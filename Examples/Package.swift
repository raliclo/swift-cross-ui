// swift-tools-version: 5.10

import Foundation
import PackageDescription

var exampleDependencies: [Target.Dependency] = [
    .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
    .product(name: "DefaultBackend", package: "swift-cross-ui"),
]
var hotReloadingDependencies: [Package.Dependency] = []

// The Swift Bundler runtime requires Swift >=6.0
#if compiler(>=6.0)
    hotReloadingDependencies = [
        .package(
            url: "https://github.com/moreSwift/swift-bundler",
            revision: "496c0638dc2c6750c7873832a08c36c74631aed4"
        )
    ]
    exampleDependencies.append(
        .product(
            name: "SwiftBundlerRuntime",
            package: "swift-bundler",
            condition: .when(platforms: [.macOS, .linux])
        )
    )
#endif

let package = Package(
    name: "Examples",
    // Apple platforms at 27 and up (2026-11-20). Strings, not .v27, which needs tools 6.4.
    // Apple 平台最低為 27(2026-11-20)。用字串而非 .v27,後者需要 tools 6.4。
    platforms: [.macOS("27.0"), .iOS("27.0"), .tvOS("27.0"), .macCatalyst("27.0"), .visionOS("27.0")],
    dependencies: [
        .package(name: "swift-cross-ui", path: ".."),
        .package(
            url: "https://github.com/stackotter/swift-miniaudio",
            .upToNextMinor(from: "0.1.2")
        ),
    ] + hotReloadingDependencies,
    targets: [
        .executableTarget(
            name: "ControlsExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "CounterExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "RandomNumberGeneratorExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "WindowingExample",
            dependencies: exampleDependencies,
            resources: [.copy("Banner.png")]
        ),
        .executableTarget(
            name: "GreetingGeneratorExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "NavigationExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "SplitExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "SpreadsheetExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "StressTestExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "NotesExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "PathsExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "WebViewExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "HoverExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "ForEachExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "AdvancedCustomizationExample",
            dependencies: exampleDependencies,
            resources: [.copy("Banner.png")]
        ),
        .executableTarget(
            name: "ColorsExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "GradientsExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "MusicPlayerExample",
            dependencies: [
                .product(name: "MiniAudio", package: "swift-miniaudio")
            ] + exampleDependencies
        ),
        .executableTarget(
            name: "FontsExample",
            dependencies: exampleDependencies
        ),
        .executableTarget(
            name: "TapGesturesExample",
            dependencies: exampleDependencies
        ),
    ]
)
