# Bug test plan: AppKitBackend and AndroidBackend

Covers the open upstream bugs that can be reproduced from this machine. The
selection comes from `issues.csv`: of the 27 unaddressed bugs, these are the
ones whose backend is reachable here. Gtk, Gtk3 and WinUI bugs are left for the
Windows and WSL sessions.

Same working style as the WinUI and Linux plans: reproduce first, measure
rather than infer, and record what was actually observed.

## Scope

| App | Backend | Issues | Where it runs |
| --- | --- | --- | --- |
| P11 | AppKitBackend | #82, #485, #473 | macOS, natively |
| P12 | AndroidBackend | #632, #580, #544 | Android device or emulator |

Two bugs from the same set are deliberately excluded, and are listed under
"Not covered" below with the reason.

---

## P11: Sliders, Scrollbars And Pickers (macOS)

Build and run:

```sh
zsh testapp/compile.sh P11
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
