# CI TODO: Android build

Tracks what the Android opt-in change (`0c90f3fc`) requires from CI, and what
still needs verifying there. None of the items below could be checked locally,
because the CI environment differs from this machine in ways that matter.

## Environment gap

The Android job runs on `macos-15` with Xcode 16.4 (Swift 6.1.2), while local
verification was done on macOS 27 with Xcode 27 (Swift 6.4). Failures seen
locally do not automatically apply to CI, and vice versa.

| | CI | Local |
| --- | --- | --- |
| Runner / host | macos-15 | macOS 27 |
| Xcode | 16.4 (Swift 6.1.2) | 27 (Swift 6.4) |
| Cross-compile toolchain | swift-6.3-DEVELOPMENT-SNAPSHOT-2026-05-01-a | ...-2026-06-07-a |
| Swift Bundler | `Vendor/swift-bundler` | same submodule |

## Done

- [x] `SCUI_ANDROID: "1"` added to the android job's `env` block. Without it the
      package no longer contains AndroidBackend or AndroidBackendShim, so the
      examples would fail to link against the backend.

- [x] The job checks out submodules recursively and builds Swift Bundler from
      `Vendor/` instead of cloning it, so CI exercises the commits this
      repository pins. `SWIFT_BUNDLER_REVISION` is gone; the cache key is now
      derived from the two Vendor commits.

- [x] Package.resolved no longer drifts. The Android dependencies are declared
      unconditionally in Package.swift, so resolving with or without
      SCUI_ANDROID leaves the same 24 pins. Only the targets stay gated, which
      is what keeps non-Android builds off AndroidBackendShim's
      `<android/log.h>`.

## Needs verifying on CI

- [ ] **Android platform 36 must be available.** Every app in
      `Examples/Bundler.toml` now sets `compile_sdk = 36`, because
      `AndroidBackendHelpers.kt` calls `TimeZone.getIanaID` (API 36). The
      `macos-15` runner's preinstalled Android SDK may not include
      `platforms;android-36`. If the gradle step fails with
      `Unresolved reference 'getIanaID'`, add an install step before
      `Build examples`:

      ```sh
      $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "platforms;android-36"
      ```

- [ ] **Swift Bundler build.** Its `ZIPFoundationModern` dependency fails to
      compile under Swift 6.3+ (`data.append(contentsOf: .init(repeating:count:))`
      can no longer have its type inferred; still broken in upstream 0.0.9).
      `Vendor/ZIPFoundationModern` tracks a fork carrying the one-line fix, and
      the job now injects it with `swift package edit`. CI builds the bundler
      with Swift 6.1.2, where even the unpatched version compiles, so the fork
      should be harmless there — but no run has confirmed it.

- [ ] **The remaining examples.** Only CounterExample, WebViewExample and
      ControlsExample were bundled locally. CI builds 11. The other 8 received
      the same mechanical `Bundler.toml` edit and are unverified.

## Examples/Package.resolved still drifts

The unconditional Android dependencies fixed the root `Package.resolved`, but
not `Examples/`, which is a separate package with its own lockfile. Resolving
there without `SCUI_ANDROID=1` still prunes the same Android pins:

```
androidkit, swift-android-native, swift-java, swift-java-jni-core,
swift-subprocess, ...
```

The root package keeps its 24 pins because the dependencies are declared there
directly. Examples reaches them transitively through `.package(path: "..")`, and
without the variable no target in the graph uses them, so they are dropped.

- [ ] Decide whether Examples should declare the Android dependencies itself, or
      whether its lockfile is simply expected to differ by build mode.
- [ ] Until then: `git checkout -- Examples/Package.resolved` after building or
      resolving there without `SCUI_ANDROID=1`. Observed while running
      `xcodebuild -list` in that directory.

## Cleanups

- [ ] The comment above `SWIFT_RELEASE` points at the API level 24 SDK, but the
      Swift Android SDK exposes **28** (`aarch64-unknown-linux-android28`). The
      triple is chosen by Swift Bundler rather than that comment, so this is
      documentation drift rather than a build failure.

- [ ] Consider moving the android job to a newer Xcode. It is pinned to 16.4
      across every macOS job, which is now several releases behind and is the
      reason the CI and local toolchains diverge.

## Reference

Full local setup and verification steps:
`Scripts/build-tool-install-android-on-Mac.sh`
