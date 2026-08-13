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
| Swift | **not installed** |
| GTK 4 | **4.22.4** (`libgtk-4-dev`, installed) |
| GTK 3 | not installed, and deliberately so |

WSLg presents a Wayland compositor. Anything about window sizing, minimum
sizes or resizing behaves differently there than on a real desktop session, so
those issues need a caveat (see Tier 2).

## Phase 0 -- toolchain

1. Install Swift in the WSL distribution. Ubuntu 26.04 is new enough that
   swift.org may not publish a matching build; use Swiftly, or fall back to the
   24.04 build, and record which was used.
2. GTK 4 is installed: `libgtk-4-dev` 4.22.4, with pkg-config 2.5.1. Note that
   `sudo` in this distribution asks for a password, so `wsl -u root` is the way
   to install without handling one.
3. Verify: `pkg-config --modversion gtk4` and `swift --version`.

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
./Scripts/test.sh            # unit tests
swift build --product <example>
```

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

## Phase 3 -- triage of the open issues

Twelve open issues match Linux/GTK, as of this plan. Two of them (#286, #166)
are Gtk3Backend-only and are dropped with it, leaving ten.

**Tier 1 -- plain widget behaviour, should reproduce under WSLg**

| # | Title | Notes |
|---|---|---|
| 389 | Images aren't clipped | P3 already exercises it |
| 390 | Disabled buttons don't appear disabled | P2 already exercises it |
| 417 | ScrollView cornerRadius doesn't affect children | |
| 426 | Horizontal ScrollView swallows parent's scroll wheel | needs a nested-scroll test app |
| 454 | Transparent containers consume click events | also affects AppKitBackend |
| 476 | List starts with the first item selected | |
| 478 | Ctrl-Q does not quit | keyboard handling, WSLg passes keys through |
| 504 | TextField/SecureField shrinks in height after first update | |

**Tier 2 -- layout and window sizing, WSLg may distort the result**

| # | Title | Caveat |
|---|---|---|
| 556 | List NavigationSplitView makes weird size decisions | |
| 295 | Clip text when necessary to reach zero width | Gtk3Backend half is out of scope |

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

- **Ubuntu 26.04 may have no matching Swift build.** Resolve in Phase 0 before
  planning around it.
- **WSLg is Wayland**, so window-level behaviour is not identical to a normal
  desktop. Tier 2 results need that caveat.
- **GTK version skew**: 4.22.4 is recent, so bugs about older GTK cannot be
  reproduced here, and fixes verified against it cannot be assumed to help users
  on older distributions.
- Several of these issues are old. Some may already be fixed; confirming that
  and closing them is a legitimate outcome.
