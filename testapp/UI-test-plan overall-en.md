# UI Test Plan: P0-P41

This document describes the manual and assisted UI test steps for the apps in `testapp`. The goal is to quickly reproduce and verify backend-specific issues across WinUIBackend, GtkBackend, AppKitBackend, UIKitBackend, and AndroidBackend.

## Preparation

1. Go to the project root:

   ```zsh
   cd /c/Users/lowei/proj/swift-cross-ui
   ```

2. Compile the test apps:

   ```zsh
   zsh testapp/compile.zsh
   ```

3. Go to the output directory:

   ```zsh
   cd testapp/output
   ```

4. Confirm that the runtime resource exists:

   ```zsh
   test -f swift-winui_CWinAppSDK.resources/Microsoft.WindowsAppRuntime.Bootstrap.dll && echo ok
   ```

   Expected result: `ok`.

## Cross-Platform Flow

- For Linux / GtkBackend issues, test WSLg first, then Windows only as a comparison if the app supports it.
- Do not compile from `/mnt/c` inside WSL. Sync the `testapp` Swift/zsh files first, then build under `~/proj/swift-cross-ui`.
- Use zsh scripts only. The current helper scripts are `compile.zsh`, `rsync_WSL.zsh`, `screenshot.zsh`, `videoshot.zsh`, and `test.zsh`.
- Automated dry-runs through `zsh testapp/test.zsh Pn --both` run WSLg first, then Windows. They keep each platform window open for 30 seconds after render by default, then take a final screenshot so the tester can inspect the app and report what changed.
- Screenshots are written to `testapp/output/screenshots` with platform and phase in the filename, such as `p8-wslg-1s-...png`, `p8-wslg-final-...png`, `p8-windows-1s-...png`, and `p8-windows-final-...png`.

## Common Checks

- The app can open its main window.
- The console does not show a fatal error or stack trace.
- The window remains interactive; buttons, inputs, and menus respond.
- The process exits normally after closing the app.
- If a crash occurs, record:
  - Which exe was running
  - Which control was clicked
  - The last log line before the crash
  - Swift / WinUIBackend file names and line numbers from the stack trace

## P0: Critical Lifecycle

Run:

```zsh
./testapp/output/P0.exe
```

Covered issues:

- #493 (Fixed): WinUIBackend may crash when an environment action is called too early
- #548 (Fixed): `@AppStorage` crashes on Windows
- No dedicated issue (Fixed): WinUIBackend `setSizeLimits` unimplemented log
- No dedicated issue (Fixed): WinUIBackend `setIncomingURLHandler` unimplemented log

Test steps:

1. Launch `P0.exe`.
2. Confirm that the main window `P0 WinUI critical checks` appears.
3. Confirm that the console does not show these unimplemented logs:
   - `setSizeLimits(ofWindow:minimum:maximum:) unimplemented`
   - `setIncomingURLHandler(to:) not implemented`
4. Click `Increment @AppStorage` several times to verify #548 (Fixed).
5. Click `Reset` to verify #548 (Fixed).
6. Close the app, launch it again, and confirm that the launch count still updates normally to verify #548 (Fixed).
7. Click `Show AlertScene`; confirm that the alert appears and can be closed with OK to verify #493 (Fixed).
8. Click `Present environment alert after 1 second`; confirm that the alert appears after 1 second to verify #493 (Fixed).
9. Click `Present environment alert now`; confirm that the alert appears to verify #493 (Fixed).

Expected results:

- The app should not crash at launch.
- The `@AppStorage` buttons should not crash; if they do, #548 (Fixed) regressed.
- AlertScene and environment alerts should display normally.
- If an alert crashes and the error contains `XamlRoot`, #493 (Fixed) regressed.

## P1: Dialogs And Sheets

Run:

```zsh
./testapp/output/P1.exe
```

Covered issues:

- #523 (Fixed): Windows file open/save dialogs are slow to appear
- #659 (Fixed): Nested sheets are not supported
- #660 (Fixed): Sheets have default padding

Test steps:

1. Launch `P1.exe`.
2. Click `Open file dialog`.
3. Select any file or cancel; record how long the dialog takes to appear and return to verify #523 (Fixed).
4. Click `Open folder dialog`.
5. Select any folder or cancel; record how long the dialog takes to appear and return to verify #523 (Fixed).
6. Click `Save file dialog`.
7. Select a save destination or cancel; record how long the dialog takes to appear and return to verify #523 (Fixed).
8. Click `Open root sheet`.
9. Observe the padding around the root sheet content to verify #660 (Fixed).
10. Click `Open nested sheet`.
11. Confirm whether the nested sheet appears and closes correctly to verify #659 (Fixed).

Expected results:

- File, folder, and save dialogs should open without crashing.
- Dialogs should not visibly take more than 2 seconds to appear; if one does, record it as a #523 (Fixed) regression.
- If the nested sheet cannot appear or crashes, record it as a #659 (Fixed) regression.
- If the red bar in the root sheet is still clearly surrounded by padding, record it as a #660 (Fixed) regression.

## P2: Controls And Styling

Run:

```zsh
./testapp/output/P2.exe
```

Covered issues:

- #449 (Fixed): Picker options do not update correctly
- #471 (Fixed): TextEditor has a thin border when unfocused
- #401 (Fixed): Full screen button is not disabled when window resizing is disabled
- #390 (Fixed): Disabled buttons do not look visibly disabled

Test steps:

1. Launch `P2.exe`.
2. Open the Picker and confirm that the initial options are only `Vanilla` and `Chocolate` to verify #449 (Fixed).
3. Check `Use expanded Picker options` to verify #449 (Fixed).
4. Open the Picker again and confirm that `Strawberry`, `Mint`, and `Coffee` were added and selectable to verify #449 (Fixed).
5. Click the TextEditor and type `12345`; confirm that no keystrokes are dropped to verify #471 (Fixed).
6. Click another control so the TextEditor loses focus; confirm that there is no unfocused thin border to verify #471 (Fixed).
7. Compare the disabled button and enabled button; confirm whether the visual difference is clear to verify #390 (Fixed).
8. Toggle `Enable button row` and confirm that the disabled state updates visually to verify #390 (Fixed).
9. Toggle `Allow window resizing` to verify #401 (Fixed).
10. Observe the window resize / full screen button behavior to verify #401 (Fixed).

Expected results:

- Picker options should update when state changes, and the dropdown should not immediately disappear; if it fails, record it as a #449 (Fixed) regression.
- Clicking the Picker should not print WinUI/Composition rendering diagnostic logs such as `BVI-*`, `rcBackdropLocal`, or `CachedNewBlur`; if it does, record it as a #204 (Fixed) regression.
- TextEditor input should not drop keystrokes, and the unfocused TextEditor should match the expected borderless appearance; if it fails, record it as a #471 (Fixed) regression.
- Disabled controls should clearly look disabled; if not, record it as a #390 (Fixed) regression.
- When window resizing is disabled, the user should not be able to resize or full screen the window normally; if it is still possible, record it as a #401 (Fixed) regression.

## P3: Layout And Clipping

Run:

```zsh
./testapp/output/P3.exe
```

Covered issues:

- #389 (Fixed): Images are not clipped
- P3 three-column test board initial layout regression (Fixed)

Test steps:

1. Launch `P3.exe`.
2. Before resizing the window, confirm that the sidebar, middle, and detail columns are fully visible.
3. Confirm that the image detail column does not cover the sidebar or middle column.
4. Click `Force state update` and confirm that the three columns do not jump or suddenly correct themselves.
5. Resize the window and confirm that the three columns remain reasonable.
6. Click `Small`, `Medium`, and `Large` in the image size controls.
7. Observe the test image on the black background to verify #389 (Fixed).
8. Confirm whether the Large image is clipped by the 220x140 frame to verify #389 (Fixed).
9. Switch back to Small / Medium and confirm that the image updates normally and remains inside the frame to verify #389 (Fixed).

Expected results:

- The initial three-column layout should be correct without waiting for a state update or resize.
- The oversized image should not spill outside the black frame.
- If the image overflows the frame, record it as a #389 (Fixed) regression.
- If the initial layout is wrong but fixes itself after resize, record it as a P3 three-column layout (Fixed) regression.

## P4: WinUI Native And Callback Stress

Run:

```zsh
./testapp/output/P4.exe
```

Covered issues:

- #190 (Fixed): Callbacks are stored in backend-wide hashmaps
- #156 (Fixed): WinUI-specific escape hatch / native API access
- #204 (Fixed): Update to latest stable WinUI / WinUI console noise
- #470 (Fixed): Regenerate WinUI bindings with latest swift-winrt

Test steps:

1. Launch `P4.exe`.
2. Confirm that the native WinUI banner is displayed to verify #156 (Fixed).
3. Type text into `Native inspection text` to verify #156 (Fixed).
4. Confirm that the native banner content updates to verify #156 (Fixed).
5. Click `Force update` several times to verify #190 (Fixed).
6. Click several `Run N` callback buttons to verify #190 (Fixed).
7. Confirm that the `callbacks` count increases and `Selected row` updates to verify #190 (Fixed).
8. Click `More rows` several times to verify #190 (Fixed).
9. Scroll the row list to the bottom; confirm that the row window slides forward (the displayed range advances) while the scroll position stays visually continuous.
10. Click `Rows 250`, then `Run last`; confirm that the final row window is shown and the UI does not stall for a long time.
11. Click `Run 249`; confirm that `callbacks` and `Selected row` quickly update to 249 to verify #190 (Fixed).
12. Click `Fewer rows` several times to verify #190 (Fixed).
13. Click an existing row button again to verify #190 (Fixed).
14. Open the Picker or trigger a WinUI backdrop update; confirm that the console no longer prints `BVI-*`, `rcBackdropLocal`, or bare matrix/size noise to verify #204 (Fixed).

Expected results:

- Callbacks should not become incorrect, disappear, or crash.
- Scrolling near the bottom/top of the row list should slide the row window forward/backward while keeping at most 50 rows rendered (Windows only; use `Load next rows` on other platforms).
- After changing the row count, both old and new buttons should trigger the correct row.
- WinUI native inspection should be able to change the style of the underlying control.
- `Force update` and editing `Native inspection text` should update the native banner.
- When the row count is large, visible row callbacks should still update quickly.
- If callbacks point to the wrong row after many updates, record it as a #190 (Fixed) regression.
- If WinUI backdrop diagnostic noise appears in the console again, record it as a #204 (Fixed) regression.

## P5: Multi-Window Alerts

Run:

```zsh
./testapp/output/P5.exe
```

Covered issues:

- #675 (Fixed): WinUIBackend could only show one dialog at a time app-wide (alerts queued across windows and couldn't stack within a window)

Test steps:

1. Launch `P5.exe`.
2. Confirm that the main window `P5: Main window` appears.
3. Click `Open another window` to open a secondary window; confirm that a second window `P5: Secondary window` appears.
4. In the main window, click `Show Alert A`; confirm that `Alert A (Main)` appears.
5. While `Alert A (Main)` is still open, switch to the secondary window and click `Show Alert A`; confirm that `Alert A (Secondary)` appears immediately, without waiting for the main window's alert to close, to verify #675 (Fixed).
6. Dismiss both alerts.
7. In the main window, click `Show Alert A`, then click `Show Alert B (stacks on A)` without dismissing Alert A; confirm that `Alert B (Main)` replaces `Alert A (Main)` on screen to verify #675 (Fixed).
8. Click `Show Alert C (stacks on A+B)` without dismissing Alert B; confirm that `Alert C (Main)` appears on top to verify #675 (Fixed).
9. Dismiss `Alert C (Main)`; confirm that `Alert B (Main)` reappears to verify #675 (Fixed).
10. Dismiss `Alert B (Main)`; confirm that `Alert A (Main)` reappears to verify #675 (Fixed).
11. Dismiss `Alert A (Main)`; confirm that no alert remains and the window is interactive again.
12. Repeat steps 7-11 in the secondary window to confirm the same stacking/restoring behavior on a non-main window.
13. Click `Open another window` again from either window; confirm that a third window opens and all three windows can independently show/stack alerts at the same time.

