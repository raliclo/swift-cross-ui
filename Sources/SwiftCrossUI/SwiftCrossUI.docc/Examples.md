# Examples

An overview of the examples included with SwiftCrossUI.

## Overview

A few examples are included with SwiftCrossUI to demonstrate some of its basic features;

- `MusicPlayerExample`, an offline music player that lets users create and persist their own playlists of audio files.
- `CounterExample`, a simple app with buttons to increase and decrease a count.
- `RandomNumberGeneratorExample`, a simple app to generate random numbers between a minimum and maximum.
- `WindowingExample`, a simple app showcasing how ``WindowGroup`` is used to make multi-window apps and
  control the properties of each window. It also demonstrates the use of modals
  such as alerts, sheets, and file pickers.
- `GreetingGeneratorExample`, a simple app demonstrating dynamic state and the ``ForEach`` view.
- `NavigationExample`, an app showcasing ``NavigationStack`` and related concepts.
- `SplitExample`, an app showcasing ``NavigationSplitView``-based hierarchical navigation.
- `StressTestExample`, an app used to test view update performance.
- `SpreadsheetExample`, an app showcasing tables.
- `ControlsExample`, an app showcasing the various types of controls available.
- `NotesExample`, an app showcasing multi-line text editing and a more realistic usage of SwiftCrossUI.
- `PathsExample`, an app showcasing the use of ``Path`` to draw various shapes.
- `WebViewExample`, an app showcasing the use of ``WebView`` to display websites. ~~Only works on Apple platforms so far.~~
- `AdvancedCustomizationExample`, an app showcasing SwiftCrossUI's more advanced APIs for customizing the underlying native views of your app.
- `ColorsExample`, `FontsExample`, `ForEachExample`, `GradientsExample`, `HoverExample` and
  `TapGesturesExample`, six further examples added between 2026-03 and 2026-08 that this list did
  not mention.

> Note: Corrected 2026-09-09, on two counts.
>
> The `WebViewExample` caveat is no longer true. All five shipped backends conform to
> ``BackendFeatures/WebViews``, and none of the four non-AppKit implementations is a stub:
> `Sources/GtkBackend/GtkBackend+WebView.swift` is 131 lines and landed 2026-09-04,
> `Sources/WinUIBackend/WinUIBackend+WebView.swift` is 108 lines,
> `Sources/UIKitBackend/UIKitBackend+WebView.swift` and
> `Sources/AndroidBackend/AndroidBackend+WebViews.swift` cover the mobile targets. The claim was
> inherited from <doc:AppBackend-refactor>, which said web views were "AppKitBackend and
> UIKitBackend only" -- a good illustration of why an unverified claim is expensive: it does not sit
> still in the document that first made it, it gets copied.
>
> The list was also short by six. There are 20 example targets, not 14; count them with
> `ls Examples/Sources | wc -l`. Every entry that *was* listed still exists, so nothing here had to
> be removed -- the failure was purely one of omission, which is the kind that produces no error
> anywhere and no reason for anyone to look.

## Running examples

Running the examples requires [Swift Bundler](https://github.com/moreSwift/swift-bundler), which provides consistent behavior across platforms and enables running SwiftPM-based apps on iOS/tvOS devices and simulators.

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

If you want to try out an example with a backend other than the default, you can do that too;

```sh
SCUI_DEFAULT_BACKEND=GtkBackend swift-bundler run ExampleToRun
```

These examples may also be run using SwiftPM. However, resources may not be loaded as expected, and features such as deep linking may not work. You also won't be able to run the examples on iOS or tvOS using this method.

```sh
# Non-recommended method
swift run CounterExample
```
