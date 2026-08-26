# Platform test matrix

Which repro app tests which issue, and what running it on each platform tells
you. The per-app steps live in `UI-test-plan overall-en.md`; the strategy behind the
Linux work lives in `UI-test-plan linux-en.md`. This file answers one question only:
*where do I run this, and does the answer count?*

Derived from `issues.csv`, which is the source of truth. To regenerate the
issue-to-app mapping:

```sh
awk -F, 'NR>1 && $4 ~ /p[0-9]+$|p[0-9]+;/ {print $4"  #"$1"  "$3}' testapp/issues.csv
```

## Legend

| | Meaning |
| --- | --- |
| 🎯 | Reported against this platform. A run here decides the issue. |
| 🔍 | Not reported here, but a run is a useful comparison -- agreement or disagreement is itself the finding. |
| ⬜ | Nothing to learn. The app builds and runs, but this platform cannot show this issue. |
| ✅ | Already fixed on this platform. Run it as a regression check. |
| 🚫 | No hardware, simulator or toolchain for it. Which machine that applies to is in the table below, not here. |
| 〰️ | Runs under WSLg, but the result does not settle the issue: it is one of the window-sizing cases WSLg distorts. Reproduce here, confirm on 🐧. |

Desktop columns: 🪟 Windows (WinUIBackend) · 🌊 WSLg (GtkBackend under a
Wayland compositor) · 🐧 Linux (GtkBackend on a real desktop session) ·
🍎 macOS (AppKitBackend). Mobile: 📱 iOS (UIKitBackend) · 🤖 Android
(AndroidBackend).

WSLg and Linux are separate columns because they disagree. WSLg is a Wayland
compositor rather than a desktop session, so window sizing, minimum sizes and
decorations behave differently -- the split that `UI-test-plan linux-en.md` already
records as Tier 1 versus Tier 2. The two rows that are 〰️ under 🌊 but 🎯
under 🐧 are the whole reason for keeping them apart: WSLg can show you the
symptom, but only a desktop session settles it. 〰️ never appears under 🐧 --
it says something about WSLg specifically, not about GtkBackend.

Only #556 and #289 carry it. Tier 2 is not a synonym for "WSLg cannot be
trusted": it collects issues that need *some* caveat, and the reasons differ.
#595 and #158 are flagged as not GTK-specific, #291 is reported as Gtk
**un**affected, and #295's caveat is that the Gtk3Backend half is out of scope.
None of those say anything about WSLg's fidelity, so marking them 〰️ would
claim the compositor distorts results it has no bearing on.

## Where each platform is reachable

This repository is worked on from two machines, so "here" depends on which
checkout you are reading. Stated per machine rather than per file:

| Platform | Windows workstation | macOS workstation |
| --- | --- | --- |
| 🪟 Windows | ✅ native | 🚫 |
| 🌊 WSLg | ✅ WSL2 + WSLg, GTK 4.22.4, Swift 6.3.3 | 🚫 |
| 🐧 Linux | 🚫 no desktop session | 🚫 |
| 🍎 macOS | 🚫 | ✅ native |
| 📱 iOS | 🚫 | ✅ Simulator, iOS 18.4 |
| 🤖 Android | 🚫 | ✅ SDK + NDK, device or emulator |

Neither machine has a real Linux desktop session, so the 🐧 column is currently
unreachable from both. It exists because several results measured under 🌊 are
explicitly provisional until someone repeats them there.

## Binaries

All 18 apps are built on both platforms reachable from the Windows
workstation -- `testapp/output/PN` under 🌊 WSLg, `testapp/output/PN.exe` on
🪟 Windows. Nothing here has been built under 🐧, which is why that column
carries no results. Rebuild with:

```sh
zsh testapp/compile.zsh P0 P1 P2 P3 P4 P5 P6 P7 P8 P9 P10 P11 P12 P13 P14 P15 P16 P17
```

## The matrix

### Open issues and fixed regression coverage -- desktop

| Issue | App | 🪟 | 🌊 | 🐧 | 🍎 | What it is |
| --- | --- | :-: | :-: | :-: | :-: | --- |
| #389 | P3 | ✅ | 🎯 | 🎯 | ⬜ | Images aren't clipped -- WinUI half fixed, GTK half open |
| #390 | P2 | ✅ | 🎯 | 🎯 | ⬜ | Disabled buttons don't look disabled -- same split |
| #476 (Fixed) | P7 | ⬜ | ✅ | ✅ | ⬜ | List starts with the first item selected -- verified fixed on GTK4 and Gtk3 |
| #556 | P7 | ⬜ | 〰️ | 🎯 | ⬜ | NavigationSplitView makes weird size decisions |
| #417 | P8 | ⬜ | 🎯 | 🎯 | ⬜ | ScrollView cornerRadius does not clip children |
| #426 | P8 | ⬜ | 🎯 | 🎯 | ⬜ | Horizontal ScrollView swallows the parent's scroll wheel |
| #504 | P9 | ⬜ | 🎯 | 🎯 | ⬜ | TextField/SecureField shrinks after the first update |
| #295 | P9 | ⬜ | 🎯 | 🎯 | ⬜ | Text not clipped to zero width |
| #478 | P10 | ⬜ | 🎯 | 🎯 | ⬜ | Ctrl-Q does not quit |
| #454 | P10 | ⬜ | 🎯 | 🎯 | 🎯 | Transparent containers eat clicks -- both backends |
| #386 | P15 | 🔍 | 🎯 | 🎯 | ⬜ | Dark mode unsupported |
| #289 | P15 | ⬜ | 〰️ | 🎯 | ⬜ | Window minimum height with Gtk-drawn title bars |
| #160 | P16 | 🎯 | 🔍 | 🔍 | ⬜ | Split view laid out wrong on first render |
| #595 | P13 | 🎯 | 🎯 | 🎯 | 🎯 | Text cut off inside a ScrollView (core) |
| #158 | P13 | 🎯 | 🎯 | 🎯 | 🎯 | Group inside ZStack lays out along the wrong axis (core) |
| #291 | P13 | 🔍 | 🔍 | 🔍 | 🎯 | NavigationSplitView minimum width -- AppKit yes, Gtk no |
| #415 | P13 | 🔍 | 🔍 | 🔍 | 🎯 | Non-Identifiable ForEach crashes on AppKit |
| #264 | P17 | 🎯 | 🎯 | 🎯 | 🎯 | frame(idealWidth:) never reaches fixedSize (core) |
| #266 | P17 | 🎯 | 🎯 | 🎯 | 🎯 | Two layout edge cases (core) |
| #161 | P17 | 🎯 | 🎯 | 🎯 | 🎯 | Picker sized from selection or largest -- needs 2+ platforms |
| #82 | P11 | ⬜ | ⬜ | ⬜ | 🎯 | Mutually clamped sliders jitter |
| #485 | P11 | ⬜ | ⬜ | ⬜ | 🎯 | Scrollbar points the wrong way |
| #473 | P11 | ⬜ | ⬜ | ⬜ | 🎯 | Compact DatePicker sizing |