Expected results:

- Alerts on different windows should be able to show at the same time; if the second window's alert does not appear until the first window's alert is dismissed, record it as a #675 (Fixed) regression.
- Stacking Alert B (or C) on the same window while an earlier alert is still open should hide the earlier alert and show the new one on top; if both appear at once in the same window, or the app crashes, record it as a #675 (Fixed) regression.
- Dismissing a stacked alert should restore the alert underneath it in the same window, in the correct order (C -> B -> A); if a restored alert is skipped or restored out of order, record it as a #675 (Fixed) regression.
- Closing one window should not affect alerts in other windows.

## P7: Lists And Split Views (Linux)

Run:

```zsh
./P7
```

Assisted WSLg/Windows comparison:

```zsh
zsh testapp/test.zsh P7 --both
```

Covered issues:

- #476 (Fixed): The List control starts with the first item already selected on the GTK backend
- #556 (Open): Gtk List NavigationSplitView makes weird size decisions

Test steps:

1. Launch `P7`.
2. **Before clicking anything**, look at the plain List and the status line. The selection binding starts as nil, so no row should be highlighted and the status should read `Selection: none`, to verify #476.
3. Click `Cherry` in the plain List; confirm the status updates and only that row is highlighted.
4. Click `Clear selection`; confirm both lists show nothing selected.
5. Click `Select Cherry`; confirm the List highlights it when the selection is set from code.
6. Look at the NavigationSplitView: the sidebar and the detail pane should each keep a sensible share of the 420 px width, to verify #556.
7. Click `Add a fruit's worth of text`, which grows the text above the split view; confirm the split view does not jump to a different division.
8. Resize the window and confirm the split stays proportionate.

Expected results:

- Nothing is selected at launch. A highlighted first row is a #476 regression. Verified fixed on GTK4 and GTK3 under WSLg.
- The detail pane is visible and does not collapse to nothing, and the division does not change when unrelated text changes. Either is #556.

## P8: Scroll Views (Linux)

Run:

```zsh
./P8
```

Assisted WSLg-first flow:

```zsh
zsh testapp/test.zsh P8 --both
zsh testapp/test.zsh P8 --both --showtime 60
zsh testapp/test.zsh P8 --both --no-showtime
```

The assisted flow waits for P8's `RENDER COMPLETE` marker, keeps the WSLg
window open for 30 seconds by default, captures a final screenshot, then repeats
the same sequence on Windows. Use this when the tester needs to inspect the
window live and report the visible problem.

Covered issues:

- #417 (Open): Giving a ScrollView a cornerRadius does not affect its children
- #426 (Open): Horizontal ScrollView swallows scroll wheel inputs for parent vertical ScrollView

Test steps:

1. Launch `P8`.
2. Look at the four corners of the red block in the first ScrollView. The frame has `cornerRadius(20)`, so the red should be rounded off at each corner, to verify #417.
3. Put the pointer over the second ScrollView, away from the horizontal strip, and scroll. Confirm the outer rows move.
4. Put the pointer **over the horizontal strip** and scroll vertically. Confirm the outer view still scrolls, to verify #426.
5. Over the strip, scroll horizontally; confirm the strip itself moves.
6. Scroll the strip to its right-hand end, then keep scrolling; confirm the outer view takes over rather than everything stopping.

Expected results:

- Red does not reach a square corner. If it does, that is #417.
- Vertical scrolling works with the pointer anywhere, including over the horizontal strip. If the outer view freezes there, that is #426.

## P9: Text And Field Sizing (Linux)

Run:

```zsh
./P9
```

Covered issues:

- #504 (Open): GtkBackend TextField/SecureField shrinks in height after first update
- #295 (Open): Clip Text when necessary to reach zero width

Test steps:

1. Launch `P9`. Note the height of the text field, the secure field and the `Reference` button next to them; at launch they should match.
2. Click `Force update` once. The button only increments a counter and does not touch the fields.
3. Compare the field heights against the `Reference` button again, to verify #504.
4. Click `Force update` several more times and confirm the heights do not keep shrinking.
5. Type into both fields and confirm text is still fully visible.
6. In the lower section, click `Narrower` repeatedly. The blue band marks the frame the label was given; the text must stay inside it, to verify #295.
7. Click `Zero width`; confirm the label takes no width rather than refusing to shrink.
8. Click `Wider` and confirm the text reappears as the frame grows.

Expected results:

- Field heights are unchanged by an unrelated update. Any shrink is #504.
- Text never spills past the blue band, and reaches zero width when asked. Spilling is #295.

## P10: Hit Testing And Shortcuts (Linux)

Run:

```zsh
./P10
```

Covered issues:

- #454 (Open): Transparent containers consume click events (AppKitBackend, GtkBackend)
- #478 (Open): GtkBackend Ctrl-Q/Cmd-Q does not quit application

Test steps:

1. Launch `P10`.
2. Click `Click me` several times and confirm `Direct clicks` increments.
3. With `Transparent overlay present` checked, click `Click me too`, which sits under a transparent `Color.clear` layer. Confirm `Covered clicks` increments, to verify #454.
4. Uncheck `Transparent overlay present` and click it again; confirm it increments now.
5. Compare: if the covered button only responds with the overlay removed, that is #454.
6. Click the middle of the orange block on the right and confirm `Hidden clicks` rises. The block is fully **opaque** and hides the button completely; only `allowsHitTesting(false)` can let the click through, which is what makes this a test of the modifier rather than of transparency.
7. Press Ctrl-Q (Cmd-Q on macOS), to verify #478.

Expected results:

- A transparent overlay does not block clicks. If the covered button only works once the overlay is removed, that is #454.
- An opaque layer with `allowsHitTesting(false)` does not block clicks either. If `Hidden clicks` stays at 0, the modifier is not reaching the backend.
- Ctrl-Q quits the app. If the window stays open, that is #478.

## P11: AppKit Sliders, Scrollbars And Pickers (macOS)

Run:

```zsh
./P11
```

Covered issues:

- #82 (Open): AppKitBackend sliders jitter when two sliders constrain each other
- #485 (Open): AppKitBackend scrollbar renders in the wrong direction
- #473 (Open): compact DatePicker sizing is off with Liquid Glass
- #404 (Open, noted only): View > Show Tab Bar affects window content size
- #425 (Open, noted only): window focus at launch is intermittent

Test steps:

1. Launch `P11`.
2. Drag the minimum slider past the maximum slider and watch whether both write counters climb while the values barely move, to verify #82.
3. Press `Separate them`, drag each slider normally, then press `Collide them` and drag again to compare the stable and constrained paths.
4. Inspect the vertical scrollbar in the scroll section and confirm the thumb direction is visually correct, to verify #485.
5. Compare the compact DatePicker height against the neighbouring reference button, to verify #473.
6. For #404, use the app menu manually: View > Show Tab Bar, then note whether the content size changes unexpectedly.
7. For #425, relaunch several times and record whether the window starts unfocused.

Expected results:

- Slider writes should track the slider being dragged, not enter a visible feedback loop.
- The scrollbar thumb should point and move in the expected direction.
- The compact DatePicker should align visually with neighbouring controls.
- #404 and #425 are noted as manual observations rather than strict pass/fail checks.

## P12: Android Margins, Rotation State And Toggles (Android)

Run on Android after building/deploying the app target for the Android backend.
The host build can still be used for a quick layout sanity check.

Covered issues:

- #632 (Open): AndroidBackend buttons have unnecessary margins
- #580 (Open): rotating the screen resets `@State`
- #544 (Open): button-style Toggle does not indicate on/off state visually
- #610 (Open, noted only): sheet sizing needs deeper measurement

Test steps:

1. Launch `P12` on an Android device or emulator.
2. Change the selected tab and increment the counter, then rotate the device to verify #580.
3. Compare the button backgrounds against the green reference bands; any visible gap is #632.
4. Compare the forced-on and forced-off button-style toggles side by side, to verify #544.
5. Press the toggle state buttons and confirm the visual state follows the forced values.
6. Note #610 separately if sheet sizing is being investigated; P12 does not turn it into a simple pass/fail check.

Expected results:

- Rotation should not reset the selected tab or counter.
- Button backgrounds should reach the button bounds without extra margins.
- On and off toggle states should be visually distinct.

## P13: Layout And View Graph (AppKit/Gtk)

Run:

```zsh
./P13
```

Covered issues:

- #415 (Open): non-Identifiable `ForEach` elements can crash AppKitBackend
- #595 (Open): Text inside a ScrollView is cut off
- #291 (Open): NavigationSplitView minimum width is deduced but the split is not moved to honour it
- #158 (Open): Group inside ZStack lays children out in the wrong axis

Test steps:

1. Launch `P13`; do not press the crash path first.
2. Compare the Identifiable list and hidden non-Identifiable section. Press `Show unidentified list (may crash)` only when ready to test #415.
3. In the ScrollView text section, compare the plain text and `.fixedSize()` control, to verify #595.
4. Adjust the split width and confirm the sidebar minimum width is honoured rather than letting the pane collapse, to verify #291.
5. Inspect the Group-in-ZStack section and confirm children overlap on the z axis rather than stacking vertically or horizontally, to verify #158.

Expected results:

- The Identifiable list should remain stable; the non-Identifiable path documents #415 if it crashes.
- ScrollView text should wrap without being clipped.
- Split view minimum widths should be reflected in the visible divider position.
- Group content inside ZStack should overlay, not stack along the container orientation.

## P14: UIKit Rotation And Theme (iOS)

Build and run:

```zsh
zsh testapp/compile.zsh -ios P14
xcrun simctl install swift-cross-ui testapp/output/P14-ios.app
xcrun simctl launch swift-cross-ui dev.swiftcrossui.testapp.P14
```

Covered issues:

- #324 (Open): rotation temporarily gives content a wrong size proposal
- #254 (Open): UIKitBackend restyles controls after a system theme change but leaves the app background behind

Test steps:

1. Launch `P14` in an iOS simulator.
2. Rotate the device and read the width history immediately after rotation, to verify #324.
3. Press `Clear history`, rotate once, and confirm whether a transient too-wide proposal appears before the final width.
4. Switch system appearance while the app is open, using the simulator menu or `xcrun simctl ui <device> appearance dark`.
5. Compare the app background, controls, and explicit adaptive colour block, to verify #254.

Expected results:

- Width history should not show a transient proposal wider than the settled layout after rotation.
- The app background should update together with controls and adaptive colours when the system theme changes.

## P15: Colour Scheme And Window Height (Linux)

Run:

```zsh
./P15                                   # inherit the system theme
GTK_THEME=Adwaita:dark ./P15            # the real test for #386
```

Covered issues:

- #386 (Open): GTK dark mode is unsupported; text keeps its light-mode colours
- #289 (Open): the window's minimum height is wrong where Gtk draws its own title bar (client-side decorations)

Checked in the source before writing these steps: `GtkBackend.swift` declares
`canOverrideWindowColorScheme = false`, and line 200 carries a
`TODO(stackotter): Support preferredColorScheme`. The scheme buttons are
therefore expected to do nothing on GtkBackend. They are the control group: the
same build on WinUIBackend does honour them, which separates "the override is
missing" from "the colours are computed wrongly".

Test steps:

1. Launch with `GTK_THEME=Adwaita:dark ./P15`.
2. Look at "Plain text on the default background" and the labels around it, to
   verify #386. Check whether text stays dark on a dark background.
3. Compare the foreground colours of the `TextField`, `Toggle` and `Button`
   against the theme.
4. Note the `Requested` and `Resolved` values shown on screen.
5. Press `Dark`, `Light` and `System`, and watch `Resolved`. It is expected not
   to change on GtkBackend.
