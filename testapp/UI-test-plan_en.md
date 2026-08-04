# WinUI Test Plan: P0-P6

This document describes the manual UI test steps for the apps in `testapp`. The goal is to quickly reproduce and verify WinUIBackend-related issues.

## Preparation

1. Go to the project root:

   ```powershell
   cd C:\Users\lowei\proj\swift-cross-ui
   ```

2. Compile the test apps:

   ```powershell
   sh testapp/compile.sh
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

## P6: Zstd Stream Player

Build and run:

```sh
zsh testapp/compile.sh P6
./testapp/output/P6.exe
```

On macOS the output binary name may be `P6` instead of `P6.exe`:

```sh
zsh testapp/compile.sh P6
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
- `testapp/.compile-work/` and `testapp/output/` are scratch: `compile.sh` copies
  the selected source to `.compile-work/TestApps/Sources/<name>/main.swift` and
  generates its `Package.swift`, so neither directory belongs in a commit.

Test steps:

1. Launch `P6.exe` and click `Choose file`.
2. Select `storybook-1min-4k60.mp4`, a WebM input, or `storybook-1min-4k60.y4m.zst`.
3. Confirm that the first frame appears and the selectable progress text uses the `Current: 01:17 / 04:02 (32%)` format when duration is available. Drag across the text and copy it to confirm text selection works.
4. Click `Show resolution`; confirm that its button background changes to the active state and a separate bottom line reports input resolution, output resolution, and the 960x540 viewport. Click it again and confirm that the bottom line disappears and the button returns to its inactive background.
5. Click `Play`; confirm that video playback starts and that audio starts too for inputs with an audio track when `ffplay` is available. Confirm that the log reports `playback clock started <time>` with an interpolated media timestamp such as `00:12`.
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

RSS stress record:

- `p6-debug-events-rss-speed3x,fps60,4k_3840x2160_sound_on_frame_drop.log` records P6 at 3x speed, 60 FPS, 3840x2160 output, Sound On, and Frame Drop enabled.
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
