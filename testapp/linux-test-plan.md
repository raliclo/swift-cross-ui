# Linux (GtkBackend) testing plan, via WSL

Goal: reproduce the open GtkBackend/Gtk3Backend issues on this machine, fix what
we can, and submit the fixes upstream. Same working style as the WinUI work:
reproduce first, measure rather than infer, and keep the evidence.

## Environment as it stands

Checked, not assumed:

| | |
|---|---|
| WSL | Ubuntu 26.04 LTS, WSL2, running |
| WSLg | available -- `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0`, so GTK windows display natively |
| Swift | **6.3.3**, installed from the official tarball into `/usr/local/swift` |
| GTK 4 | **4.22.4** (`libgtk-4-dev`, installed) |
| GTK 3 | not installed, and deliberately so |

WSLg presents a Wayland compositor. Anything about window sizing, minimum
sizes or resizing behaves differently there than on a real desktop session, so
those issues need a caveat (see Tier 2).

## Phase 0 -- toolchain

Done. `testapp/install_tool_wsl.sh` does all of it and is the record of what was
needed; run it as root, since `sudo` in this distribution asks for a password:

```sh
wsl -d Ubuntu -u root -- bash testapp/install_tool_wsl.sh
```

What it resolved, none of it guessed:

1. swift.org publishes **no** Ubuntu 26.04 build -- the 26.04 tarball URL 404s
   while the 24.04 one returns 200 -- so the 24.04 build is installed, from the
   official tarball into `/usr/local/swift`. Not Swiftly.
2. That build then fails to start on 26.04, twice over: 26.04 ships
   `libxml2.so.16` where Swift wants `.so.2`, and ICU 78 where it wants ICU 74.
   Both are extracted from the 24.04 `.deb` packages into
   `/usr/local/lib/swift-compat`.
3. GTK 4 is installed: `libgtk-4-dev` 4.22.4, with pkg-config 2.5.1.
4. Verify: `pkg-config --modversion gtk4` and `swift --version`.

**Scope: GtkBackend only.** Gtk3Backend is out of scope, so GTK 3 is not
installed and issues that only affect it are not being pursued. That drops #286
and #166 outright, and means #426 is only tested against GTK 4.

GTK 4.22.4 is recent, which decides #702 (about *older* GTK 4) before it starts:
it cannot be reproduced here.

## Phase 1 -- prove the toolchain end to end

Build and run one of the repo's own examples under WSLg before touching any
issue. If a window does not appear, that is an environment problem, not a bug in
the code being tested, and every later result would be suspect.

```sh
./Scripts/test.sh                    # unit tests
swift build --target GtkBackend      # not --product
```

`--target GtkBackend` is not a preference. A plain `swift build`, or
`--product SwiftCrossUI`, makes SwiftPM build the default target set, which
includes the `WinUIInterop` C target, and that fails on Linux with
`'Windows.h' file not found`. Naming the target directly is the way past it.

Measured on this machine: 61.7 s from clean for `--target GtkBackend`, and
`testapp/compile.sh` builds a repro app in 5-15 s once that is warm.

## Phase 2 -- free coverage from the existing test apps

Every app in `testapp` uses `DefaultBackend`, which selects GtkBackend on Linux,
and `testapp/compile.sh` already handles non-`.exe` output. P0-P3 and P5 should
build and run unchanged; P4 and P6 contain Windows-specific sections behind
`#if os(Windows)`.

This matters because **P2 and P3 already have test steps for two of the open
issues**, written when the WinUI versions were fixed:

- P2 step 7-8 covers #390, disabled buttons not appearing disabled
- P3 step 6-9 covers #389, images not being clipped

So the first real test run costs nothing to write. Run P0-P3 and P5, and record
which of the WinUI-fixed behaviours are still broken on GTK. Extend
`UI-test-plan.md` / `UI-test-plan_en.md` with a Linux column or section rather
than starting a separate document.

Since this plan was written, P7-P10 have been added for the Tier 1 and Tier 2
issues below, and P13 for three core-layout issues that are not GTK-specific but
are reachable from here. All of them build and link under GtkBackend in WSL, so
the only thing left for them is a human at the screen.

## Phase 3 -- triage of the open issues