6. Run the same binary on Windows under WinUIBackend and repeat step 5 as the
   control.
7. Drag the bottom edge of the window up until it stops shrinking, to verify
   #289.
8. Note the `Content area` size, and check whether anything is cut off at that
   smallest height.
9. Press `Use tall content` and repeat steps 7-8: the minimum height should
   grow with the content.
10. Press `Use short content` and confirm the window shrinks again.

Expected results:

- Text and controls follow the theme in dark mode. Keeping light-mode colours
  is #386.
- Nothing is clipped at the smallest height the window allows. A minimum that
  does not account for Gtk's own title bar is #289.
- WSLg is Wayland and Gtk uses client-side decorations there, so #289's
  precondition holds. That is not the same as Fedora with GNOME, so a negative
  result bounds the bug rather than closing it.

## P16: Split View Initial Layout (Windows)

Run:

```zsh
./P16.exe
```

Covered issues:

- #160 (Open): WinUIBackend lays out NavigationSplitView incorrectly on the
  initial load, and it snaps to a correct layout on any state change or resize

**Read the numbers before touching anything.** The bug is defined by the first
render, and resizing the window is one of the two things that fixes it, so any
interaction destroys the evidence.

Test steps:

1. Launch `P16.exe`. Do not move or resize the window.
2. Immediately note the sizes reported by the `sidebar` and `detail` panes.
3. Judge by eye whether the layout is visibly wrong -- sidebar filling the
   window, detail squeezed out, and so on.
4. Press `Force update`, which changes a counter unrelated to the layout.
5. Note the two pane sizes again. The difference between step 2 and step 5 is
   #160.
6. Relaunch and trigger the snap by resizing the window instead, to confirm
   both routes fix it.
7. Relaunch, press `Switch to 3 column`, and repeat steps 2-5 for the
   three-column layout.
8. Run the same app on Linux under GtkBackend as the control.

Expected results:

- The pane sizes at first render are already correct, and match the sizes after
  a forced update.
- Different numbers at step 2 and step 5 are #160, and the difference is how
  wrong "very incorrectly" actually is.
- Sizes are displayed live rather than captured into state at first render:
  writing state during a layout pass feeds back into the layout it is
  measuring, and `GeometryReader`'s own documentation warns that content may be
  evaluated several times with different sizes before the layout settles.

## P17: Cross-Backend Layout Comparison (Linux and Windows)

Run:

```zsh
./testapp/output/P17          # GtkBackend, in WSL
./testapp/output/P17.exe      # WinUIBackend, on Windows
```

Covered issues:

- #264 (Open): `frame(idealWidth:idealHeight:)` does not set
  `idealWidthForHeight` / `idealHeightForWidth`, which is what
  `fixedSize(horizontal:vertical:)` reads
- #161 (Open): backends disagree on whether a `Picker` is sized from its
  selected item or its largest item
- #266 (Open): two layout edge cases upstream wrote down while specifying the
  layout algorithm

Unlike P7-P16 this app is not aimed at one backend. **Every check is a
comparison**: run the same build under both backends and compare the numbers.
For #161 the comparison is the issue itself -- it is about backends disagreeing,
so a single-backend result cannot answer it.

Each measured view reports its own size, drawn on top of a blue box that shows
the view's extent. The readout deliberately covers the subject: what is under
test is the subject's box, not its contents.

Test steps:

1. Launch `P17` under one backend and record every reported size before
   changing anything.
2. Compare `subject` against `control` in the first section, to verify #264.
   Both are the same text with `idealWidth: 160`; only the subject also has
   `fixedSize(horizontal: true, vertical: false)`.
3. A subject width near 160 means the ideal width reached `fixedSize`. A width
   matching the control, or the full natural width of the text, is #264.
4. Note the `picker` width, then press `Shortest`, `Medium` and `Longest`,
   noting the width after each, to verify #161.
5. A width that changes with the selection means the picker is sized from the
   selected item; a constant width means it is sized from the largest item.
   Record which, because the issue is that the two backends differ.
6. Step the aspect-ratio scroll view through its heights with `Shorter` and
   `Taller`, to verify #266a. The content is a 2:1 box, so showing a scroll bar
   narrows it and therefore shortens it.
7. Watch for the height at which the scroll bar appears and disappears. It may
   do either, but it must settle. Flickering between the two states without
   settling is the failure.
8. In the last section, compare the three coloured bands, to verify #266b. They
   are a `VStack` of three different natural widths given a fixed height.
9. Press `Less height` and `More height` and check the bands stay equal in
   width at each step.
10. Repeat every step on the other backend and compare the two records.

Expected results:

- #264: the subject is about 160 wide. Matching the control instead means the
  ideal width never reached `fixedSize`.
- #161: whichever sizing rule applies, both backends apply the same one.
  Different rules on the two backends is the issue.
- #266a: the scroll bar settles at every height.
- #266b: all three bands share the widest child's width, at every stack height.

## P6: Zstd Stream Player

Build and run:

```zsh
zsh testapp/compile.zsh P6
./testapp/output/P6.exe
```

On macOS the output binary name may be `P6` instead of `P6.exe`:

```zsh
zsh testapp/compile.zsh P6
./testapp/output/P6
./testapp/output/P6 -core
./testapp/output/P6 --debug
./testapp/output/P6 --frame-drop
./testapp/test_P6.zsh /path/to/video.webm
./testapp/test_P6.zsh -rss --debug /path/to/video.webm
```

Metal is the default macOS renderer. Pass `-core` to use the Core Animation
fallback, or `-metal` to select Metal explicitly. If both flags are present,
the last renderer flag wins.
The default output rate is 30 FPS. Pass `--debug` to enable full-frame duplicate
comparisons and detailed frame diagnostics; normal playback omits both costs.
Late-frame dropping is disabled by default. Pass `--frame-drop` to start with it
enabled, or use the runtime `Frame drop` toggle button to change it. During
playback, changing the toggle restarts video and audio from the current timestamp
so the new setting takes effect immediately.
For unattended runs, `-f` selects the input without the file dialog: `-f` alone
picks the first media file whose name contains `恩典365`, `-f <substring>`
matches any other name, and `-f <path>` takes a path directly. The search covers
the current directory, the directory holding the executable, and the default
input directory. `-autoplay` starts playback immediately and
`-enable-dropframe` turns on frame dropping, so
`P6.exe -f -autoplay -enable-dropframe` needs no clicks at all.
`test_P6.zsh -win` and `P6-test.zsh` both wrap that combination;
`P6-test.zsh [file-pattern]` is the shorter form.
`compile.zsh` builds release by default so GUI timing reflects normal usage. Use
`BUILD_CONFIG=debug` only when unoptimised compiler-level debugging is needed;
app diagnostics should be controlled by app flags such as `--debug`.

`test_P6.zsh` prints its usage when no arguments are provided and otherwise
forwards renderer flags, `--debug`, `--frame-drop`, and the media path to the
compiled P6 binary. Its wrapper-only `-rss` option samples the P6 process RSS
once per second and appends `rss_kb`, `peak_rss_kb`, and the final exit status to
the separate `p6-debug-events-rss.log`; every `-rss` launch clears that file
before recording the new run, and `-rss` is not forwarded to P6.

Runtime tools:

- `ffmpeg` and `ffprobe` must be available on `PATH`.
- `zstd` must be available on `PATH` when selecting a `.zst` file.
- `ffplay` must be available on `PATH` for audio playback.
- LZFSE2/swift_tar `.zst` storybook streams are treated as zstd level 9 sources.
- macOS tool lookup also checks `/opt/homebrew/bin`, `/usr/local/bin`,
  `/opt/local/bin`, `/usr/bin`, and `/bin`, covering Apple Silicon Homebrew,
  Intel Homebrew, MacPorts, and system tools even when the app launches with a
  minimal GUI environment.
- The default file dialog directory checks both `~/proj/LZFSE2/swift_tar/images`
  and `~/proj/lzfse2/swift_tar/images`.

Diagnostics:

- P6 writes lifecycle and error messages only to `p6-debug-events.log` in the
  current working directory, keeping normal terminal output quiet. Detailed frame
  upload, presentation, and per-frame timing messages require `--debug` and are
  also written only to that file.
- `testapp/.compile-work/` and `testapp/output/` are scratch: `compile.zsh` copies
  the selected source to `.compile-work/TestApps/Sources/<name>/main.swift` and
  generates its `Package.swift`, so neither directory belongs in a commit.

Test steps:

1. Launch `P6.exe` and click `Choose file`.
2. Select `storybook-1min-4k60.mp4`, a WebM input, or `storybook-1min-4k60.y4m.zst`.
3. Confirm that the first frame appears and the selectable progress text uses the `Current: 01:17 / 04:02 (32%)` format when duration is available. Drag across the text and copy it to confirm text selection works.
4. Click `Show resolution`; confirm that its button background changes to the active state and a separate bottom line reports input resolution, output resolution, and the 960x540 viewport. Click it again and confirm that the bottom line disappears and the button returns to its inactive background.
5. Click `Play`; confirm that video playback starts and that audio starts too for inputs with an audio track when `ffplay` is available. Confirm that the log reports `playback clock token <n> started <time> speed <s>x fps <f> frame-drop <on|off>`, matching the token and captured settings of the preceding `session token <n> start` line.
6. Click the fixed-label `Sound` toggle during playback; confirm that its background is blue while enabled and uses the normal button appearance while disabled. Confirm that enabling sound restarts decoding from the current media timestamp so audio and video share one starting point, and that playback continues from where it was rather than jumping to zero.
7. With an audio track playing, let a direct MP4/WebM input run for at least three minutes; measure and record whether video progressively falls behind audio at each output resolution.
8. Click `Stop`; confirm that Stop preserves the current position and Play resumes it.
9. Drag the timeline slider through several positions and stop at a specific time. Confirm that `Seek target` updates continuously but only one decoder session starts 200 ms after the final slider change.
10. Click `Seek`; confirm that the displayed frame/time jumps to the slider target, and that playback continues from that target when playback was already running.
11. With the specified WebM sample, seek to 00:50 and confirm that the visible subtitle and spoken audio are both around `卻看我是祂的孩子`. Confirm from a standalone ffplay diagnostic that `-seek2any 1 -ss 50` starts the audio clock near 50.01 seconds instead of falling back near 46.05 seconds.
12. Click `-5s` and `+5s`; confirm that the displayed frame and time move by five seconds and clamp at zero/end.
13. Select `1x`, `2x`, and `3x`; confirm that selecting a speed does not switch focus to another terminal and does not immediately restart the decoder. Press Play or Seek to apply the new speed.
14. Confirm that `30` FPS is selected by default. Select `45` and `60` FPS; confirm that selecting FPS does not switch focus to another terminal and does not immediately restart the decoder. Press Play or Seek to apply the new presentation rate.
15. Select `Preview 960x540`, `1080p 1920x1080`, and `4K 3840x2160`; confirm that selecting resolution does not switch focus to another terminal and does not immediately restart the decoder. Press Play or Seek to apply the new output mode.
16. On macOS, confirm that all selectable playback controls, including `Sound`, `Frame drop`, and `Show resolution`, appear in one row and never add `on` or `off` to their button labels. Click each toggle and confirm that its background is blue while enabled and returns to the normal button appearance while disabled. Enable `Frame drop`; confirm that `Show resolution` is enabled automatically and cannot be turned off until Frame Drop is disabled. Confirm that the status line reports the Frame Drop state. During playback, confirm that toggling Frame Drop restarts one decoder/audio session from the current timestamp.
17. Relaunch with `--debug --frame-drop`, select `4K 3840x2160` and `60` FPS, and confirm that Frame Drop and Show Resolution both start enabled, the preview remains 960x540, the bottom information line reports dropped frames per second, and detailed logs report 3840x2160 frame uploads and cumulative late-frame drops.
18. Load a file, then seek or load another file; confirm that the terminal shows no `Broken pipe`, `Error muxing a packet`, or `Error writing trailer` output from ffmpeg when the previous decoder is stopped.
19. Close the window during playback, confirm the close prompt, and confirm that FFmpeg/Zstd/FFplay child processes exit and that the `P6` process itself also exits, returning the shell prompt.
20. Start playback from `test_P6.zsh`, obtain the ffplay PID from `p6-debug-events.log`, and press Ctrl-C in that terminal. Confirm in the log file that P6 received the signal, waited for ffplay to exit, and left no matching ffplay process running. Confirm that P6 diagnostic lines were not printed in the terminal. Because the script no longer uses `exec`, its observed exit status is shell-dependent when both zsh and P6 receive Ctrl-C.
21. Put a recognizable old line in `p6-debug-events-rss.log`, then relaunch through `test_P6.zsh -rss`, play and seek for at least one minute, and close P6 or press Ctrl-C. Confirm that the old line was cleared and the file contains only the new run's start line, one RSS sample per second, final sample count, peak RSS in KiB, and P6 exit status. Confirm that the terminal contains no RSS diagnostic lines and `p6-debug-events.log` remains reserved for P6 diagnostics.

