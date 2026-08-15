# WinUI Test Plan: P0-P6

This document describes the manual UI test steps for the apps in `testapp`. The goal is to quickly reproduce and verify WinUIBackend-related issues.

## Preparation

1. Go to the project root:

   ```powershell
   cd C:\Users\lowei\proj\swift-cross-ui
   ```

2. Compile the test apps:

   ```powershell
   sh testapp/compile.zsh
   ```

3. Go to the output directory:

   ```powershell
   cd testapp\output
   ```

4. Confirm that the runtime resource exists:

   ```powershell
   Test-Path .\swift-winui_CWinAppSDK.resources\Microsoft.WindowsAppRuntime.Bootstrap.dll
   ```

   Expected result: `True`.

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

```powershell
.\P0.exe
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

```powershell
.\P1.exe
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

```powershell
.\P2.exe
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

```powershell
.\P3.exe
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

```powershell
.\P4.exe
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

```powershell
.\P5.exe
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

```sh
./P7
```

Covered issues:

- #476 (Open): The List control starts with the first item already selected on the GTK backend
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

- Nothing is selected at launch. A highlighted first row is #476.
- The detail pane is visible and does not collapse to nothing, and the division does not change when unrelated text changes. Either is #556.

## P8: Scroll Views (Linux)

Run:

```sh
./P8
```

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

```sh
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

```sh
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
6. Press Ctrl-Q (Cmd-Q on macOS), to verify #478.

Expected results:

- A transparent overlay does not block clicks. If the covered button only works once the overlay is removed, that is #454.
- Ctrl-Q quits the app. If the window stays open, that is #478.

## P15: Colour Scheme And Window Height (Linux)

Run:

```sh
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

```sh
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

```sh
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

```sh
zsh testapp/compile.zsh P6
./testapp/output/P6.exe
```

On macOS the output binary name may be `P6` instead of `P6.exe`:

```sh
zsh testapp/compile.zsh P6
./testapp/output/P6
./testapp/output/P6 -core
./testapp/output/P6 --debug
./testapp/output/P6 --frame-drop
./testapp/test_P6.sh /path/to/video.webm
./testapp/test_P6.sh -rss --debug /path/to/video.webm
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
`test_P6.sh -win` and `P6-test.sh` both wrap that combination;
`P6-test.sh [file-pattern]` is the shorter form.
`compile.zsh` builds debug by default and accepts `BUILD_CONFIG=release` for an
optimised build.

`test_P6.sh` prints its usage when no arguments are provided and otherwise
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
20. Start playback from `test_P6.sh`, obtain the ffplay PID from `p6-debug-events.log`, and press Ctrl-C in that terminal. Confirm in the log file that P6 received the signal, waited for ffplay to exit, and left no matching ffplay process running. Confirm that P6 diagnostic lines were not printed in the terminal. Because the script no longer uses `exec`, its observed exit status is shell-dependent when both zsh and P6 receive Ctrl-C.
21. Put a recognizable old line in `p6-debug-events-rss.log`, then relaunch through `test_P6.sh -rss`, play and seek for at least one minute, and close P6 or press Ctrl-C. Confirm that the old line was cleared and the file contains only the new run's start line, one RSS sample per second, final sample count, peak RSS in KiB, and P6 exit status. Confirm that the terminal contains no RSS diagnostic lines and `p6-debug-events.log` remains reserved for P6 diagnostics.

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
- `test_P6.sh -rss` clears `p6-debug-events-rss.log` at launch, then measures only the P6 process resident memory once per second and records samples and peak RSS there; FFmpeg, ffplay, and zstd child RSS are not included.
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
- 2026-08-12: GPU selection flags (`-amd`, `-nvidia`, `-both-gpu`, `-no-gpu`; `-both-gpu` decodes on the Nvidia card and presents on the display's adapter, `-no-gpu` presents through Microsoft's Basic Render Driver as a CPU baseline) plus `testapp/gpu-matrix.sh`, which runs every mode and reports dropped frames/sec and stage timings. This machine has an AMD Radeon iGPU as adapter 0 and an Nvidia RTX 4060 as adapter 1. Measured over 25 s per mode:

  | Mode | 1080p read | 1080p dropped/s | 4K read | 4K dropped/s |
  |---|---|---|---|---|
  | default | 0-17 ms | 0.0 | 36-40 ms | 0.0 |
  | `-amd` | 1-14 ms | 0.0 | 42-47 ms | 0.0 |
  | `-nvidia` | 3-12 ms | 0.0 | 38-41 ms | 0.0 |
  | `-both-gpu` | 7-16 ms | 0.0 | 33-47 ms | 0.0 |
  | `-no-gpu` (WARP) | 2-3 ms | 0.0 | 43-51 ms | 0.0 |

  Presenting measured 0-6 ms in every mode at every resolution and frame rate. **The GPU choice makes no measurable difference, and neither does using no GPU at all.** Full results, including 60 FPS and the exact ffmpeg arguments per run, are in `testapp/P6_findings/gpu-modes.csv` (written by `gpu-matrix.sh`); see `testapp/P6_findings/README.md`.
- 2026-08-12: **the decoder is not the bottleneck either.** Running the same filter chain standalone (`ffmpeg ... -f rawvideo -pix_fmt rgba -y NUL`) produced 4K60 frames at about 123 fps, roughly 2.1x realtime, while P6 consumed 1.1-2.3 fps. The same 33 MB frame reads in 58 ms at 4K30 and ten times slower at 4K60, which points at CPU contention: ffmpeg saturates the machine producing frames nothing is waiting for. Pacing the decoder to the playback rate (`-re` / `-readrate`) is the next thing to try.
- 2026-08-12: **the real ceiling was publishing, not the pipe.** After the pipe fix every configuration still sat at 7-8 frames/sec regardless of resolution or frame rate, which is the signature of a fixed per-frame cost rather than a bandwidth limit. Timing the main-actor hop showed it: `acceptFrame` sets `currentTime`, `seekPosition` and `status`, all `@Published`, so **every frame rebuilt the view graph and ran a WinUI layout pass, measured at 97 ms per frame** against budgets of 16-33 ms. The video never goes through the view graph, so the timeline and status text are now published at 2 Hz instead of per frame. Results, 20 s per configuration:

  | Configuration | Before | After |
  |---|---|---|
  | 1080p @ 30 | 7.8 fps | **26.6-29.2 fps**, 0.7-2.9 dropped/s |
  | 1080p @ 60 | 7.7 fps | **49.5-50.8 fps**, 7.9-10.1 dropped/s |
  | 4K @ 30 | 6.9 fps | **27.5-28.2 fps**, 1.2-2.1 dropped/s |
  | 4K @ 60 | 1.1 fps | 0.9-25.7 fps, 33-57 dropped/s |

  A single state update costing ~100 ms is a WinUIBackend finding in its own right and is worth investigating separately.
- 2026-08-12: two corrections to earlier entries. The dropped-frame figures reported as 0.0 were a bug in `gpu-matrix.sh`, which summed the wrong awk field; drops were always in the tens per second at 4K. And pacing the decoder with ffmpeg's `-readrate` (the `-pace` flag) made no measurable difference, so the CPU-contention theory was wrong.
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
