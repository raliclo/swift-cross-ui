# Bug test plan: AppKitBackend and AndroidBackend

Covers the open upstream bugs reachable from the macOS workstation. The
selection comes from `issues.csv`: 33 rows are tagged `bug` and are not yet
fixed, and these are the ten whose backend is reachable there. Gtk, Gtk3 and
WinUI bugs belong to the Windows workstation instead.

`UI-test-plan platform-en.md` is the cross-platform view of the same data, and is the
place to look for which app covers which issue on which platform.

The count is checkable rather than remembered:

```sh
awk -F, 'NR>1 && $2 ~ /bug/ && $4 !~ /^fixed-p/' testapp/issues.csv | wc -l
```

Same working style as the WinUI and Linux plans: reproduce first, measure
rather than infer, and record what was actually observed.

## Scope

| App | Backend | Issues | Where it runs |
| --- | --- | --- | --- |
| P11 | AppKitBackend | #82, #485, #473 | macOS, natively |
| P12 | AndroidBackend | #632, #580, #544 | Android device or emulator |
| P13 | core layout / view graph | #595, #291, #158 | any backend |
| P13 | AppKitBackend | #415 | macOS, natively |
| P14 | UIKitBackend | #324, #254 | iOS Simulator |

P13 is split across two rows on purpose. `issues.csv` files #595, #291 and #158
under `core/unspecified`, not under a backend, so they are testable wherever the
app runs; only #415 is reported against AppKitBackend. Measured, not assumed:
P13 builds and links under GtkBackend in WSL, so those three can be checked
without waiting for a Mac, and a backend that does *not* show them is a useful
result too.

Bugs from the same set that are deliberately excluded appear under "Not
covered" in each section, with the reason.

### Not reachable from the macOS workstation

Recorded so the gaps are visible rather than forgotten. "Blocked" here means
blocked *from macOS* -- the first two rows are routine work on the Windows
workstation, and #289 and #160 already have repro apps there:

| Issues | Where it belongs instead |
| --- | --- |
| #289, #594 | The Windows workstation, under WSLg. #289 is covered by P15 |
| #160, #231 | The Windows workstation. #160 is covered by P16 |
| #286, #166, #179 | Gtk3Backend, which is out of scope everywhere |
| #189 | GtkBackend *on macOS*, which neither workstation runs -- the Gtk3 half is out of scope as well |
| #227 | A Mac Catalyst build target, not yet set up |
| #226 | tvOS |
| #645 | Comparison against several platforms at once, so it needs the others first |

---

## P11: Sliders, Scrollbars And Pickers (macOS)

Build and run:

```sh
zsh testapp/compile.zsh P11
./testapp/output/P11
```

Covered issues:

- #82 (Open): Sliders jitter in RandomNumberGeneratorExample when two sliders
  constrain each other
- #485 (Open): Scrollbar renders pointing the wrong way
- #473 (Open): Compact DatePicker sizing is off with Liquid Glass

Test steps:

1. Launch `P11`.
2. Click `Separate them`, so minimum is 20 and maximum is 80 and neither clamp
   is active. Click `Reset counters`.
3. Drag the **minimum** slider slowly upward past 80. Watch the two write
   counters, to verify #82.
4. Release and read the counters. One drag should advance `min` roughly in step
   with the pointer, and should not advance `max` at all while the sliders are
   apart.
5. Click `Collide them`, then `Reset counters`, then drag the minimum slider
   further right. Both values are now pinned together, so this is where the
   clamp feeds back.
6. Watch the slider handle while dragging: it must stay where the pointer put
   it rather than snapping back and forth.
7. Scroll the row list with the scroll wheel and watch the vertical scrollbar,
   to verify #485. Note which end of the track the thumb sits at when the list
   is at row 1.
8. Scroll to the bottom and note where the thumb sits now.
9. Compare the compact `DatePicker` against the `Reference` button beside it,
   to verify #473. Check the heights match and that neither the date text nor
   the stepper is clipped.
10. Click into the DatePicker and change the date; confirm the control does not
    resize as its contents change.

Expected results:

- Dragging one slider does not write to the other while they are apart. Both
  counters climbing together, or a handle that jumps back after release, is #82.
- The scrollbar thumb is at the **top** when the list is at row 1, and at the
  bottom when scrolled to the end. Reversed is #485.