### Open issues -- mobile

| Issue | App | 📱 | 🤖 | What it is |
| --- | --- | :-: | :-: | --- |
| #595 | P13 | 🎯 | 🎯 | Text cut off inside a ScrollView (core) |
| #158 | P13 | 🎯 | 🎯 | Group inside ZStack lays out along the wrong axis (core) |
| #264 | P17 | 🎯 | 🎯 | frame(idealWidth:) never reaches fixedSize (core) |
| #266 | P17 | 🎯 | 🎯 | Two layout edge cases (core) |
| #161 | P17 | 🎯 | 🎯 | Picker sized from selection or largest -- needs 2+ platforms |
| #324 | P14 | 🎯 | ⬜ | Wrong size proposal on orientation change |
| #254 | P14 | 🎯 | ⬜ | App background does not follow the system theme |
| #632 | P12 | ⬜ | 🎯 | Buttons have an unnecessary margin |
| #580 | P12 | ⬜ | 🎯 | Rotation resets @State |
| #544 | P12 | ⬜ | 🎯 | Toggle state not shown visually |

Core-layout issues appear in both tables: they are backend-independent, so a
run anywhere counts, and disagreement between two platforms is the finding.

### Fixed, kept as regression checks

| Issues | App | 🪟 | What it is |
| --- | --- | :-: | --- |
| #493 #548 | P0 | ✅ | Launch-time crashes |
| #523 #659 #660 | P1 | ✅ | Dialogs and sheets |
| #204 #401 #449 #471 | P2 | ✅ | Controls and styling |
| #156 #190 #470 | P4 | ✅ | Bindings and callback storage |

P5 and P6 carry no upstream issue numbers: P5 is multi-window alerts, P6 is the
Windows GPU video path that the NV12 work came out of.

P25 covers cross-platform drag-and-drop, P28 covers AppKit hit-testing
pass-through, P29 covers visual fidelity, and P37 covers window levels. These
feature apps are included in the macOS source matrix even though they are not
upstream issue rows.

## What to run, by machine

🌊 **WSLg**, on the Windows workstation -- 17 issues, plus #291 and #415 as
comparisons. #476 has been verified fixed on GTK4 and Gtk3. Results for the
〰️ rows stay provisional until 🐧 exists:

```sh
./testapp/output/P2                            # 390
./testapp/output/P3                            # 389
./testapp/output/P7                            # 476 556
./testapp/output/P8                            # 417 426
./testapp/output/P9                            # 504 295
./testapp/output/P10                           # 478 454
./testapp/output/P13                           # 595 158, and 291 415 as comparisons
GTK_THEME=Adwaita:dark ./testapp/output/P15    # 386 289
./testapp/output/P17                           # 264 266 161
```

🪟 **Windows** -- 6 issues, plus #291 and #415 as comparisons:

```sh
./testapp/output/P16.exe                       # 160
./testapp/output/P13.exe                       # 595 158, and 291 415 as comparisons
./testapp/output/P17.exe                       # 264 266 161
./testapp/output/P15.exe                       # 386 as the control only
```

The two lists overlap on the five core-layout issues, which is the point: they
are backend-independent, so running them on both is how a disagreement shows
up. Everything else is specific to one column.

## Three things that invalidate a result

- **P15 without `GTK_THEME=Adwaita:dark` does not test #386.** GtkBackend
  declares `canOverrideWindowColorScheme = false`, so the app's own scheme
  buttons cannot change anything. They are the control; the ambient theme is
  the test.
- **P16 after touching the window does not test #160.** Resizing is one of the
  two things that corrects the layout, so read the pane sizes before moving
  anything.
- **P17 on one platform answers nothing for #161.** The issue is that backends
  disagree, so it needs at least two runs to compare.

## Caveats on the 🌊 column

WSLg is a Wayland compositor, not a desktop session. Window sizing, minimum
sizes and decorations behave differently there, which is why 🌊 and 🐧 are
separate columns rather than one. #556 and #289 are marked 〰️ because both are
about window sizing itself; the rest of Tier 2 is caveated for other reasons
and is not affected by the compositor. Gtk does draw client-side decorations under Wayland, so
#289's precondition holds -- but this is not Fedora with GNOME, so a negative
result bounds the bug rather than closing it.

GTK here is 4.22.4, recent enough that #702 (about *older* GTK 4) cannot be
reproduced at all. Gtk3Backend is out of scope entirely, which drops #286 and
#166 and means #426 is only ever tested against GTK 4.
