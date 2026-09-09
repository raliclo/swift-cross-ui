# AppKitBackend

SwiftCrossUI's native macOS backend built on top of AppKit.

@Metadata {
    @TitleHeading("Backend")
    @Available(macOS, introduced: "11")
}

## Overview

`AppKitBackend` is the default backend on macOS, supports all current SwiftCrossUI features, and
targets macOS 11+. It doesn't have any system dependencies other than a few system frameworks
included on all Macs.

> Note: Corrected 2026-09-09. The `@Available` directive above read ~~`introduced: "10.15"`~~ while
> the prose one line below it said macOS 11+. `Package.swift:220` declares
> `platforms: [.macOS(.v11), ...]`, so 11 is the true minimum and the badge was the wrong half. The
> correction is made in the directive itself rather than struck through in place, because DocC
> parses `@Available` as a directive and tilde-wrapping it would leave the page rendering literal
> markup instead of a badge.
>
> This one is worth noting for a different reason than the rest of this audit: it was not a claim
> that went stale as the code moved, it was a self-contradiction present in a single short file.
> Two numbers eleven lines apart, disagreeing, for as long as the file has existed. Directives are
> easy to skip when re-reading a page, because they do not read like prose.
>
> The claim that `AppKitBackend` "supports all current SwiftCrossUI features" is separately worth
> keeping an eye on. As of this re-check it holds, and structurally so: it is the only backend that
> declares ``FullAppBackend`` on its class (`Sources/AppKitBackend/AppKitBackend.swift:22`), so the
> compiler enforces the claim for AppKit specifically. That is exactly why the equivalent sentence
> cannot be trusted on any other backend page without measuring.

## Usage

@TabNavigator {
    @Tab("Package.swift") {
        ```swift
        // ...
        let package = Package(
            // ...
            targets: [
                // ...
                .executableTarget(
                    name: "YourApp",
                    dependencies: [
                        .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                        .product(name: "AppKitBackend", package: "swift-cross-ui"),
                    ]
                ),
                // ...
            ],
            // ...
        )
        ```
    }
    @Tab("YourApp.swift") {
        ```swift
        import SwiftCrossUI
        import AppKitBackend
        
        @main
        struct YourApp: App {
            // You can explicitly initialize your app's chosen backend if you desire.
            // This happens automatically when you import any of the built-in backends.
            //
            // var backend = AppKitBackend()
            
            var body: some Scene {
                WindowGroup {
                    Text("Hello, World!")
                        .padding()
                }
            }
        }
        ```
    }
}