Twelve open issues match Linux/GTK, as of this plan. Two of them (#286, #166)
are Gtk3Backend-only and are dropped with it, leaving ten. Tier 2 has since
picked up three more from `issues.csv` that are filed as `core/unspecified`
rather than against GtkBackend: they are not GTK bugs, but they are reachable
from here, and checking a core layout bug on a second backend is worth more
than checking it on one.

**Tier 1 -- plain widget behaviour, should reproduce under WSLg**

| # | Title | App | Notes |
|---|---|---|---|
| 389 | Images aren't clipped | P3 | already exercised; WinUI half fixed, GTK half open |
| 390 | Disabled buttons don't appear disabled | P2 | already exercised; WinUI half fixed, GTK half open |
| 417 | ScrollView cornerRadius doesn't affect children | P8 | |
| 426 | Horizontal ScrollView swallows parent's scroll wheel | P8 | nested-scroll case |
| 454 | Transparent containers consume click events | P10 | also affects AppKitBackend |
| 476 | List starts with the first item selected | P7 | |
| 478 | Ctrl-Q does not quit | P10 | keyboard handling, WSLg passes keys through |
| 504 | TextField/SecureField shrinks in height after first update | P9 | |

**Tier 2 -- layout and window sizing, WSLg may distort the result**

| # | Title | App | Caveat |
|---|---|---|---|
| 556 | List NavigationSplitView makes weird size decisions | P7 | |
| 295 | Clip text when necessary to reach zero width | P9 | Gtk3Backend half is out of scope |
| 595 | Text inside a ScrollView is cut off | P13 | not GTK-specific; compare against other backends |
| 291 | NavigationSplitView minimum width sizing | P13 | reported as AppKit-affected and Gtk-unaffected |
| 158 | Group behaviour in ZStacks | P13 | not GTK-specific |

Reproduce these, but before claiming a fix, confirm the behaviour on a real
Linux desktop session or at least state that it was only checked under WSLg.

**Tier 3 -- needs something we do not have, or is not a bug**

| # | Title | Why |
|---|---|---|
| 702 | Older GTK 4 breaks button label centering | 26.04 ships 4.22.4; needs an older GTK |
| 386 | Support dark mode | feature; needs a dark theme configured |
| 594 | EventControllerKey.keyPressed cannot return Bool | binding generation, testable without a GUI |
| 52 | libadwaita support | feature request |

Start with Tier 1, cheapest first: #389 and #390 need no new test code.

## Phase 4 -- per issue

1. Reproduce, and capture what was observed (screenshot or a described symptom).
   If it does not reproduce, say so on the issue -- that is a useful result too,
   especially for the ones that predate current GTK versions.
2. Add or extend a `testapp` app that isolates it, following the existing P0-P6
   convention, and add steps to both test plan documents.
3. Fix in `Sources/GtkBackend`, keeping the change as small as the bug. Where
   an issue names both backends, fix GtkBackend and say in the pull request
   that Gtk3Backend was not tested.
4. Verify against the test app, and check the neighbouring behaviour did not
   regress.
5. One commit per issue, in the style already used here (`GtkBackend: ...`).

## Before submitting anything upstream

- `Scripts/format.sh` (SwiftFormat is installed on the Windows side; install it
  in WSL too, or format from Windows).
- The project's LLM policy applies: usage must be disclosed in the pull request
  description, the author must understand the code, and **the description must
  be written by the author, not by an LLM**.
- Prefer one issue per pull request. The contributing guide asks for focused
  changes, and the smaller ones here are exactly that.

## Risks

- **Ubuntu 26.04 has no matching Swift build**, so the toolchain here is the
  24.04 one running against 26.04's libraries, with `libxml2` and ICU shimmed in
  from 24.04 packages. It builds and links, but it is not a combination
  swift.org tests. A failure that looks like a Swift or Foundation bug should be
  suspected of being this before it is reported.
- **WSLg is Wayland**, so window-level behaviour is not identical to a normal
  desktop. Tier 2 results need that caveat.
- **GTK version skew**: 4.22.4 is recent, so bugs about older GTK cannot be
  reproduced here, and fixes verified against it cannot be assumed to help users
  on older distributions.
- Several of these issues are old. Some may already be fixed; confirming that
  and closing them is a legitimate outcome.
