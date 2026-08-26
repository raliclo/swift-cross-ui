// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iOSActionFileRunner",
    platforms: [.iOS(.v13)],
    targets: [
        .testTarget(
            name: "iOSActionFileRunnerTests",
            path: "Tests"
        )
    ]
)
