# testapp

Standalone apps that reproduce specific upstream issues, plus the documents
that say which app tests what and what has been verified.

**This directory does not exist upstream.** Nothing here can be part of a pull
request, which is why every commit touching it is recorded as `local` in
`issue_commits.csv` and why commits that mix `Sources/` and `testapp/` changes
need the `testapp/` half dropped before submitting.

## Start here

| Question | File |
| --- | --- |
| Where do I run this issue, and does the answer count? | `UI-test-plan platform-en.md` |
| What are the steps for app PN? | `UI-test-plan overall-en.md` |
| What is the plan for the GtkBackend work? | `UI-test-plan linux-en.md` |
| What is the plan for the AppKit/Android/iOS work? | `UI-test-plan bug-en.md` |
| What is the state of every upstream issue? | `issues.csv` |
| Which commit fixes what, and can it be submitted? | `issue_commits.csv` |

`UI-test-plan platform-en.md` is the entry point: it maps all 40 covered issues onto
the six platforms and marks, per cell, whether a run there settles the issue,
is only a comparison, or tells you nothing.

## The apps

P0-P17, one Swift file each, built as standalone executables. P0-P6 came out of
the WinUIBackend work, P7-P10 and P15 target GtkBackend, P11 AppKitBackend, P12
AndroidBackend, P14 UIKitBackend, and P13, P16 and P17 cover core layout and
split-view behaviour. `UI-test-plan platform-en.md` has the full mapping.

```sh
zsh testapp/compile.zsh P7 P15 P17     # build a subset
zsh testapp/compile.zsh                # build everything
```

Output lands in `testapp/output/` -- `PN` on Linux and macOS, `PN.exe` on
Windows. Neither the output directory nor the `.compile-work` build tree is
tracked.

## Environment setup

| Script | For |
| --- | --- |
| `install_tool_wsl.sh` | WSL: GTK 4, the Swift tarball, and the libxml2/ICU shims Ubuntu 26.04 needs |
| `install_tools_ios.zsh` | macOS: the iOS Simulator toolchain, called automatically by `compile.zsh -ios` |
| `install_tool_mac.zsh` | macOS: GTK 4 via Homebrew, and the two things `swift test` needs to run on a Mac at all. `--test` runs the suite |
| `install_tools_android.zsh` | macOS: the Android SDK, NDK and emulator the Android runner needs |

## Running a test

`test.zsh` is the entry point for every platform:

```sh
zsh testapp/test.zsh P8                 # this host's platform
zsh testapp/test.zsh P8 --both          # WSLg, then Windows
zsh testapp/test.zsh P28 --macos --actionfile
zsh testapp/test.zsh P14 --ios
zsh testapp/test.zsh P12 --android
```

### Platforms

The platform flag is optional. Each test declares the platform it was written
for and most were written on Windows, so on a Mac the declared platform is
usually one this host cannot drive; the run moves to one it can and says so.
Naming a platform this host cannot drive is refused rather than redirected.

| Host | Can drive |
| --- | --- |
| Windows | `--windows` (`-win`), `--wsl`, `--both` |
| macOS | `--macos`, `--ios`, `--android` |

`--wsl` and `--both` reach into WSL with `wsl.exe`, so they need a Windows host
rather than a Linux one. `--ios` and `--android` need macOS.

### Flags

The same flags mean the same thing on every platform, iOS and Android included.

| Flag | Effect |
| --- | --- |
| `-n`, `--no-build` | Reuse what is already built |
| `--showtime <s>`, `--no-showtime` | How long to leave the app up after it renders |
| `--actionfile [path]` | Replay a CSV of synthesised input once the window is up. Without a path, `testapp/actions/<platform>/<Pn>-*.csv` is used — one folder per platform, because a file verified elsewhere is not evidence here |
| `--device <name>` | iOS and Android only; refused on the others |

### Devices

Neither iOS nor Android needs a device named or an environment variable set.

`--ios` uses a Simulator called `swift-cross-ui`, which `install_tools_ios.zsh`
creates as an iPhone 16. `--android` boots the first AVD `emulator -list-avds`
reports, and says so if none exists rather than failing further in.

`--device` overrides either: a Simulator name or UDID for iOS, an AVD name or an
adb serial for Android. `IOS_SIM_DEVICE` and `ANDROID_AVD_NAME` do the same
thing from the environment.

| Script | For |
| --- | --- |
| `test.zsh` | The command. Finds `test_support/test_Pn.zsh`, which sets the app's details and hands over to `test_support/test_common.zsh` |
| `test_common.zsh` | Parses the flags, resolves the platform, and runs WSLg, Windows or macOS directly; delegates iOS and Android to the two scripts below, rebuilding the flags in their spelling |
| `test_ios.zsh` | macOS: installs a Pn through the fixed `debugTarget` iOS bundle and launches Simulator; optionally replays an action file through XCUITest. Reached as `test.zsh <Pn> --ios` |
| `test_android.zsh` | macOS: builds and bundles a Pn as an APK, installs it on the emulator and launches it. Reached as `test.zsh <Pn> --android` |

## Other scripts

| Script | For |
| --- | --- |
| `screenshot.zsh` | Captures the composited desktop, which is the only way to see D3D/DirectComposition content |
| `gpu-matrix.zsh`, `P6-test.zsh`, `test_P6.zsh` | P6's throughput matrix and its unattended runs |
| `rebase.zsh` | Rebases, then checks that the hashes in `issue_commits.csv` still exist on the branch |

`rebase.zsh` exists because a rebase silently orphans recorded hashes: they
keep resolving from the reflog, so nothing looks wrong until the next clone.

## Records

`P6_findings/` holds the measured throughput numbers behind the NV12 work, and
`comments/` holds write-ups drafted for upstream issues.

Two documents are deliberately untracked and local to a checkout:
`UI-test-plan overall-zhTW.md`, the Traditional Chinese half of the test plan, and
`UI-test-results.md`. Edits to the test steps belong in both language files even
though only `UI-test-plan overall-en.md` is committed.
