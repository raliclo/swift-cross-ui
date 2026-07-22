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
```

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

Test steps:

1. Launch `P6.exe` and click `Choose file`.
2. Select `storybook-1min-4k60.mp4` or `storybook-1min-4k60.y4m.zst`.
3. Confirm that the first frame appears and the duration is shown when the sibling MP4 exists.
4. Click `Show resolution`; confirm that the status line reports input resolution, output resolution, and the 960x540 viewport.
5. Click `Play`; confirm that video playback starts and that audio starts too for inputs with an audio track when `ffplay` is available.
6. Click `Sound on` / `Sound off`; confirm that audio can be toggled without disrupting video playback.
7. Click `Stop`; confirm that Stop preserves the current position and Play resumes it.
8. Drag the timeline slider to a specific time and confirm that `Seek target` updates.
9. Click `Seek`; confirm that the displayed frame/time jumps to the slider target, and that playback continues from that target when playback was already running.
10. Click `-5s` and `+5s`; confirm that the displayed frame and time move by five seconds and clamp at zero/end.
11. Select `1x`, `2x`, and `3x`; confirm that selecting a speed does not switch focus to another terminal and does not immediately restart the decoder. Press Play or Seek to apply the new speed.
12. Select `30`, `45`, and `60` FPS; confirm that selecting FPS does not switch focus to another terminal and does not immediately restart the decoder. Press Play or Seek to apply the new presentation rate.
13. Select `Preview 960x540`, `1080p 1920x1080`, and `4K 3840x2160`; confirm that selecting resolution does not switch focus to another terminal and does not immediately restart the decoder. Press Play or Seek to apply the new output mode.
14. On macOS, select `4K 3840x2160` and `60` FPS; confirm that the preview remains 960x540 while logs report `metal frame ... 3840x2160`.
15. Close the window during playback and confirm that FFmpeg/Zstd/FFplay child processes exit.

Expected results:

- MP4, Y4M, and Y4M.ZST inputs decode at the selected output resolution.
- Direct inputs with audio tracks can play sound through `ffplay`; Y4M / `.zst` video-only paths should not crash.
- The timeline slider can quickly choose a target time, and `Seek` displays or plays from that target.
- Selecting speed, FPS, or output resolution should not switch focus to another terminal, steal focus, or immediately restart the decoder.
- The visible viewport remains 960x540 and scales the decoded frame down for operation in a normal test window.
- macOS renders decoded RGBA frames through a persistent Metal texture instead of rebuilding a SwiftCrossUI image for every frame.
- Playback controls remain responsive while decoding runs off the UI thread.
- Repeated static frames do not force redundant image uploads.
- Missing tools or malformed input produce an error in the status line instead of crashing.

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
