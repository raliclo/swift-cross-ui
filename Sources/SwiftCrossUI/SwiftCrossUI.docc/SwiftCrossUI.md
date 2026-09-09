# ``SwiftCrossUI``

Create cross-platform apps for macOS, Linux, Windows, iOS, tvOS, visionOS and Android.

## Overview

SwiftCrossUI takes inspiration from SwiftUI, allowing you to use the basic concepts of SwiftUI to create cross-platform apps. SwiftCrossUI provides your users with a native experience on every platform via a suite of backends built on top of various UI frameworks (see [Backends](#backends)).

> Note: Corrected 2026-09-09. The abstract used to read ~~"Create cross-platform **desktop** apps
> for macOS, Linux, Windows, iOS and tvOS"~~. Two things were wrong with it. It omitted Android,
> although `Sources/AndroidBackend/` ships and <doc:Built-in-backends> lists six backends; and it
> omitted visionOS, although `Package.swift:220` declares `.visionOS(.v1)` and
> <doc:UIKitBackend> names visionOS as one of the platforms it is the default backend for. The word
> "desktop" was also carrying more weight than it should, given that four of the seven platforms in
> the corrected list are not desktops. Regenerate the platform list from
> `grep -n "platforms: \[" Package.swift` together with `ls Sources | grep Backend`.

## Topics

### Getting Started

- <doc:Table-of-Contents>
- <doc:Examples>
- <doc:Hot-reloading>

### Backends

- <doc:Built-in-backends>
- <doc:Custom-backends>

### App structure

<!-- TODO: Create article on metadata -->

- ``App``
- ``AppMetadata``
- <doc:Scenes>

### Views

- <doc:View-fundamentals>
- <doc:Controls>
- <doc:Layout>
- <doc:Styling>
- <doc:Navigation>
- <doc:Shapes>
- <doc:Gradients>
- <doc:Tables>

### State

- <doc:State-basics>
- <doc:The-environment>
- <doc:Preferences>

### User input

- <doc:Gestures>

### Other

- <doc:Logging>
- <doc:Implementation-details>
- <doc:Deprecated>