Expected results:

- MP4, WebM, Y4M, and Y4M.ZST inputs decode at the selected output resolution.
- Direct inputs with audio tracks can play sound through `ffplay`; Y4M / `.zst` video-only paths should not crash.
- The timeline slider can quickly choose a target time, and `Seek` displays or plays from that target.
- Elapsed time, duration, and percentage share one selectable `Current` progress text; there is no separate percentage field in the options row.
- All selectable playback controls appear together in one options row.
- Continuous slider changes are debounced for 200 ms so intermediate drag positions do not repeatedly restart FFmpeg and ffplay.
- Selecting speed, FPS, or output resolution should not switch focus to another terminal, steal focus, or immediately restart the decoder.
- The visible viewport remains 960x540 and scales the decoded frame down for operation in a normal test window.
- `Sound`, `Frame drop`, and `Show resolution` use fixed button labels. Each toggle independently selects blue through `.toggleColor(.blue)`, uses that background while enabled, and returns to the normal button appearance while disabled; state is not appended to its label.
- `Frame drop` is a runtime toggle whose state appears in the status line; enabling it also enables and locks `Show resolution` on so the dropped-frames-per-second value remains visible. `--frame-drop` selects both initial on states.
- `Show resolution` uses an active button background while enabled and adds a separate information line at the bottom of the window; while frame dropping is enabled, that line also shows the sampled dropped-frames-per-second value.
- macOS renders decoded RGBA frames through a reusable three-texture Metal pool instead of allocating a texture or rebuilding a SwiftCrossUI image for every frame.
- Audio starts only after the first video frame is decoded, and video pacing uses an absolute monotonic clock to reduce accumulated per-frame timing drift.
- Each session log records its token, seek time, captured speed, FPS, resolution, and mode; the audio and playback-clock logs retain the same token and captured speed.
- Enabling sound mid-playback restarts decoding at the current media timestamp so the new `ffplay` process and the video stream share one starting point instead of running on unrelated clocks.
- Audio seeking enables non-keyframe demuxer targets so WebM playback starts near the requested slider time instead of falling back several seconds to the preceding video keyframe.
- Playback controls remain responsive while decoding runs off the UI thread.
- Normal playback does not scan complete RGBA frames for equality or synchronously log every frame; `--debug` enables those diagnostics when needed.
- By default, every decoded frame remains eligible for presentation. With `--frame-drop`, frames older than the audio-anchored monotonic deadline are discarded before reaching the UI and Metal renderer; combining it with `--debug` reports cumulative late-frame drops.
- Stopping a decoder early is a normal operation and must stay silent: child stderr is buffered rather than forwarded to the terminal, so ffmpeg's expected EPIPE reports do not appear. A genuine decode failure still surfaces the buffered tool output in the status line.
- Closing the window terminates the `P6` process itself, not just its child processes, so the shell prompt returns without a manual `Ctrl-C`.
- Terminal SIGINT and SIGTERM handlers terminate and synchronously reap the retained ffplay process before P6 exits. Without `exec` in the wrapper script, the final shell-visible Ctrl-C status is not guaranteed to be P6's internal status 130.
- `test_P6.zsh -rss` clears `p6-debug-events-rss.log` at launch, then measures only the P6 process resident memory once per second and records samples and peak RSS there; FFmpeg, ffplay, and zstd child RSS are not included.
- Missing tools or malformed input produce an error in the status line instead of crashing.

Verification status:

- The previously reported A/V desynchronization after timeline seeking is confirmed resolved with the supplied WebM sample. At a requested 00:50 seek, default ffplay demuxer seeking started audio near 46.05 seconds, while `-seek2any 1` starts it near 50.01 seconds. The visible subtitle and spoken phrase around that point are both `卻看我是祂的孩子`.
- The confirmation covers normal playback and timeline seeking without `--debug`. Extended 4K playback at every speed and Frame Drop combination remains a separate stress-test scenario rather than a confirmed regression.
- 2026-08-11: fixed a reproducible Windows-only crash (exception `0xc000001d`, illegal instruction in `dispatch.dll`) that occurred at first-frame publish, most reliably when a single-frame seek immediately terminates the decoder session. Root-caused via a `cdb` crash-dump stack trace to `P6DecoderSession.terminate()` closing `outputHandle` synchronously from inside its own `readabilityHandler` callback, a same-queue `dispatch_sync` self-deadlock that `dispatch.dll` traps instead of hanging. Fixed by moving the close onto a different queue (`DispatchQueue.global().async`). Confirmed fixed by repeated single-frame seeks and normal playback launches with no further crash or new crash dump.
- 2026-08-11: normal playback at default settings (30 FPS, Frame Drop off) was observed dropping approximately 17 frames/sec on Windows, rising to roughly 25 frames/sec at 4K where playback nearly stops. Investigation results:
  - ffmpeg is **not** the bottleneck. Running P6's exact 4K filter chain standalone decoded 20 seconds of video in 5 seconds (about 4x realtime).
  - A release build (`BUILD_CONFIG=release`) did not fix it, so the cost is not merely unoptimised code.
  - The bottleneck is the Windows display path. Each 4K frame previously cost: a 33 MB pipe read, a 33 MB `Array` copy, an `ImageFormats.Image`, a fresh 33 MB `WriteableBitmap` allocation, a 33 MB `memcpy`, an 8.3-million-iteration per-pixel RGBA→BGRA loop, and a SwiftCrossUI view-graph update -- roughly 4 GB/s of memory traffic at 30 FPS.