- The DatePicker matches the reference button's height and clips nothing. Being
  visibly taller, shorter or clipped is #473.

Not covered by P11:

- **#404** (window content size after `View > Show Tab Bar`) needs a system menu
  item that the app cannot drive from its own view tree. Reproducing it means
  toggling the menu by hand and watching whether the content area follows;
  worth doing manually, but not something P11 can assert.
- **#425** (window not focused at launch) is described upstream as intermittent
  -- "every once in a while". A pass/fail step would report success almost every
  time regardless of whether the bug is fixed. If it appears, record the launch
  method, whether Swift Bundler was used, and whether the sidebar had
  transparency.

---

## P12: Button Margins, State And Toggles (Android)

Build and run:

```sh
cd Examples
SCUI_ANDROID=1 swift build --swift-sdk aarch64-unknown-linux-android28 --product P12
```

Or bundle and install it as an APK, following
`Scripts/build-tool-install-android-on-Mac.sh`. P12 also renders on the host
platform, which is useful for checking the layout before deploying, but only
the Android run can verify these issues.

Covered issues:

- #632 (Open): Buttons have an unnecessary margin
- #580 (Open): Rotating the screen resets `@State`
- #544 (Open): Toggle button state is not indicated visually

Test steps:

1. Launch `P12` on a device or emulator with auto-rotate enabled.
2. In the margins section, look at the two blue buttons between the green
   bands, to verify #632. The blue background should reach each button's edges.
3. Measure or eyeball the gap between the blue and the green above and below.
   Any consistent strip of background colour between them is the margin.
4. Tap `Second` or `Third` so the selected tab is not the default, then tap
   `Increment counter` a few times. Note both values.
5. Rotate the device to landscape without touching anything else, to verify
   #580.
6. Read the tab and counter again. Both must be unchanged.
7. Rotate back to portrait and read them once more.
8. In the toggle section, compare the `Forced on` and `Forced off` toggles side
   by side, to verify #544.
9. Tap `Set both on`; confirm the two now look identical to each other.
10. Tap `Set opposite`; confirm they now look different from each other.
11. Compare against the `switch` style toggle below, which uses a different
    component, to see whether the problem is specific to the button style.

Expected results:

- The blue background reaches the button edges. A gap between blue and green is
  #632.
- Tab selection and counter survive rotation unchanged. Reverting to the first
  tab, or the counter returning to 0, is #580.
- The two button-style toggles look different when in opposite states. Looking
  identical is #544.

Not covered by P12:

- **#610** (sheet sizing on Android) is two coupled defects upstream: the layout
  system not respecting the size backends report for sheets, and AndroidBackend
  reporting the wrong size in the first place. Distinguishing them needs
  measured sizes from both layers rather than a visual check, so it needs its
  own instrumented app rather than a step here.

---

## P13: Layout And View Graph (any backend, plus one macOS-only check)

Build and run:

```sh
zsh testapp/compile.zsh P13
./testapp/output/P13          # .exe on Windows
```

Covered issues, by where they have to be checked:

Any backend:

- #595 (Open): Texts inside a ScrollView get unnecessarily cut off
- #291 (Open): NavigationSplitView minimum width sizing
- #158 (Open): Group behaviour in ZStacks

macOS only:

- #415 (Open): Message list benchmark crashes with AppKitBackend

#415 crashes on purpose, so it is behind a button. Do the other three checks
first, then trigger it last. Steps 1-8 are worth running on every backend
available, recording each separately: #291 in particular is reported upstream as
affecting AppKitBackend and not GtkBackend, so agreement between the two is
itself the finding.

Test steps:

1. Launch `P13`. Confirm the window opens and the identifiable list on the left
   renders three identical rows.
2. Compare the two ScrollViews. The left one is plain, the right one applies
   `.fixedSize(horizontal: false, vertical: true)`, which upstream reports as
   the workaround, to verify #595.
3. Confirm the plain ScrollView shows the whole wrapped sentence. If its last
   line is clipped while the `.fixedSize()` one is not, that is #595.
4. Look at the ZStack section, to verify #158. The red, green and blue blocks
   are inside a `Group` inside a `ZStack`, at decreasing sizes.
5. Confirm they overlap, smallest on top, so all three are visible as nested
   rectangles. Laid out side by side or stacked vertically means the Group took
   the container's orientation instead of the z axis, which is #158.
