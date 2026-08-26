<p align="center">
    <img width="100%" src="banner.png">
</p>

<p align="center">
    <a href="https://github.com/moreSwift/swift-cross-ui/actions/workflows/build-test-and-docs.yml"><img alt="Workflow status" src="https://github.com/moreSwift/swift-cross-ui/actions/workflows/build-test-and-docs.yml/badge.svg?event=push"></a>
    <img alt="License" src="https://img.shields.io/github/license/moreSwift/swift-cross-ui">
    <a href="https://moreswift.dev/discord"><img src="https://img.shields.io/discord/1123965445687484466?color=6A7EC2&label=discord&logo=discord&logoColor=ffffff"></a> 
</p>

A SwiftUI-like framework for creating cross-platform apps in Swift (5.10+).

To get started with SwiftCrossUI, check out [the quick start guide](https://docs.swiftcrossui.dev/tutorials/swiftcrossui/quick-start).

> [!NOTE]
> SwiftCrossUI does not attempt to replicate SwiftUI's API perfectly since that would be a constantly-moving target and SwiftUI has many entrenched Apple-centric concepts. That said, SwiftCrossUI's built-in views and scenes share much of their API surface with their SwiftUI cousins, and over time SwiftCrossUI will likely adopt many of SwiftUI's commonly-used APIs.

## Overview

- [Community](#community)
- [Supporting SwiftCrossUI](#supporting-swiftcrossui)
- [Documentation](#documentation)
- [Basic example](#basic-example)
- [Backends](#backends)

## Community

Discussion about SwiftCrossUI happens in the [moreSwift Discord server](https://moreswift.dev/discord). [Join](https://moreswift.dev/discord) to discuss the library, get involved, or just be kept up-to-date on progress!

## Supporting SwiftCrossUI

If you find SwiftCrossUI useful, please consider supporting its development by [becoming a sponsor](https://opencollective.com/moreswift). moreSwift's core contributors spend much of their spare time working on open-source projects, and each sponsorship helps us to focus more time on making high quality tools and libraries for the community.

## Documentation

Here's the [documentation site](https://docs.swiftcrossui.dev/documentation/swiftcrossui). SwiftCrossUI is still a work-in-progress; proper documentation and tutorials are on the horizon. Documentation contributions are very welcome!

## Basic example

Here's a simple example app demonstrating how easy it is to get started with SwiftCrossUI. For a more detailed walkthrough, check out our [quick start guide](https://docs.swiftcrossui.dev/tutorials/swiftcrossui/quick-start)

```swift
import PackageDescription

let package = Package(
    name: "YourApp",
    dependencies: [
        .package(
            url: "https://github.com/moreSwift/swift-cross-ui",
            .upToNextMinor(from: "0.2.0")
        ),
    ],
    targets: [
        .executableTarget(
            name: "YourApp",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
            ]
        ),
    ]
)
```
Figure 1: *Package.swift*

```swift
import SwiftCrossUI
import DefaultBackend

@main
struct YourApp: App {
    @State var count = 0

    var body: some Scene {
        WindowGroup("YourApp") {
            HStack {
                Button("-") { count -= 1 }
                Text("Count: \(count)")
                Button("+") { count += 1 }
            }.padding()
        }
    }
}
```
Figure 2: *Sources/YourApp/YourApp.swift*

## More examples

The SwiftCrossUI repository contains the above example and many more. The documentation hosts [a detailed list of all examples](https://docs.swiftcrossui.dev/documentation/swiftcrossui/examples).

Running the examples requires [Swift Bundler](https://github.com/moreSwift/swift-bundler), which provides consistent behavior across platforms and enables running on iOS/tvOS devices and simulators.

To install Swift Bundler, follow [its official installation instructions](https://github.com/moreSwift/swift-bundler?tab=readme-ov-file#installation-).

```sh
git clone https://github.com/moreSwift/swift-cross-ui
cd swift-cross-ui/Examples

# Run on host machine
swift-bundler run CounterExample
# Run on a connected device with "iPhone" in its name (macOS only)
swift-bundler run CounterExample --device iPhone
# Run on a simulator with "iPhone 16" in its name (macOS only)
swift-bundler run CounterExample --simulator "iPhone 16"
```

These examples may also be run using SwiftPM. However, resources may not be loaded as expected, and features such as deep linking may not work. You also won't be able to run the examples on iOS or tvOS using this method.

```sh
# Non-recommended method
swift run CounterExample
```

## Running the tests

`swift test` on its own fails on every platform, and not because of the tests.
SwiftPM builds *every* target in the package before running any of them, and
each host has targets it cannot build: `WinUIBackend` pulls in a package whose C
target needs the Windows SDK's `<wtypesbase.h>`, `AppKitBackend` and
`UIKitBackend` import Apple frameworks, and `GtkCHelpers` includes
`<gtk/gtk.h>`. None of those headers ship with this repository — they belong to
the Windows SDK, to Apple's SDKs and to GTK — so the answer is to leave the
target out on a host that cannot build it.

`SCUI_HOST_BACKENDS_ONLY=1` does that. Set it only for a test run: it changes
which targets the manifest declares, which is not what you want for a build.

```sh
# macOS
SCUI_HOST_BACKENDS_ONLY=1 swift test -Xcc -I$(brew --prefix)/include

# Linux
SCUI_HOST_BACKENDS_ONLY=1 swift test

# Windows
SCUI_HOST_BACKENDS_ONLY=1 swift test --scratch-path .build-hosttest
```

> [!NOTE]
> The separate build directory on Windows is unrelated to the flag. SwiftPM's
> incremental state records which modules each target depended on, so a GTK
> build of a Windows app leaves `GtkBackend` behind and the next default build
> in that same tree fails with `missing required modules: 'CGtk',
> 'GtkCHelpers'` — even though its manifest never mentions them. `.build-hosttest`
> is gitignored for this reason, as `testapp/.compile-work-*` is.

> [!TIP]
> Keep a `--scratch-path` short and relative. An absolute one nested deeply
> under `AppData` came back from SwiftPM as `\\?\C:\?\C:\Users\...`, and every
> input file then failed to open with `invalid argument`.

## Building the test apps

`testapp/P*.swift` are standalone apps used to exercise the backends by hand.
`testapp/compile.zsh` generates a package around the ones you name and builds
them:

```sh
zsh testapp/compile.zsh P19              # the platform's default backend
zsh testapp/compile.zsh -gtk4 P19        # force GtkBackend, Windows included
zsh testapp/run.zsh P19                  # needed for a -gtk4 build on Windows
```

`run.zsh` exists because a `-gtk4` build needs `C:/gtk4/bin` on `PATH`; without
it the executable exits immediately with `gtk-4-1.dll => not found`.

> [!NOTE]
> A rebuild that changes nothing now takes about **6 s**. It used to take
> **118 s** for a `-gtk4` app, and none of that was compilation.
>
> The script regenerates the package manifest on every run. The content is
> almost always identical — same apps, same flags — but writing it gave the file
> a new mtime, and SwiftPM decides what to rebuild from mtimes. So every run
> re-planned the build and re-emitted every module, of which `Gtk` alone was
> 16 s. It now writes the manifest, and copies each app's source, only when the
> content differs.
>
> This was also the whole reason `-gtk4` *looked* far slower than the default
> path on Windows. It is not: measured from an empty build tree, `-gtk4` takes
> 130 s and the WinUI path 123 s, five percent apart. `Gtk` is a large module
> built from GIR bindings and the WinUI path never builds it, so a real
> difference was easy to assume — but the clean builds say there is barely one,
> and the 118 s was the churn.

> [!NOTE]
> Build times measured on one machine, 2026-08-27, from an empty
> `COMPILE_WORK_DIR` so each is a genuine full build. Re-run rather than quote:
>
> | | full | nothing changed |
> |---|---|---|
> | GtkBackend, WSL | 434 s | 2 s |
> | GtkBackend, Windows | 130 s | 19 s |
> | WinUIBackend, Windows | 123 s | 18 s |
>
> The two columns disagree about which platform is faster, and both are right.
> A full build is faster on Windows here; a rebuild that changes nothing is
> roughly ten times faster on Linux. The second column is the one you feel all
> day, and it follows from process creation costing about twenty times more on
> Windows — SwiftPM still spawns a round of tools to establish that there is
> nothing to do. `testapp/platform-costs.md` has that measurement.

> [!TIP]
> Each backend gets its own build tree (`testapp/.compile-work` and
> `.compile-work-gtk4`). Sharing one is not merely slower, it is wrong: SwiftPM's
> incremental state records which modules a target depended on, so a `-gtk4`
> build leaves references behind and the next default build fails with
> `missing required modules: 'CGtk', 'GtkCHelpers'`. Set `COMPILE_WORK_DIR` to
> build somewhere else again — useful when something else is already using those
> trees.

## Backends

SwiftCrossUI has a variety of backends tailored to different operating systems. The beauty of SwiftCrossUI is that you can write your app once and have it look native everywhere. For this reason I recommend using [DefaultBackend](https://docs.swiftcrossui.dev/documentation/swiftcrossui/defaultbackend) unless you've got particular constraints.

> [!TIP]
> Click through each backend name for detailed system requirements and installation instructions.

- [DefaultBackend](https://docs.swiftcrossui.dev/documentation/swiftcrossui/defaultbackend): Adapts to your target operating system. On macOS it uses [AppKitBackend](https://docs.swiftcrossui.dev/documentation/swiftcrossui/appkitbackend), on Windows it uses [WinUIBackend](https://docs.swiftcrossui.dev/documentation/swiftcrossui/winuibackend), on Linux it uses [GtkBackend](https://docs.swiftcrossui.dev/documentation/swiftcrossui/gtkbackend), and on iOS and tvOS it uses [UIKitBackend](https://docs.swiftcrossui.dev/documentation/swiftcrossui/uikitbackend).
- [AppKitBackend](https://docs.swiftcrossui.dev/documentation/swiftcrossui/appkitbackend): The native macOS backend. Supports all SwiftCrossUI features.
- [UIKitBackend](https://docs.swiftcrossui.dev/documentation/swiftcrossui/uikitbackend): The native iOS & tvOS backend. Supports most SwiftCrossUI features.
- [WinUIBackend](https://docs.swiftcrossui.dev/documentation/swiftcrossui/winuibackend): The native Windows backend. Supports most SwiftCrossUI features.
- [GtkBackend](https://docs.swiftcrossui.dev/documentation/swiftcrossui/gtkbackend): Works on Linux, macOS, and Windows. Requires gtk 4 to be installed. Supports most SwiftCrossUI features.

> [!TIP]
> If you're using DefaultBackend, you can override the underlying backend during compilation by setting the `SCUI_DEFAULT_BACKEND` environment variable to the name of the desired backend. This is useful when you e.g. want to test the Gtk version of your app while using a Mac. Note that this only works for built-in backends and still requires the chosen backend to be compatible with your machine.