- 2026-08-11: a GPU presentation path was built for Windows, mirroring the macOS Metal design (`D3D11VideoSurface` in `Sources/WinUIBackend/D3D11VideoInterop.swift`): a D3D11 swap chain plus a rotating pool of three staging textures, presentation driven by frame arrival, with frames written straight into mapped GPU memory. No `Array`, no `ImageFormats.Image`, no `WriteableBitmap`, and no pixel conversion (ffmpeg's `rgba` output is byte-identical to `DXGI_FORMAT_R8G8B8A8_UNORM`). One `memcpy` remains, because `FileHandle.fileDescriptor` is unavailable on Windows; removing it needs a named pipe read via `ReadFile` in place of Foundation's `Pipe`.
- 2026-08-11: **the GPU path is not yet usable.** Two hosting approaches were tried and both are blocked:
  - `SwapChainPanel`: not projected by swift-winui. Activating it via `RoActivateInstance` works (`GetRuntimeClassName` confirms the correct runtime class, and `ISwapChainPanelNative` QI succeeds), but the generated wrapper classes resolve their COM interface lazily through a `try!`, so the process traps with an illegal instruction the moment a wrapped property is touched.
  - Child `HWND` + `CreateSwapChainForHwnd`: the swap chain is created and `Present` succeeds, yet nothing is visible. Since the child window overlaps the visible client area even when mispositioned, the video being entirely absent points to WinUI 3's airspace behaviour -- XAML composes through DirectComposition and occludes plain child windows.
  - Remaining options: host the swap chain on a DirectComposition visual, or create the `SwapChainPanel` and attach it to the visual tree from a C++/WinRT shim so no Swift wrapper is ever constructed.
- 2026-08-11: **the black screen is fixed and the GPU path displays.** No C++ shim was needed: the `SwapChainPanel` is driven entirely through raw COM (added to a projected `Canvas` via `IPanel::get_Children` + `IVector<UIElement>::Append`, sized through `IFrameworkElement::put_Width/put_Height`), so no Swift wrapper is ever constructed and the lazy-QI `try!` is never reached. The swap chain is created with `CreateSwapChainForComposition` and bound with `ISwapChainPanelNative::SetSwapChain` on the UI thread (that API is UI-thread only); the decode thread still only maps, copies, and presents.
- 2026-08-11: **the video appearing in the bottom-right corner was caused by `WinUI.Canvas` always reporting a zero DesiredSize.** A Canvas never measures its children, and `WinUIElementRepresentable`'s default `sizeThatFits` asks the element for exactly that, so the view was treated as 0x0, the layout centred it, and the swap chain drew from the middle of the video area outwards with the rest clipped away. The fix is for the representable to implement `sizeThatFits` itself. **This is a general upstream trap**: any representable rooted at a `Canvas` is mispositioned.
- 2026-08-11: **scaling is solved for 960x540, 1080p and 4K.** A SwapChainPanel composes one swap chain pixel per DIP, so the buffer is sized in physical pixels (which keeps the video sharp) and mapped back with `IDXGISwapChain2::SetMatrixTransform(viewport DIPs / buffer pixels)`. A frame smaller than the viewport is stretched by DXGI via `SetSourceSize`; a larger one (4K) is scaled down by the matrix. Neither needs a shader pass. Every geometry change goes through one API, `D3D11VideoSurface.setViewport(_:frameWidth:frameHeight:)`, which rebuilds the swap chain and texture pool only when their sizes actually change.
- 2026-08-11: the geometry is verified with `-calib`, which fills the swap chain with a red border, a green centre cross and corner blocks, and is then measured by scanning the screenshot's pixels rather than by eye. Both 960x540 and 4K measure as `x=360..1559` = 1200 px = the 960 DIP viewport, with the borders and centre cross where they should be.
- 2026-08-12: **the Windows bottleneck was the pipe, not the GPU, and it is now measured rather than inferred.** Per-stage timings are logged once a second (`stage timings:` lines). At 1080p the read stage cost 102-164 ms per frame against a 33 ms budget, while presenting cost 0-4 ms. The cause is Foundation's `Pipe`: swift-corelibs-foundation calls `CreatePipe(..., 0)` on Windows, so the buffer is the system default of a few kilobytes and an 8 MB frame arrives in thousands of reads, each allocating a `Data` that is then appended into a growing 8 MB buffer and copied a second time into the mapped texture. There is no API to configure that buffer size.
- 2026-08-12: P6 now creates its own Win32 pipe with an 8 MB buffer and reads frames with `ReadFile` straight into the mapped staging texture, in one call when the mapped row pitch matches the frame's rows. The read stage dropped to 0-17 ms per frame and **1080p reports 0 dropped frames/sec in every GPU mode**.
- 2026-08-12: GPU selection flags (`-amd`, `-nvidia`, `-both-gpu`, `-no-gpu`; `-both-gpu` decodes on the Nvidia card and presents on the display's adapter, `-no-gpu` presents through Microsoft's Basic Render Driver as a CPU baseline) plus `testapp/gpu-matrix.zsh`, which runs every mode and reports dropped frames/sec and stage timings. This machine has an AMD Radeon iGPU as adapter 0 and an Nvidia RTX 4060 as adapter 1. Measured over 25 s per mode:

  | Mode | 1080p read | 1080p dropped/s | 4K read | 4K dropped/s |
  |---|---|---|---|---|
  | default | 0-17 ms | 0.0 | 36-40 ms | 0.0 |
  | `-amd` | 1-14 ms | 0.0 | 42-47 ms | 0.0 |
  | `-nvidia` | 3-12 ms | 0.0 | 38-41 ms | 0.0 |
  | `-both-gpu` | 7-16 ms | 0.0 | 33-47 ms | 0.0 |
  | `-no-gpu` (WARP) | 2-3 ms | 0.0 | 43-51 ms | 0.0 |

  Presenting measured 0-6 ms in every mode at every resolution and frame rate. **The GPU choice makes no measurable difference, and neither does using no GPU at all.** Full results, including 60 FPS and the exact ffmpeg arguments per run, are in `testapp/P6_findings/gpu-modes.csv` (written by `gpu-matrix.zsh`); see `testapp/P6_findings/README.md`.
- 2026-08-12: **the decoder is not the bottleneck either.** Running the same filter chain standalone (`ffmpeg ... -f rawvideo -pix_fmt rgba -y NUL`) produced 4K60 frames at about 123 fps, roughly 2.1x realtime, while P6 consumed 1.1-2.3 fps. The same 33 MB frame reads in 58 ms at 4K30 and ten times slower at 4K60, which points at CPU contention: ffmpeg saturates the machine producing frames nothing is waiting for. Pacing the decoder to the playback rate (`-re` / `-readrate`) is the next thing to try.
- 2026-08-12: **the real ceiling was publishing, not the pipe.** After the pipe fix every configuration still sat at 7-8 frames/sec regardless of resolution or frame rate, which is the signature of a fixed per-frame cost rather than a bandwidth limit. Timing the main-actor hop showed it: `acceptFrame` sets `currentTime`, `seekPosition` and `status`, all `@Published`, so **every frame rebuilt the view graph and ran a WinUI layout pass, measured at 97 ms per frame** against budgets of 16-33 ms. The video never goes through the view graph, so the timeline and status text are now published at 2 Hz instead of per frame. Results, 20 s per configuration:

  | Configuration | Before | After |
  |---|---|---|
  | 1080p @ 30 | 7.8 fps | **26.6-29.2 fps**, 0.7-2.9 dropped/s |
  | 1080p @ 60 | 7.7 fps | **49.5-50.8 fps**, 7.9-10.1 dropped/s |
  | 4K @ 30 | 6.9 fps | **27.5-28.2 fps**, 1.2-2.1 dropped/s |
  | 4K @ 60 | 1.1 fps | 0.9-25.7 fps, 33-57 dropped/s |

  A single state update costing ~100 ms is a WinUIBackend finding in its own right and is worth investigating separately.
- 2026-08-12: two corrections to earlier entries. The dropped-frame figures reported as 0.0 were a bug in `gpu-matrix.zsh`, which summed the wrong awk field; drops were always in the tens per second at 4K. And pacing the decoder with ffmpeg's `-readrate` (the `-pace` flag) made no measurable difference, so the CPU-contention theory was wrong.
- 2026-08-12: **4K @ 60 is transport-bound and stays broken.** It needs about 2 GB/s of RGBA through the pipe, and frame dropping cannot help because a pipe cannot seek -- every frame to be dropped must still be read in full. 4K @ 30 is 1 GB/s and reaches 28 fps, which puts the measured ceiling near 1 GB/s. Across three repeats the five GPU modes vary wildly (`-both-gpu` measured 25.7, 10.2 and 5.6 fps) with no reproducible ordering, except that `-no-gpu` is consistently worst because CPU rasterising competes with the reader. The way out is fewer bytes: NV12 is 12 bpp against RGBA's 32, taking 4K @ 60 from 2 GB/s to 750 MB/s.
- 2026-08-12: **4K@60 is fixed by decoding to NV12 and converting on the GPU.** ffmpeg now emits `-pix_fmt nv12` (12 bpp against RGBA's 32), and a D3D11 video processor converts and scales it into the back buffer, replacing the `SetSourceSize` stretch on that path. NV12 has nothing to do with Nvidia -- "NV" is the FourCC -- so the choice is made by probing whether the presenting adapter can create the conversion, not by looking for a vendor. `-rgba` forces the old path as a control. Measured at 4K@60, 20 s per mode:

  | Mode | Format | fps | dropped/s | read |
  |---|---|---|---|---|
  | default | nv12 | **52.1** | 8.0 | 2.6 ms |
  | `-amd` | nv12 | **51.3** | 7.8 | 2.8 ms |
  | `-nvidia` | nv12 | **49.4** | 9.5 | 3.5 ms |
  | `-both-gpu` | nv12 | **51.3** | 7.8 | 4.3 ms |
  | `-no-gpu` | rgba (fell back) | 13.4 | 53.3 | 62.1 ms |

  Against 0.9-25.7 fps and 33-57 dropped/s on the RGBA path. The one mode that falls back is its own control within the same run: the pixel format is what matters, not the GPU. Verified visually as well -- colours are correct with `DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709` in and `RGB_FULL_G22_NONE_P709` out, and the picture still lands on exactly the 1200 px viewport (`x=173..1372` in a non-maximised window).
- 2026-08-12: three bugs found while building that path, all worth remembering:
  - The chroma plane's offset in a mapped NV12 texture **is `rowPitch * height`**, and must not be derived from the mapped size. This driver reports `DepthPitch` as `rowPitch * height` (2048 x 1080), not `rowPitch * height * 3/2`, so subtracting the chroma half landed chroma in the middle of the luma plane. The picture came out bright green with a corrupted lower half.
  - A video processor input texture needs `D3D11_BIND_DECODER`, not `D3D11_BIND_SHADER_RESOURCE`: the video engine reads it, the shader units do not. Otherwise `CreateVideoProcessorInputView` fails with `E_INVALIDARG`.
  - The NV12 capability probe has to run on the adapter that will present. Probing the default adapter and then presenting from the software one chose NV12 on a device that cannot convert it, and the NV12 bytes then reached the RGBA image fallback and trapped. The probe is adapter-aware now and the fallback never builds an RGBA image from NV12 bytes.
- 2026-08-12: a bigger decoder pipe buffer does not help. At 4K@60: 25 MB (two frames, the default) gave 49.9 fps, 128 MB gave 51.6, 512 MB gave 48.2, and **2 GB gave 45.3** -- slightly worse than the default. `CreatePipe` accepts 2 GB, but a pipe buffer absorbs jitter rather than raising throughput, and letting the decoder run seconds ahead only wastes memory and has to be discarded on a seek. The earlier 8 MB fix mattered only because the buffer was smaller than a single frame. `-pipe-mb <n>` re-runs this.
- 2026-08-13: **the decoder no longer opens console windows.** P6 spawns ffmpeg, ffplay, zstd and two ffprobes, and restarts the decoder on every resolution or frame-rate change; each spawn opened a console window whenever P6 had no console to inherit, which is the case when it is launched from Explorer or from a pty-based terminal. Foundation's `Process` passes only `CREATE_UNICODE_ENVIRONMENT` and offers no way to add `CREATE_NO_WINDOW`, so all five spawns now go through `P6WindowlessProcess`, which calls `CreateProcessW` directly. That also meant reimplementing argument quoting, handle inheritance, termination and exit codes; other platforms keep the Foundation path. See `testapp/todo-foundation.md`.
- 2026-08-13: linking the apps as GUI-subsystem executables was tried and reverted. It removes the console Explorer opens, but with children still spawned through Foundation it makes things worse: with no console to inherit, ffmpeg and ffplay get a console window each for as long as they run. The reasoning is recorded in `compile.zsh` so it is not attempted again without fixing the spawning first.
- 2026-08-13: **`-maximized` and bringing the window to the front now work**, and the fix was to identify the window by its title. The previous lookup took the calling thread's first visible window and fell back to `GetForegroundWindow()`, so before the XAML window existed it maximised and activated whatever the user was using -- the terminal that launched P6. It also timed the retry window from process start, which had already expired by the time the window appeared several seconds later. Both are fixed: matched by title, retried for five seconds from the moment the window is first found.
- 2026-08-13: **960x540 was cropped on the NV12 path** while 1080p and 4K were correct. The two paths present different regions: RGBA copies the frame into the buffer's corner and lets DXGI stretch that region, so the source is the frame; NV12 goes through the video processor, which scales the frame across the whole buffer, so the source is the whole buffer. Asking for the frame region there presented only its top-left corner, stretched. It is invisible whenever the frame is at least as large as the viewport, because the buffer is then the frame size -- which is why only the smallest preset showed it. Re-calibrated after the fix: the video spans `x=360..1559`, 1200 px, at every preset.
- Windows P6 follow-ups (not implemented yet):
  - The video area is fixed at 960x540 and **does not resize with the window**. `setViewport` is already the entry point for that -- it just needs the window size wired into it -- and the test steps should gain a "drag the window edge; the video area scales with it without distortion" check.
  - **4K playback still does not advance on its own** (about 20 dropped frames/sec, the progress bar stalls). Dragging the progress bar shows the frame correctly, so the bottleneck is not the presentation path but the 33 MB per frame read through Foundation's `Pipe`. Fixing it needs a named pipe read via `ReadFile`, or hardware decoding/CUDA.
  - CUDA is not implemented; the path is pure D3D11/DXGI today.

RSS stress record:

- `p6-debug-events-rss-8845476c-speed3x,fps60,4k_3840x2160_sound_on_frame_drop.log` records P6 commit `8845476c` at 3x speed, 60 FPS, 3840x2160 output, Sound On, and Frame Drop enabled.
- The run lasted from 2026-08-04 18:25:39 UTC through 18:28:58 UTC, collected 196 valid one-second samples, and exited successfully with status 0.
- P6 peak RSS was 2,398,896 KiB (approximately 2.29 GiB), and average sampled RSS was approximately 1.92 GiB. These values exclude FFmpeg, ffplay, and zstd child processes.

## P18: File Dialogs (Linux and Windows)

Run:

```zsh
./testapp/output/P18          # GtkBackend, in WSL
./testapp/output/P18.exe      # WinUIBackend, on Windows
```

Not tied to an issue. GtkBackend moved off `GtkFileChooserNative`, which the
GIR marks `deprecated="1"` and which did not close its dialog on Wayland
without an xdg-desktop-portal, onto `GtkFileDialog`. The migration rewrote four
paths and only a plain single-file open had ever been run. This app runs the
rest and compares them against WinUIBackend.

Not covered: multiple selection. `PresentSingleFileOpenDialogAction` hardcodes
`allowMultipleSelections: false`, so `gtk_file_dialog_open_multiple` cannot be
reached from any application.

Test steps:

1. Launch P18 under one backend. Each button opens one dialog and reports what
   came back on the line beneath it.
2. Press `Open a file`, choose any file, and confirm the dialog closes and the
   line shows the path. **The dialog closing is itself part of the result** --
   the original defect was a dialog that stayed on screen after delivering the
   file.
3. Repeat with Cancel and confirm the dialog closes and the line reads
   `cancelled`.
4. Press `Choose a folder`, select a directory, and confirm the same two things.
   This is a different GTK call from the file open.
5. Press `Choose a save destination`. Confirm the name field is prefilled with
   `p18-example.txt`, which is the only path that exercises the initial name.
6. Repeat every step under the other backend and compare. What matters is
   whether both deliver a path and both dismiss the dialog, not that the
   dialogs look alike.

## P19: Flat Menus (Linux and Windows)

Run:

```zsh
./testapp/output/P19          # GtkBackend, in WSL
./testapp/output/P19.exe      # WinUIBackend, on Windows
```

The two backends render the same `Menu` through different mechanisms and the
app cannot choose between them. GtkBackend conforms to `PopoverMenus`, creating
and positioning a separate menu widget; WinUIBackend conforms to
`AttachedMenus`, handing a menu to a button and letting the platform build it.
These are two implementations of one feature, not a capability either lacks.

P19 keeps to a single flat level so that any difference is unambiguously about
how items render. Nesting is P20.

Test steps:

1. Launch P19 and press `Open the menu`.
2. Confirm all five entries appear: two buttons, a non-clickable text item, a
   separator, and a toggle.
3. Note whether the text item and the separator render at all. A backend that
   drops either is the finding.
4. Press `Button item` and confirm `last action` updates.
5. Open the menu again, use the toggle, and confirm `toggle item` reflects the
   new state. Note whether the menu stays open or closes when a toggle is used.
6. Note where the menu appears relative to the button, and record it. The two
   mechanisms position menus differently and this is the comparison.
7. Repeat under the other backend.

## P20: Nested Menus (Linux and Windows)

Run:

```zsh
./testapp/output/P20          # GtkBackend, in WSL
./testapp/output/P20.exe      # WinUIBackend, on Windows
```

Separate from P19 on purpose. Nesting is where the two mechanisms have the most
room to diverge: one gets the whole tree from the platform, the other builds and
positions every level itself.

Every level carries a clickable item, so `level 2 opens but its button does
nothing` can be told apart from `level 3 never appears`.

Test steps:

1. Launch P20 and press `Open the menu`.
2. Press `Level 1 item` and confirm `last action` reads `level 1`.
3. Open the menu again and hover or click `Level 2 submenu`. Record which one
   opens it -- hover and click are both legitimate and the backends may differ.
4. Press `Level 2 item` and confirm `last action` reads `level 2`.
5. Open `Level 3 submenu` and confirm it appears at all. This is the step most
   likely to fail on one side.
6. Press `Level 3 item`, then use `Level 3 toggle`, and confirm both reach the
   app: `last action` reads `level 3` and `level 3 toggle` flips.
7. Note where each submenu lands relative to its parent, especially near a
   screen edge.
8. Repeat under the other backend.

## P6-v2: Video Playback on GtkBackend (Linux and Windows)

Run:

```zsh
./testapp/output/P6-v2 -i <file> -autoplay              # GtkBackend, in WSL
./testapp/output/P6-v2.exe -i <file> -autoplay          # GtkBackend, on Windows
```

Build it with `-gtk4`. P6 is **not** the comparison target on Windows in the
usual sense: P6 is the WinUI/D3D11 implementation and `compile.zsh -gtk4`
refuses to build it, because a SwapChainPanel and a D3D11 composition swap chain
have no GtkBackend equivalent. P6-v2 is the GTK answer to the same question,
written fresh, keeping P6's measurement vocabulary so the numbers line up.

Flags that matter:

| flag | effect |
|---|---|
| `-cpu` | force software decode |
| `-gpu` | force hardware decode; refuses to start if none is available |
| (default) | try hardware, fall back to software, and say which ran |
| `-mute` | no ffplay; use this for measurement runs |
| `-seconds N` | exit after N seconds and print the summary |
| `-speed` `-fps` `-res` | preset the pickers so a run needs no clicking |

Test steps:

1. Launch with `-autoplay -seconds 20 --debug` and confirm the window renders.
   On Windows the window does not respond to AppActivate, so capture it with
   `zsh testapp/screenshot.zsh -w "P6-v2 GTK playback" <label>`, which reads the
   window directly rather than the desktop.
2. Read the status line. It states the decode path and the presentation path
   separately -- `decode d3d11va, present memory-texture (CPU)`. Presentation is
   the CPU path in every mode today; the flag switches decode only.
3. Confirm audio. It is a separate ffplay process, so sync is not enforced: at
   1x it tracks well enough to watch, at 3x it drifts. That is expected.
4. Run `-cpu` and `-gpu` back to back at the same speed, fps and resolution, and
   compare the summary lines. On this machine they came out within noise of each
   other, because the bottleneck is the RGBA pipe read, not decode.
5. Push the speed to `3x` and watch `dropped/sec`. Dropping only happens when
   frames arrive faster than they can be shown; a decoder that is simply slower
   than the target presents everything and reports a lower fps instead.
6. Repeat on the other platform and compare. WSL has no GPU path at all -- no
   render node, so GTK is on llvmpipe -- so a Windows-against-WSL comparison here
   measures two different rendering stacks, not two operating systems.

## P21: Input Controls (Linux and Windows)

Run:

```zsh
./testapp/output/P21          # GtkBackend, in WSL
./testapp/output/P21.exe      # WinUIBackend, on Windows
```

The widest uncovered surface. ToggleSwitch, ToggleButton and Checkbox appear in
no other test app. Every control appears twice, enabled and disabled.

Test steps:

1. Press `Enabled` under Button and confirm `clicks` rises.
2. Press `Disabled` and confirm `clicks` does **not** rise. A disabled control
   that still accepts input is the finding here, and it looks correct in a
   screenshot.
3. Work down each toggle style -- plain, `.switch`, `.button`, `.checkbox` --
   operating the enabled one and confirming the disabled one refuses.
4. Compare how each backend renders the disabled state: greyed label, dimmed
   widget, or no change at all.
5. Drag both sliders; the disabled one must not move.
6. Type into `TextField`, `SecureField` and `TextEditor`, then try their
   disabled counterparts.
7. Confirm `ContentUnavailableView` shows both its title and description.
8. Repeat under the other backend.

## P22: Text Styles (Linux and Windows)

Run:

```zsh
./testapp/output/P22 --debug          # GtkBackend, in WSL
./testapp/output/P22.exe --debug      # WinUIBackend, on Windows
```

Worth doing early, because font metrics are the measuring stick for every other
layout comparison. A backend whose text is systematically wider will produce
different results in P17's sizing checks and P7's split ratios, and without this
app that difference gets attributed to the layout code instead of the font.

Test steps:

1. Run with `--debug` and collect the reported sizes for each of the eight
   samples. These are numbers, not impressions of a screenshot.
2. Compare the two backends sample by sample. A consistent ratio across all
   eight is a font difference; a difference at one size only is a layout bug.
3. Press `Narrower` and `Wider` and record where the wrap lands at each width.
4. Check the three alignment rows inside their fixed 320pt frames.
5. Repeat under the other backend.

## P23: Tables (Linux and Windows)

Run:

```zsh
./testapp/output/P23 --debug          # GtkBackend, in WSL
./testapp/output/P23.exe --debug      # WinUIBackend, on Windows
```

Column width is the interesting part. Nothing in the API states a width, so each
backend picks: from the header, from the widest cell, from the first screenful,
or by dividing the available space. Column 2 is deliberately wider than its
header and column 3 narrower, so which rule is in use is visible at a glance.

Test steps:

1. Note where each column boundary lands, and which of the four rules that
   implies.
2. Look at row 3, whose cell is far longer than any header. Record whether it
   widens its column or is truncated.
3. Press `More rows` past the window height and confirm whether the table
   scrolls or clips.
4. Press `Fewer rows` and confirm the layout recovers rather than leaving a gap.
5. Repeat under the other backend.

## P24: Navigation Stack (Linux and Windows)

Run:

```zsh
./testapp/output/P24 --debug          # GtkBackend, in WSL
./testapp/output/P24.exe --debug      # WinUIBackend, on Windows
```

`NavigationStack` and `NavigationLink` appear in no other test app. This gap was
once dismissed on the grounds that P7 and P16 cover navigation, which was wrong:
those exercise `NavigationSplitView`, a different type with a different layout
model. A sidebar-and-detail split is not a push-and-pop stack.

What a stack has that a split view does not is history.

Test steps:

1. Push three levels with `Push level N` and confirm each screen appears.
2. Go back through them and confirm they return in order.
3. At each level press `Record a push` and compare `pushes recorded` against the
   level shown. The counter lives outside the stack on purpose: if the screen
   says level 2 while the counter says 3, that disagreement is the finding.
4. Press `Increment counter` at depth, then go back, and confirm the path
   survived the state change.
5. Press `Pop to root` and confirm both the screen and the counter reset.
6. Repeat under the other backend.

## P25: Drag and Drop (Linux and Windows)

Run:

```zsh
./testapp/output/P25 --debug          # GtkBackend, in WSL
./testapp/output/P25.exe --debug      # -gtk4 build, on Windows
```

Drag and drop appears in no other test app because SwiftCrossUI had no API for it
until `onDrop(of:isTargeted:perform:)` was added. The questions worth asking are
the ones where the platforms have room to disagree, not whether a drop arrives:
Windows delivers a path through `CF_HDROP` and X11 delivers a `text/uri-list`, so
`received` is printed verbatim and never normalised.

Test steps:

1. Drag a file from the file manager over the accepting area and confirm it
   highlights **before** the button is released. A backend that only reacts on
   release is usable but wrong, and invisible without somewhere to look.
2. Drop the file and confirm `state` reads `accepted`, `count` is 1, and
   `received` shows the payload as the platform delivered it.
3. Drag the same file over the refusing area and confirm it does **not**
   highlight and reports nothing. This is why there are two areas: a drop zone
   that silently swallows what it cannot handle looks identical to one that
   rejects it, until they are side by side.
4. Drop several files at once and record whether they arrive as several items or
   as one string.
5. Repeat on the other platform and compare the two `received` values.

Note: this cannot be driven by an action file. Drag and drop is an OS-level
negotiation, not a sequence of mouse events, so `InputEvent` cannot synthesise
it; step 1 onwards needs a real drag.

## P26: Networking and the App Cache (Linux and Windows)

Run:

```zsh
./testapp/output/P26 --debug
zsh testapp/test.zsh P26 --cache-only   # cache assertions without the window
```

Covers `AsyncImage`, the `appCache` and the networking comparison table. Unlike
every other Pn, half of this is observable only across runs -- a cache proves
itself by the second fetch not downloading anything.

Test steps:

1. Launch with no cache present and confirm the images load and the cache
   directory is created on first fetch.
2. Relaunch and confirm nothing is downloaded and the images still appear.
3. Check the `not_latest` column reports staleness rather than deleting the
   entry -- a cached copy has to survive a failed fetch, or going offline loses
   the content it was meant to protect.
4. Switch to the SwiftUI tab and confirm it renders nothing on Linux, which is
   correct: SwiftUI is not available there.
5. Confirm the Summary table's cells can be selected and copied.

## P27: Backend Feature Coverage (Linux and Windows)

Run:

```zsh
zsh testapp/test.zsh P27 --both
```

Covers backend features whose absence should be exposed as visible fallback or
diagnostic behaviour rather than a silent no-op or hard crash.

A missing backend conformance goes through `@CastBackend`, which turns it into
`fatalError("'GtkBackend' does not implement ...")`. So an app containing a
`WebView` aborts on GTK the moment that view is laid out, and `AngularGradient`
does the same -- both on Linux and on Windows `-gtk4`. AppKit implements both.

Test steps:

1. Show a `WebView` and confirm the app does not abort.
2. Show an `AngularGradient` beside a `LinearGradient` and a `RadialGradient`
   and confirm all three render.
3. Repeat under WinUIBackend and AppKit and compare.
4. Confirm that a feature a backend genuinely cannot provide degrades visibly
   (a blank area) rather than aborting -- the decision this app exists to force.

## P28: Control Styles (Linux and Windows)

**Planned, not yet written.** Covers styles that assert in a debug build and
silently downgrade in release.

`supportedPickerStyles` is `[.menu]` on GtkBackend against `[.menu, .segmented,
.radioGroup]` on AppKit, and `supportedDatePickerStyles` lacks `.compact`. The
style modifiers hit `assertionFailure` and fall back to `.automatic`, so
`.pickerStyle(.segmented)` crashes a debug GTK build and quietly becomes a
dropdown in release -- a different-looking control from every other platform.

Planned test steps:

1. Show one picker per style -- `.menu`, `.segmented`, `.radioGroup`, `.palette`
   -- and record which render as asked and which silently become a dropdown.
2. Same for `.datePickerStyle(.compact)` against `.graphical`.
3. Confirm a debug build does not abort on an unsupported style.
4. Set `displayedComponents: .hourAndMinute` and confirm time entry appears.
   GtkBackend currently logs `time picker is unimplemented` and shows a bare
   month grid, in the wrong calendar and timezone.
5. Compare all of the above against WinUIBackend.

## P29: Visual Fidelity (Linux and Windows)

Run:

```zsh
zsh testapp/test.zsh P29 --both
```

Covers output that can be wrong on one backend with no diagnostic at all -- the
failures a log will never reveal.

Test steps:

1. Show an indeterminate `ProgressView()` with no value. GtkBackend sets the
   fraction to zero and never pulses, so it renders as a static empty bar and
   reads as "stuck"; AppKit and WinUI animate it.
2. Put an oversized image inside `.cornerRadius(20)`. The clip is rectangular on
   GtkBackend, so the corners stay square underneath a rounded border; AppKit
   and WinUI clip to the rounded shape.
3. Show a `List` whose rows have an explicit `.frame(height:)` and compare the
   rendered heights against the layout. GtkBackend discards the row heights it
   is handed and reports zero base padding while the theme adds real padding, so
   the list is measured differently from how it draws.
4. Put a `TextEditor` inside `.disabled(true)` and confirm it cannot be typed
   into. GtkBackend never sets `sensitive` on it.
5. Compare `.fontWeight(.semibold)` against `.bold`; they map to the same CSS
   weight on GtkBackend.

## P30: Effects and Animation (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** Covers the
largest protocol-level gap: SwiftCrossUI has no animation layer at all, and only
the effect modifiers currently available in the project can be exercised.

There is no `Animation`, `withAnimation`, `.animation(_:value:)`, `.transition`
or `Namespace`, and no backend protocol for any of them. Nor is there `.opacity`,
`.shadow`, `.blur`, `.rotationEffect`, `.scaleEffect`, `.offset`, `.zIndex`,
`.clipShape` or `.mask` -- `.clipped()` and `.cornerRadius()` are the only two
that exist. Every SwiftUI state change is implicitly animatable, so this is the
widest behavioural divergence in the toolkit.

This app is written **before** the feature, deliberately: it starts as a list of
things that do not compile, and each line that starts compiling is the progress
report. Until then it documents the boundary in one place instead of a dozen
issues.

Current automated flow:

```zsh
zsh testapp/test.zsh P30 --both
```

The app shows compileable visual/geometric effect samples and keeps the missing
animation APIs visible as text. It also writes `p30-debug-events.log` when run
with `--debug`.

Test steps:

1. Toggle a `@State` value that changes a frame and confirm whether the change is
   instant (current behaviour) or animated.
2. Apply `.opacity(0.5)`, `.shadow(...)`, `.rotationEffect(...)`,
   `.scaleEffect(...)` and `.offset(...)` and record which compile at all.
3. Insert and remove a view with `.transition(...)`.
4. Compare each against the same code under AppKit.

## P31: Focus and Keyboard (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** Roughly half of
what this app has to check can be written today; the other half remains a list
of calls that do not compile.

Nothing in SwiftCrossUI names focus. There is no `@FocusState`, no
`.focused(_:)` and no `.focusable()`, so an app cannot say which field starts
focused, cannot move focus after a button is pressed, and cannot read where
focus currently is. Whatever the platform does by default is the entire
behaviour.

Keyboard shortcuts have the same shape. There is no `.keyboardShortcut`, no
`KeyEquivalent` and no `EventModifiers`. `Commands` and `CommandMenu` do build a
menu bar, but they resolve to `ResolvedMenu.Item`, whose `button` case carries a
label and an action and nothing else -- there is no field a key equivalent could
travel in, so the gap is in the data structure, not only in the modifier.
`CommandGroup` does not exist at all.

Two backend behaviours are worth measuring on their own. GtkBackend installs
exactly one accelerator, `<Control>q` bound to `app.quit`, in
`installQuitShortcut()`; it is the only key binding the toolkit creates.
`createAlert()` then attaches a shortcut controller that consumes `Escape` so it
cannot close the dialog, and the response handler discards GTK's delete-event
response. Both are deliberate, and both are invisible until an app presses the
key and reports what happened.

Test steps:

1. Tab through a window holding a `TextField`, a `Button`, a `Toggle` and a
   `Slider`, and record the order focus visits them and whether the focused
   control is visibly marked. This is entirely the platform's doing, so a
   difference here is a GTK-against-WinUI difference and not a SwiftCrossUI one.
2. Press Space and Return on each focused control and record which ones
   activate. A control that is reachable but not operable from the keyboard
   looks correct in a screenshot.
3. Press Ctrl+Q. Under GtkBackend the app must exit. Under WinUIBackend nothing
   should happen, because no equivalent binding is installed; that asymmetry is
   the finding, not a bug in either backend.
4. Open an alert, press Escape, and confirm the dialog stays open. Then press
   one of its buttons and confirm the response arrives. Escape doing nothing and
   Escape dismissing while reporting no response are different failures, and
   only pressing a button afterwards separates them.
5. Reach a `CommandMenu` item using the keyboard alone, through the menu bar's
   own traversal, since no item can declare a shortcut. Record how many
   keystrokes it takes.
6. Keep the list of calls that do not compile in the app itself: `@FocusState`,
   `.focused($field)`, `.focusable()`,
   `.keyboardShortcut("s", modifiers: .command)`,
   `CommandGroup(replacing: .newItem) { ... }`. Each line that starts compiling
   is the progress report.
7. Repeat under the other backend.

Automated flow:

```zsh
zsh testapp/test.zsh P31 --both
```

The automated run verifies launch, render marker, final screenshot and the
visible baseline controls. Real focus traversal, Escape handling and Ctrl+Q
still require manual keyboard interaction.

## P32: Accessibility (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** The app calls
nothing that is missing. It exists to be inspected from outside.

SwiftCrossUI has no accessibility API. There is no `.accessibilityLabel`,
`.accessibilityHint`, `.accessibilityValue`, `.accessibilityAddTraits`,
`.accessibilityHidden`, `.accessibilityElement` or `.accessibilityIdentifier`,
and no backend protocol for any of them, so no backend can be asked to set one.
The nearest thing is `.help(_:)`, which goes through `BackendFeatures.Tooltips`
and sets a hover tooltip; UIKitBackend also assigns `accessibilityHint` from it,
and GTK and WinUI do not.

That does not mean the tree is empty. GTK exposes AT-SPI, WinUI exposes UI
Automation and AppKit exposes NSAccessibility, and each hands a widget a default
role and often a default name taken from its label. So the question here is not
whether accessibility exists but how much of it survives without an API: which
elements appear, which carry a usable name, and which are anonymous boxes. That
baseline is what any future labelling API gets measured against, and it has to
be recorded before the API exists or there is nothing to compare against.

Test steps:

1. Build a window holding a labelled `Button`, an icon-only `Button` with no
   text, a `TextField` with placeholder text, a `Toggle`, a `Slider`, a
   `ProgressView` and an `Image`.
2. On Linux, read the tree with Accerciser and record each element's role and
   name.
3. On Windows, read the same window with Accessibility Insights or
   `inspect.exe` and record each element's control type and Name.
4. Compare the two lists element by element. An element present on one platform
   and absent on the other is a backend gap; an element present on both with an
   empty name is the API gap this section is about, and the two want different
   fixes.
5. Apply `.help("...")` to the icon-only button and record whether the text
   reaches the accessibility tree, the tooltip only, or neither. Check both
   platforms; the code paths are not shared.
6. Drive the window with a screen reader -- Orca on Linux, Narrator on Windows
   -- and write down verbatim what it announces for the icon-only button. "Button"
   with no name is the expected result today; record the exact announcement
   rather than a summary of it.
7. Confirm the announced order matches the visual order. A layout container can
   reorder its children in the tree without changing what is drawn, and nothing
   on screen would show it.

Automated flow:

```zsh
zsh testapp/test.zsh P32 --both
```

The automated run verifies that the baseline controls render. Role/name
inspection still requires Accerciser on Linux and Accessibility Insights or
`inspect.exe` on Windows.

## P33: Missing Views (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** Covers the
SwiftUI views with no SwiftCrossUI equivalent at all, where ported code fails to
compile rather than rendering differently.

None of `Form`, `Section`, `Label(_:systemImage:)`, `Stepper`, `Gauge`,
`DisclosureGroup`, `LabeledContent`, `ColorPicker` or `Link` exists under
`Sources/SwiftCrossUI/Views`. `Section` is the one that matters most: in SwiftUI
it is less a view in its own right than the structuring element that `List`,
`Form`, `Picker` and `Menu` all accept, so its absence breaks call sites that do
not look like they are about sections. The others each cost one call site.

Current automated flow:

```zsh
zsh testapp/test.zsh P33 --both
```

The app renders a missing-view list and hand-written approximations for Stepper,
DisclosureGroup and LabeledContent. The intentionally missing SwiftUI call sites
remain documented in text rather than being kept as uncompilable code.

Test steps:

1. Show one instance of each missing view and record which compile. The app
   begins as a file that does not build, and the list of lines that had to be
   commented out is the measurement.
2. For `Section`, test all four containers separately -- `List`, `Form`,
   `Picker`, `Menu`. A `Section` that works in one and not the others is a
   different result from one that works nowhere.
3. Where a view can be approximated by hand -- a `Stepper` as two buttons and a
   label, `LabeledContent` as an `HStack` -- build the approximation beside the
   gap and record how many lines it takes and what it still fails to do:
   keyboard reachability, alignment with neighbouring rows, disabled state.
4. `Label(_:systemImage:)` needs a system image, and `Image(systemName:)` does
   not exist either (see P36). Record whether a text-only fallback is acceptable
   or whether the two gaps have to be closed together.
5. Compare each against the same code under AppKit.

## P34: Lazy Containers and Large Collections (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** Covers what
happens when a collection is larger than the window that shows it.

There is no `LazyVStack`, `LazyHStack`, `LazyVGrid`, `LazyHGrid` or `Grid`, and
no `ScrollViewReader` or `ScrollViewProxy`. `VStack` and `HStack` build every
child, and `ScrollView` scrolls whatever it was handed, so a collection inside a
`ScrollView` is fully realised: 10,000 rows means 10,000 widgets, whether or not
any of them is on screen. Nor is there a way to scroll to a particular row
programmatically, which is what `ScrollViewProxy.scrollTo` is for in SwiftUI.

"Feels slow" is not a finding. The app takes a row count on the command line and
prints numbers, so the result is a table rather than an impression.

Current automated flow:

```zsh
zsh testapp/test.zsh P34 --both
```

The loader currently runs with `--debug -rows 100` for a quick smoke pass. Larger
row counts should be run explicitly when measuring first-paint time and memory.

Test steps:

1. Run with 100, 1,000, 10,000 and 100,000 rows and record the time from launch
   to first paint at each. Four points are enough to see the shape: growth
   proportional to row count is full realisation, flat is laziness that has come
   from somewhere unexpected and should be located.
2. Record peak resident set size on the same runs. Time alone cannot separate
   "builds everything slowly" from "builds everything and keeps it", and the
   memory figure is what distinguishes them.
3. Measure scroll latency at 10,000 rows -- the time from a scroll event to the
   frame that reflects it -- and compare it against 100 rows. Eager building
   costs launch time; it does not necessarily cost scrolling, and conflating the
   two assigns the cost to the wrong cause.
4. Find the row count at which the app fails, and record how it fails: refusing
   to start, an allocation failure, a widget-count limit in X11 or WinUI, or a
   launch time long enough to be unusable. The remedies differ, so the mode
   matters as much as the number.
5. Write `ScrollViewReader { proxy in ... }` and record the compiler error, then
   jump to row 5,000 by whatever means the toolkit does offer and record what
   that costs.
6. Repeat under the other backend. GTK and WinUI have different widget-creation
   costs, so the two curves are expected to differ in slope, not only in offset.

## P35: State and Scene Composition (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** Covers the gaps
that stop a SwiftUI app's structure from being expressed, as distinct from its
appearance.

`@State`, `@Binding`, `@Environment` and `ObservableObject` all exist.
`@StateObject` and `@ObservedObject` do not, so a reference-type model has no
property wrapper to be observed through. Neither does `@SceneStorage`, nor
`Binding.constant(_:)`, and `.environmentObject(_:)` is not offered as an alias
for the environment modifier.

The scene side is more structural. `Scene` declares only `associatedtype Node`
-- there is no `var body: some Scene`, so a scene cannot be composed out of other
scenes the way a view is composed out of views. `SceneBuilder` provides
`buildBlock` only: no `buildIf`, no `buildOptional`, no `buildEither`. An `if`
inside `App.body` therefore does not compile, which rules out the ordinary
SwiftUI pattern of opening a window conditionally. `ViewBuilder` does have
`buildIf` and `buildEither`, but no `buildLimitedAvailability`, so `if #available`
does not work inside a view body either.

Current automated flow:

```zsh
zsh testapp/test.zsh P35 --both
```

The app exercises a simple `@State` counter/toggle and lists the state/scene APIs
that still cannot be represented. Scene composition remains a compile-time gap,
so this test is mainly a tracked baseline.

Test steps:

1. Declare a class conforming to `ObservableObject` with a `@Published`
   property and try to hold it with `@StateObject`, then with `@ObservedObject`.
   Record what compiles and, for anything that does, whether changing the
   published property redraws the view.
2. Write an `App` whose `body` contains `if showSecondWindow { WindowGroup ... }`
   and record the compiler error. The failure is in `SceneBuilder`, not in the
   window type, and the error text should be checked to say so -- an error that
   blames the wrong type sends the next person to the wrong file.
3. Write `if #available(macOS 14, *) { ... }` inside a view body and record that
   error too. It is a different missing requirement from step 2's, in a
   different builder, and the two should not be filed as one issue.
4. Pass `Binding.constant(true)` to a `Toggle` and record the error, then pass
   `Binding(get: { true }, set: { _ in })` and confirm it works. The second is
   the workaround, and its existence is what makes this a convenience gap rather
   than a functional one.
5. Set a value, close the window, reopen it, and record whether the value
   survives. With no `@SceneStorage` nothing restores it; confirm that is what
   actually happens rather than assuming it from the missing API.
6. Repeat under the other backend. These are compile-time gaps, so the results
   should be identical. A difference means something here is conditional on the
   backend, which is worth locating.

## P36: API-Shape Compatibility (Linux and Windows)

**Baseline app written and smoke-tested on WSLg and Windows.** Covers views that
exist but whose SwiftUI call sites do not compile. Every gap in this section is
invisible on a feature checklist, because the type is present and only the
initialiser is missing.

- `Picker` is `Picker(of: [Value], selection: Binding<Value?>)`. There is no
  label argument, no `@ViewBuilder` content and no `.tag`, and the selection
  must be `Optional`, so a picker over a non-optional `@State` needs a bridging
  binding.
- `Button` is `Button(_ label: String, action:)`. There is no trailing-closure
  label, so `Button { ... } label: { Image(...) }` cannot be written, and there
  is no `ButtonRole`, so `.destructive` cannot be expressed at all.
- `Text` takes a `String`. There is no `LocalizedStringKey`, therefore no
  markdown, and no `Text` + `Text` concatenation.
- `Image` takes a `URL` or an `ImageFormats.Image<RGBA>`. There is no
  `Image(systemName:)` and no bundle asset lookup, so every image in a ported
  app needs a file path.
- `List` requires `selection:` on every initialiser and constrains
  `Data.Index == Int`. There is no `Section`, no `.onDelete` and no
  `.swipeActions`.
- `TextField` has no `axis:`, no `prompt:` and no `value:format:`.
- Geometry is `Int`: `padding(_ amount: Int?)`, `cornerRadius(_ radius: Int)`,
  `HStack(spacing: Int?)`. SwiftUI uses `CGFloat` throughout, so `.padding(8.5)`
  in ported code is a compile error rather than a rounding difference.

Current automated flow:

```zsh
zsh testapp/test.zsh P36 --both
```

The app renders the SwiftCrossUI spelling that works today next to a text list of
SwiftUI-shaped calls that still fail to compile. This keeps the porting-cost
surface visible without breaking normal test builds.

Test steps:

1. Put each SwiftUI declaration above into the app verbatim and record the
   compiler error it produces. The error text is the deliverable; "does not
   compile" is not specific enough for anyone to act on.
2. Beside each, write the SwiftCrossUI form that does compile and gets nearest
   to the same result, and record the line-count difference. That difference is
   the porting cost, and it is the number this section exists to produce.
3. For `Picker`, hold a non-optional selection in `@State` and record what the
   bridging binding has to do when the picker's selection becomes `nil`. With no
   `.tag`, confirm what identity the selection is actually matched on -- the
   `Equatable` conformance of the value itself.
4. For the integer geometry, set a spacing of `8` and one of `9` and measure the
   rendered gap under each backend. If a backend scales by a display factor then
   the integer is not a pixel count and the rounding is happening somewhere
   else; record where, because a test that only checks `8 < 9` would pass either
   way.
5. Record whether `Image(systemName: "gear")` is a compile error or a runtime
   blank. A checklist cannot tell the two apart, and the silent blank is the
   worse of them.
6. Repeat under the other backend. Anything that compiles under one and not the
   other is a backend-conditional API, which is a separate finding from
   everything else in this section.

## P37: Window Level (Linux and Windows)

Run:

```zsh
zsh testapp/run.zsh P37                    # GtkBackend on Windows
./testapp/output/P37.exe                   # WinUIBackend on Windows
./testapp/output/P37                       # GtkBackend, in WSL
```

The one Pn that cannot be judged from a picture of its own window. Every other
app is assessed by what its window contains; this one is assessed by what is
*not* covering it. So the test needs a second window, and the interesting
outcome is the boring one, where nothing changed.

The app applies `.topmost()`, which is `.windowLevel(.floating)` under the name
the platform APIs use. Both go through `BackendFeatures.WindowLevels`, and a
backend that cannot honour a level falls back to `.normal` and logs it once
rather than crashing or going quiet.

The two platforms genuinely differ, and a tester who does not know that will
file the Linux result as a defect:

- **Windows** supports it on both backends. WinUIBackend uses
  `OverlappedPresenter.isAlwaysOnTop`; GtkBackend goes through
  `SetWindowPos(HWND_TOPMOST, SWP_NOACTIVATE)` on the `HWND` underneath the GTK
  window. `SWP_NOACTIVATE` matters: this must not steal focus, and taking the
  foreground is a separate thing Windows only allows the process already in
  front.
- **Linux does not.** GTK 4 removed `gtk_window_set_keep_above` and has no
  replacement, so the answer would have to come from the window manager. Under
  Wayland a client cannot raise itself above another application by design. X11
  has `_NET_WM_STATE_ABOVE`, but WSLg's window manager does not advertise it:
  measured 2026-08-26, its root `_NET_SUPPORTED` lists only
  `_NET_WM_MOVERESIZE`, `_NET_WM_STATE`, `_NET_WM_STATE_FULLSCREEN` and the two
  `MAXIMIZED` atoms. Re-check with `xprop -root _NET_SUPPORTED` before treating
  that as still true, and expect a different answer on a desktop Linux, where
  `_NET_WM_STATE_ABOVE` usually is implemented.

Test steps:

1. Launch P37 and read the `supported levels` line it prints in its window.
   On Windows it should list `automatic, normal, floating`; in WSL, only the
   first two. That line is the app telling you which of the next two steps
   applies.
2. Where floating is supported: click another application's window so that
   application takes focus, then look again. P37 must still be visible on top
   of it. Capture the desktop, not the window -- a window capture cannot show
   what is *not* covering it.
3. Where floating is unsupported: P37 goes behind, which is the correct result
   there. Confirm the app said so in step 1 rather than leaving you to guess.
4. Check the log for the fallback line. On a backend without floating,
   SwiftCrossUI should have logged `window level floating is not supported by
   ... using .normal` exactly once, not once per layout pass.
5. Close P37 and confirm nothing else on the desktop has been left pinned above
   its neighbours. A window level that outlives its window would cover whatever
   the user does next.

## P38: WebView (Linux and Windows)

Run:

```zsh
zsh testapp/test.zsh P38 --both
```

Covered issues:

- WinUI WebView async / render delay behaviour.
- GtkBackend WebView coverage and graceful fallback behaviour.

Test steps:

1. Launch P38 on WSLg first, then Windows.
2. Confirm the app window appears and does not hang before the final screenshot.
3. Check whether the WebView area renders usable content, a deliberate fallback,
   or a blank area.
4. Check the log for navigation or async completion messages.
5. On Windows, keep the run open for the default 30 seconds and confirm the app
   remains responsive while the WebView is loading.

Expected results:

- The test should not crash or block the loader.
- If the initial screenshot is blank but the final screenshot is visible, record
  it as startup/render timing, not as a UI failure.
- If Windows never reaches the final screenshot or cannot close cleanly, record
  it as the WinUI async WebView issue.

## P39: Visual Effects (Linux and Windows)

Run:

```zsh
zsh testapp/test.zsh P39 --both
```

Covered issues:

- Visual-effect rendering differences across GtkBackend and WinUIBackend.
- Unexpected diagnostic noise or silent no-op effects.

Test steps:

1. Launch P39 on WSLg first, then Windows.
2. Confirm all effect samples are visible in the final screenshot.
3. Use image measurement for color/visibility checks when judging a rendering
   issue; do not rely only on visual inspection.
4. Compare WSLg and Windows captures for obvious missing effects, clipped
   content, or theme-driven contrast problems.

Expected results:

- The app should render visible samples on both platforms.
- Backend-specific theme differences are acceptable; missing or blank samples
  should be recorded as issues.

## P40: Geometric Effects (Linux and Windows)

Run:

```zsh
zsh testapp/test.zsh P40 --both
```

Covered issues:

- Geometric effect rendering.
- Hotpink fallback / incorrect geometry detection.

Test steps:

1. Launch P40 on WSLg first, then Windows.
2. Confirm transformed shapes are visible in the final screenshot.
3. Measure the final screenshot with PIL before claiming the hotpink fallback is
   absent or fixed.
4. Measure color-component bounding boxes for the orange/blue test tiles. A
   pass requires scale, offset, rotation and shear samples to differ from the
   control in the expected direction; zero hotpink alone is not sufficient.
5. Record the screenshot dimensions, non-black pixel ratio, and exact/near
   hotpink pixel count.
6. Record the platform theme/background separately. WSLg may default to light
   Adwaita while WinUI follows the Windows theme; this is not geometry failure.

Expected results:

- The app should produce a visible non-black capture on both platforms.
- Exact hotpink pixels should be zero unless the app intentionally displays the
  fallback color for a test case.
- The transformed samples should not all have the same bounding box as the
  control tile.

## P41: Date Picker Styles (Linux and Windows)

Run:

```zsh
zsh testapp/test.zsh P41 --both
```

Covered issues:

- WinUI `.graphical` DatePicker blank sliver / binding behaviour.
- Cross-backend DatePicker style fallback behaviour.

Test steps:

1. Launch P41 on WSLg first, then Windows.
2. Confirm every DatePicker section occupies visible space.
3. On Windows, inspect `.graphical` specifically and confirm it is not rendered
   as a blank sliver.
4. Change the date where possible and confirm the displayed binding value
   updates.
5. Record style-specific fallback messages from the log.

Expected results:

- The final screenshot should show visible DatePicker content on both
  platforms.
- If `.graphical` is blank or updates the wrong binding value on Windows, record
  it as the WinUI DatePicker issue.

## Test Record Template

Use this format after each test run:

```text
Date:
Commit:
OS:
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