6. Click `Narrower` repeatedly and watch the NavigationSplitView, to verify
   #291. The frame shrinks in 60 px steps.
7. Confirm the detail pane stays visible as the frame narrows. If the split
   stops moving and the detail pane is squeezed out or clipped while the
   sidebar keeps its width, that is #291.
8. Click `Wider` and confirm the split recovers.
9. On macOS: `More duplicates` a few times, then click `Show unidentified list`,
   to verify #415. This renders a `ForEach` over elements that are not
   `Identifiable` and all compare equal.
10. Record whether the app crashes, and if so capture the message. Upstream
    attributes it to the backend receiving duplicate child views. On other
    backends this step is not expected to crash; run it anyway and record that,
    since it bounds the bug to AppKitBackend.

Expected results:

- The plain ScrollView does not clip its text. Needing `.fixedSize()` is #595.
- The Group's children overlap along z. Any side-by-side or vertical layout is
  #158.
- The detail pane survives narrowing. Being squeezed out is #291.
- Rendering the non-Identifiable list does not crash. A crash is #415, and the
  identifiable list beside it is the control showing the same data is fine when
  identity is explicit.

## macOS feature coverage without an upstream issue

The following apps cover AppKit features that are not assigned an open issue:

| App | Feature | macOS check |
| --- | --- | --- |
| P25 | Drag and drop | Drag a file onto the accepting area; verify hover feedback and the received file URL payload. |
| P28 | Hit testing | Click the blue overlay; the click must pass through and increment the button below. |
| P29 | Visual fidelity | Compare the indeterminate progress bar, clipping and disabled editor behaviour against the stated controls. |
| P37 | Window levels | Place another window over the app and verify the selected window-level behaviour. |

For P28, the measurable result is the `Clicks received` counter and the
`underlying button clicked` entries in `p28-debug-events.log`. A visible overlay
that consumes the click is an AppKit regression even if the overlay itself is
drawn correctly.

---

## P14: Rotation Size Proposals And Theme (iOS Simulator)

Build, install and run:

```sh
zsh testapp/compile.zsh -ios P14
xcrun simctl boot swift-cross-ui
open -a Simulator
xcrun simctl install swift-cross-ui testapp/output/P14.app
xcrun simctl launch swift-cross-ui dev.swiftcrossui.testapp.P14
```

`compile.zsh -ios` provisions the simulator itself via `install_tools_ios.zsh`, so
a missing device is created rather than reported.

Covered issues:

- #324 (Open): Content gets an incorrect size proposal on orientation change
- #254 (Open): App background colour is not updated when the system theme changes

Both are about a value rather than an appearance, so P14 records what it was
given instead of asking you to catch a flicker. #324 corrects itself on the next
layout pass, and #254 is one surface disagreeing with others.

Test steps:

1. Launch `P14` in portrait. Note the reported proposed width; it should match
   the device's portrait width.
2. Click `Clear history`.
3. Rotate the simulator to landscape (Cmd-Left Arrow), to verify #324.
4. Read `Width history`. It records up to eight width changes in order.
5. Confirm the history goes straight from the portrait width to the landscape
   width. An intermediate entry **wider than the landscape width**, followed by
   the correct one, is #324 -- the app was proposed more space than exists and
   then corrected.
6. Rotate back to portrait and read the history again.
7. With the app open, switch the system appearance, to verify #254. In the
   simulator use Features > Toggle Appearance, or from a terminal:
   `xcrun simctl ui swift-cross-ui appearance dark`.
8. Compare the three numbered surfaces. The text, the button and the adaptive
   colour block should all change together with the window background behind
   them.
9. Switch back to light and compare again.

Expected results:

- Width history contains only the portrait and landscape widths, in order. An
  extra oversized entry between them is #324.
- Every surface follows the theme. If the controls and the adaptive block
  change while the background behind them stays the previous theme's colour,
  that is #254. The adaptive block is the control here: it proves the theme
  change arrived, so a background that ignores it is the app's own bug.

Not covered by P14:

- **#227** (Mac Catalyst button sizing) shares UIKitBackend but needs a Catalyst
  destination rather than an iOS Simulator one, and upstream supplies only a
  screenshot with no description, so the reproduction conditions are unclear.

---

## Test Record Template

```text
Date:
Commit:
OS / device:
Swift:
App:
Result: Pass / Fail
Steps:
Observed:
Expected:
Logs:
Screenshots:
Notes:
```
