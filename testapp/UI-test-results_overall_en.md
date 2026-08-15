# WinUI Manual Test Results

## 2026-07-12

### P2: Controls And Styling

- #449 Picker: When opening the `Flavor` picker, WinUI/Composition console diagnostic logs such as `BVI-*`, `rcBackdropLocal`, and `CachedNewBlur` were previously observed. WinUIBackend has been changed to override `ComboBoxDropDownBackground` with a solid brush; retest is needed to confirm whether the console noise is gone.
- #449 Picker: Previously, the dropdown disappeared immediately and another option could not be selected. The WinUI ComboBox has been adjusted so items are not updated when options are unchanged, and selection is not reset when the selected index is unchanged; retest is needed.
- #471 TextEditor: Previously, typing could drop characters; for example, quickly entering `12345` might show only `1235`. The one-shot `shouldBlockNextChangedSignal` blocking logic in TextEditor has been removed, and the implementation now tracks the last synchronized text to avoid same-value binding writes; retest is needed.
- #390 (Fixed): Disabled and enabled buttons are currently reported as having no visual-difference issue.
- #401 (Fixed): Window resizing / full-screen button behavior is currently reported as no issue.

### P3: Layout And Clipping

- #160: Screenshots show that NavigationSplitView columns may be clipped or unstable at initial launch or at specific window sizes. Continue recording the difference before and after resize / force state update.
- #389: Screenshots show that an oversized image may still exceed the expected frame. Record this as image clipping behavior and fix later.

### P4: WinUI Native And Callback Stress

- #156: Screenshots show that the native WinUI banner and the border modified through `TextField.inspect` are visible. The native API escape hatch appears to work initially.
- #190: Screenshots show that row buttons and the scroll view appear correctly. Still need to click each `Run N`, increase/decrease rows, and repeatedly force updates to confirm callbacks do not get mixed up.
- Row-size increase delay: Currently judged to be related to WinUIBackend. Each P4 row creates multiple native widgets such as Button/Text/Spacer. When row count increases, SwiftCrossUI `ForEach` reuses old rows and appends new rows, but ScrollView/VStack still lays out all rows. WinUIBackend previously rebuilt the button content `TextBlock` on every `updateButton`, which amplified delay during large row updates. It has first been changed so `CustomButton` reuses the label TextBlock; retest is needed to compare whether the delay decreases.

## 2026-08-16

### P7: Lists And Split Views

- #476 (Open): Windows `P7.exe` starts with no selected plain-list row, and the status line shows `Selection: none` as expected.
- #476 (Open): WSLg/GTK `P7` reproduces the issue at launch: the `Apple` row is already selected even though the selection binding starts as `nil`, and the status line shows `Selection: Apple`.
- #476 (Open): Running WSLg/GTK with `GTK_THEME=Adwaita:dark ./testapp/output/P7` still reproduces the initial `Apple` selection, so the selection issue is not caused only by the default light theme.
- #476: Clicking `Cherry` updates the status to `Selection: Cherry` and highlights `Cherry` in the plain List on both Windows and WSLg/GTK. This part of the selection binding works correctly after user interaction.
- #476: Test 4 works correctly. Clicking `Clear selection` clears the selected row state as expected.
- #386 / GTK theme observation: WSLg/GTK uses native GTK theme metrics and colors, so its background, text contrast, spacing, and selected-row styling differ from WinUI. Under `GTK_THEME=Adwaita:dark`, the app background becomes darker, but some text contrast remains poor in the captured screenshot and should be considered when validating GTK theme behavior.
- #556 (Open): The `NavigationSplitView` region is visible on both Windows and WSLg/GTK, but the pane aspect / split ratio differs between backends. This matches the reported GTK NavigationSplitView sizing issue, so #556 remains open even though the detail pane does not collapse.
- #556: After clicking `Cherry` in the plain List, the NavigationSplitView detail pane still shows `No sidebar selection`. This appears expected for the current P7 test because the plain List selection is separate from the NavigationSplitView sidebar selection, but it is worth keeping in mind when reading the comparison screenshots.
- #556: Step 7 is functionally stable. After clicking `Add a fruit's worth of text`, the longer text above the split view appears and the split view does not jump or collapse, but the Windows and WSLg/GTK pane ratios still do not match.
- #556: Step 8 is functionally stable. After resizing the windows, including a much wider horizontal resize, the detail pane remains visible on both Windows and WSLg/GTK. However, the WSLg/GTK split-view aspect / pane ratio remains visibly different from Windows, so this still belongs to #556.
- #556 / Windows Light mode: The third pane on the right does not show the expected vertical divider line (`|`) in Windows Light mode, while the WSLg/GTK comparison screenshot shows a visible pane boundary. Record this as a Windows/GTK visual parity issue for the split-view detail pane.
- WSL/Windows GUI comparison: The Windows `P7.exe` window and the WSLg/GTK `P7` window should be equal in size for the same test scenario, but the screenshot comparison shows a visible size difference. This needs investigation before treating cross-backend layout screenshots as directly comparable; confirm whether the difference comes from requested content size, backend window-sizing semantics, DPI scaling, window decorations, or WSLg compositor behavior.
