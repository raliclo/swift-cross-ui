# queue

## 2026-10-05 code review: gaps against the five-backend rule

Read from the source, not from this file: every `BackendFeatures` protocol
(typealiases such as `Controls`, `PassiveViews` and `FullAppBackend` expanded,
protocol inheritance followed, comments stripped) against each backend's
declared conformances; `fatalError` / "unsupported" paths in the five shipped
backends; the 113 TODO/FIXME comments in SwiftCrossUI and those backends, each
checked against the code beside it. Items marked "verify" were not confirmed
by running anything. Not gaps: `BaseStubs` (a scaffold for writing a backend),
`AttachedMenus` vs `PopoverMenus` (two ways to do menus, either one), and
UIKit's three slider `fatalError`s (the `#else` branch is tvOS only).

這次 review 以原始碼為準：每個 `BackendFeatures` 協定(展開 `Controls`、`PassiveViews`、`FullAppBackend`
等型別別名，跟隨協定繼承，去掉註解)對照每個 backend 宣告的 conformance;五個已發布 backend 中的
`fatalError` 與「不支援」路徑；SwiftCrossUI 與這些 backend 的 113 個 TODO/FIXME,逐一對照旁邊的程式碼。
標為 "verify" 的沒有實際跑過。不算缺口的：`BaseStubs`(寫 backend 用的鷹架)、`AttachedMenus` 與
`PopoverMenus`(選單的兩種做法，擇一即可)、UIKit 的三個滑桿 `fatalError`(`#else` 是 tvOS)。

### On this Mac

- [ ] **Android: `BackendFeatures.IncomingURLs` is not implemented.** It is part
  of `FullAppBackend`; GTK, WinUI, AppKit and UIKit have it, Android does not
  declare it, and `AndroidBackend.swift:609` still carries upstream's commented
  "Handle incoming URLs". An app opened by a link on Android never hears about it.
- [ ] **File dialogs never filter by type, on any platform.** The core never sets
  it: `PresentSingleFileOpenDialogAction.swift:54`, `PresentMultipleFileOpenDialogAction.swift:73`
  and `PresentFileSaveDialogAction.swift:49` all pass `allowedContentTypes: []`,
  and `DocumentGroup` does not hand its `FileDocument`'s readable types to the
  open dialog. Backends: Android maps them to MIME types; UIKit has `TODO(#235)`
  (`UIKitBackend+FilePicker.swift:37`); AppKit ignores them in both panels
  (`AppKitBackend.swift:1764`, `:1803`); GTK and WinUI never read the field.
  Needs a public API first, then the three backends.
- [ ] **AppKit: `Slider` ignores `decimalPlaces`** (`AppKitBackend.swift:978`,
  "TODO: Implement decimalPlaces"). The other four read it.
- [ ] **`Picker.inspect` is commented out on all five backends**
  ("Repair Picker.inspect implementations post PickerStyle refactor" in each
  `InspectionModifiers.swift`; Android has none at all). Every other control
  has its `.inspect`.
- [ ] **UIKit: `preferredColorScheme` on the window -- verify.** `updateWindow`
  (`UIKitBackend+Window.swift:283`) only paints the background from
  `colorScheme` and carries "TODO: Support preferredColorScheme"; views set
  `overrideUserInterfaceStyle` one by one (Symbols, Passive), system controls in
  between may not follow. P15 on iOS is the check.
- [ ] **Android TODOs to verify, each a possible gap:** navigation titles
  (`AndroidBackend.swift:460`), orientation and configuration changes (`:580`),
  live system light/dark changes (`:804`), per-window environment changes
  (`:822`), more than one `createWindow` (`:430`), sheet background and detents
  (`AndroidBackend+Sheets.swift:51`), `dismantleAndroidView`
  (`AndroidViewRepresentable.swift:53`). UIKit: sheet detents before iOS 16
  (`UIKitBackend+Sheet.swift:171`).
- [ ] **The csv2 rule (CLAUDE.md) in the tools that still use Python's csv:**
  `testapp/test_support/ios_aim_check.py`, `Scripts/fill_matrix_from_sweep.py`,
  `Scripts/check_action_files.sh`, `Scripts/check_action_file_fields.sh`,
  `Scripts/check_mistakes_numbering.sh`, `Scripts/check_results_columns.sh`.

### Windows side (GTK and WinUI)

- [ ] **Five optional features declared by neither GTK nor WinUI:** `ContextMenus`,
  `Cursors`, `KeyEvents`, `ScrollGestures`, `WidgetSnapshots` (AppKit, UIKit and
  Android have all five). `Mesh3DViews` is the sixth, already its own item above.
- [ ] **Picker styles:** GTK lacks `.wheel` (`supportedPickerStyles`,
  `GtkBackend.swift:233`); WinUI lacks `.segmented` and `.wheel`
  (`WinUIBackend.swift:209`). An app asking for them is downgraded -- the path
  CLAUDE.md rules out on shipped backends. AppKit, UIKit and Android have all four.
- [ ] **WinUI parity TODOs:** date picker ignores the foreground colour
  (`WinUIBackend.swift:3202`), font design / monospace (`:1540`), picker font
  (`:2033`), no notification when the window's scale factor changes (`:1151`),
  fullscreen not detected (`:726`). GTK: button label colour from the environment
  (`GtkBackend+Button.swift:17`).
## 2026-10-05 M10 follow-up: what SoftPCB's tab 9 needs from Mesh3DView

SoftPCB-UI draws its board with its own Metal renderer because Mesh3DView drew
indexed triangles only. The user's decision: Apple and Android first, Windows and
WSL to the Windows side. Android was queued here until the 6.4.0 Android
toolchain was installed (2026-10-05); it is done below.

- [x] **Apple (AppKit + UIKit, one shared `SwiftCrossUIMetal`).** `Mesh3DPrimitive`
  (`.triangles` indexed; `.lines` and `.points(size:)` drawn straight from the
  vertex array, so no index-width limit), `Mesh3D.lit`, `Mesh3D.depthTested`,
  `Mesh3DCamera.Projection.orthographic(height:)` (shared matrix, both depth
  ranges unit-tested), `.glb` modes 0/1 and an orthographic camera. Fixed on the
  way: a mesh with no triangle shifted every later mesh onto its predecessor's
  transform. Verified with P76 on macOS and on the iOS simulator, each with
  `P76-projection.csv`; `Mesh3DTests` added.
- [x] **iOS builds without Swift Bundler by default.** `compile.zsh -ios` runs
  `xcodebuild -scheme <Pn>` and wraps the executable in
  `iosContainer/appTemplate.app` (name, identifier `dev.swiftcrossui.testapp.<Pn>`,
  ad-hoc signature); the bundler is the fallback when that fails. P76 built,
  installed directly with `simctl install`, and replayed through `test.zsh --ios`.
  **Full sweep 2026-10-05: all 101 iOS action files pass with no bundler on the
  machine** (92 on the first pass; the other 9 failed in 4 s because an up-to-date
  xcodebuild did not relink, so the freshness check rejected an old executable --
  compile.zsh now removes it first, and those 9 then passed). No Pn fell back.
- [x] **Android: the GLES path for the same options.** DONE 2026-10-05, built with
  the swift.org 6.4.0 toolchain and the 6.4.0 Android SDK, NDK r30, AVD
  `swift-cross-ui-api36b`.
  - B: 32-bit indices when the context is GLES 3 or has `OES_element_index_uint`
    (`IntBuffer`, `GL_UNSIGNED_INT`); otherwise `ShortBuffer` while every index fits,
    and a one-time warning past 65,535. The old `Int16.max` refusal is gone.
  - D: lines and points with `glDrawArrays`, `gl_PointSize` from a uniform; both
    unlit. `lit` and `depthTested` per mesh (`GL_ALWAYS` + depth mask off), the
    mask restored before `glClear`. Every mesh now gets a draw entry, so the
    matrices stay aligned with it.
  - Accepted: P76 shows all six claims on the emulator and on the iOS simulator;
    P77 (new: 1,002,001 vertices, 2,000,000 triangles, largest index 1,002,000)
    shows one gradient with no hole and no streak on Android, iOS and macOS.
- [x] **Render time in microseconds, off by default.** `Mesh3DScene.measuresRenderTime`
  and `Mesh3DFrameInfo.renderMicros` (nil when not measured): from the start of
  the frame until the GPU finishes it -- `waitUntilCompleted` on Metal, `glFinish`
  on GLES. P72, P76 and P77 have a button for it. Measured once each (not a
  benchmark): macOS P72 329, P76 4437, P77 12312 us; Android emulator P76 3929,
  P77 40144 us. Showing a reading redraws the view; the apps skip the frame that
  redraw produces, so the loop stops (CPU 0% against 10.6-13.7% without the guard).
- [x] **`P72-stop-and-check.csv` on Android missed every target since the api36b
  AVD.** That AVD's renderer string is three lines, not five, so the controls sit
  about 62 pt higher; "Stop" landed on Snapshot and the readout stayed at
  "frames at the stop: -1" with nothing failing. Re-measured: stop 190, check 193.
- [ ] **GTK and WinUI: no `Mesh3DViews` at all yet** -- Windows side.
- [x] **Skip the per-commit geometry comparison.** Not needed, measured
  2026-10-05: `Array ==` returns at once when both arrays share storage (0.003 ms
  for 2,000,000 vertices, against 2.2 ms for equal contents in another buffer,
  `-O`). A scene built from stored arrays is already O(1) per commit; a revision
  token would only add a way to draw stale geometry by forgetting to bump it.
  Documented on `Mesh3D` as "keep the arrays; do not rebuild them per update".

## 2026-10-01 open after the UIScene change (8272b7a2) -- in this order

1-4 first, in the order 4, 1, 2, 3 (the user's choice); the iPad plan after all four.

- [x] **4. Why the iOS executable says `sdk 15.0`.** DONE 2026-10-01. The Swift
  driver's link job hands clang `--sysroot <SDK>`; clang reads an SDK's version
  only from `-isysroot` or $SDKROOT, so it fell back to the deployment target:
  the logged link line re-run with `-###` gave `-platform_version ios-simulator
  15.0.0 15.0.0`, and `15.0.0 27.0` with -isysroot. Not Homebrew's CC (an Apple
  clang build gave the same), not swift-bundler's metadata object, not any link
  flag (each removed in turn). Fixed at the source:
  `testapp/iosContainer/link-sdk.xcconfig` adds `-Xclang-linker -isysroot`
  through XCODE_XCCONFIG_FILE, and the link now writes sdk 27.0 itself. The
  `vtool` rewrite is gone; compile.zsh only CHECKS the field and stops the build
  if it is wrong (shown to fail on an sdk-15 copy).
- [x] **1. Re-aim every iOS action file.** DONE 2026-10-01. Apps now run at
  native size (440x956 points instead of a zoomed 428x926), so layouts moved.
  Swept all 84 files, read each capture against its file's assertion, re-aimed
  the misses (P2 P3 P13 P17 P21 ×2 P22 P23 ×5 P33 P43 P44 P45 ×2 P46 P74 P75
  save) and replayed every re-aimed file until its capture showed the
  assertion. Two tools came out of it: `testapp/test_support/ios_aim_check.py`
  checks each positioned row against the accessibility tree, and the iOS runner
  takes a `dumptree` row that prints the tree mid-file, for targets that only
  sit where they do after earlier rows (P17's More height was mis-aimed from a
  capture taken after the closing scroll). P75 deletes last run's saved file on
  launch so the save file is repeatable.
- [x] **2. Write the missing action files.** iOS 14: P47 P48 P49 P51 P52 P58
  P59 P61 P62 P63 P64 P66 P68 P70 (captured 2026-09-30, but at the zoomed size
  -- re-measure). Android 20: P15-DARK P17-DOE P47 P48 P49 P51 P52 P59 P60 P61
  P62 P63 P64 P66 P67 P68 P69 P70 P73 (+ P6-v2, GTK-only, never).
  - [x] iOS: 16 files written 2026-10-01, measured from the native-size tree and
    each replayed and read. Two defects found and fixed on the way:
    DocumentGroup's binding never redrew its window (P62 read (empty) while
    its log said AA; macOS hid it because opening a second document redrew
    window 1), and a sheet whose content was wider than the window was laid
    out at that width and centred, cutting both ends of every line (P49).
  - [x] Android: all 20 written 2026-10-01/02, measured from uiautomator dumps and
    replayed (sweep_android 19/19 launched; each capture read). On the way:
    the Android host SDK (Xcode 27 Foundation interfaces the snapshot toolchain
    cannot read) broke every Android build; test_android refused P15-DARK and
    P17-DOE, and a hyphen made an invalid application id; an app that crashed at
    launch still exited 0 and photographed the app behind it; P63 read global
    x=0 y=0 (pending LayoutParams, pixels); a default popover had no panel; a
    popover wider than the window ran off it (Android and iOS); taps aimed into a
    sheet or popover reached the activity behind (P60); main-queue work waited
    up to 50 ms for the tickler. All fixed.
  - [x] **Re-aim the Android action files.** DONE 2026-10-02. Every file's taps
    checked against a uiautomator dump (`ios_aim_check.py` reads .xml now), 16
    re-aimed, and a full sweep -- 98/98 launched, no crash, every replay
    finished -- read capture by capture against each file's assertion. Fixed on
    the way: launch focus went to the first text field (keyboard over P2 P15
    P21 P36, and P21's buttons scrolled away on a relayout) -- ShortcutHostLayout
    now takes the default focus; P72's long-press menu had been unreachable since
    the scroll-gesture container took every touch -- it now takes a touch only
    past the slop and hands a still press to the long-click ancestor; the final
    capture now waits for the replay to finish; P75 reveal writes a fresh name
    when the old file belongs to an earlier install.
  - [x] **Android per-frame update cost.** Re-measured 2026-10-04 on the new AVD
    after the reboot: P64 54-56 Hz (median gap 16.7 ms, max 117-150 ms), P66
    16-22 samples in 0.6 s (iOS 31). The earlier 37 Hz / 7 samples were the
    stuck emulator eating 7 cores. Findings, all measured, nothing changed yet:
    - Not the update pipeline: no merged or throttled updates during P66's
      animation; each SwiftCrossUI update takes 4-10 ms and runs every frame.
    - Main thread is busy ~20 ms per frame during the animation (P66's 8 ms
      sampler runs every 20-30 ms then, every 8 ms after), and values sometimes
      advance two frames at once -- dropped frames.
    - A ~100 ms main-thread stall at the animation's start (sampler t=76 ->
      178), the same shape as P64's 117-150 ms max gap; ART's JIT thread is
      6-10 % of the process then, so first-run JIT/class loading is the lead.
    - simpleperf: libart 28 %, libswiftCore 18 %. The top symbol was
      `art::mirror::Class::FindClassMethod` (8.9 %): swift-java's
      `javaMethodLookup` runs GetObjectClass + GetMethodID on EVERY call (from
      AndroidBackend.setSize -> setLayoutParams among others). A method-ID cache
      prototyped in the checkout removed it but cut main-thread CPU only ~5 %
      (2.38 s -> 2.26 s over 6 s) and did not move P66, so it was reverted; a
      swift-java fork is not justified by that alone.
    FIXED 2026-10-04 (second pass, counting calls rather than their cost):
    `AndroidBackend.size(of:whenDisplayedIn:)` built a new Java TextView and a
    full TextStyle for every text measurement (50.5 % of the main thread),
    `getTextStyle` rebuilt Typeface/classes every call (19.6 %), and 94-96 % of
    setPosition/setSize calls and ~half of setText calls changed nothing yet
    each requested an Android layout. Now: measurements and text styles are
    cached by key, unchanged positions/sizes/text are skipped. P66 16-22 ->
    24-28 samples (iOS 31); P64 54-56 -> 57-58 Hz, max gap 117-167 -> 67-100 ms.
    Full Android sweep 98/98, captures compared with the run before.
    PARITY 2026-10-04 (third pass): the remaining read-back checks were
    themselves JNI calls (updateTextView 27 %, setPosition 22 %), and
    swift-java's per-call method lookup was 29 %. The last value set on each
    widget is now kept on the Swift side (AndroidBackend+LastSet.swift), so an
    unchanged call costs a dictionary lookup. P66 29-31 samples (iOS 31), P64
    59.0-59.5 Hz with a 33-50 ms worst gap (iOS 58.9-59.8 Hz, 22-43 ms). Not
    done, and not needed at parity: a method-ID cache in swift-java (a fork).
    CLOSED 2026-10-05 with all three platforms measured the same way (full
    sweeps with SCUI_UPDATE_STATS=1, table in
    testapp/measurements/update-stats-20261005.md). Steady state is at parity:
    for the four apps with >= 50 updates, Android median / p95 vs iOS -- P52
    5.8/114 vs 9.5/52, P64 2.5/3.8 vs 3.6/5.1, P66 2.3/5.3 vs 1.0/1.9, P72
    7.4/10.0 vs 5.3/6.1 ms. The gap left is elsewhere, see the next item.
  - [x] **Android: the first updates after launch.** Over 58 apps the Android
    median is 1.44x iOS (median of medians 17.0 vs 10.8 ms, p95 52.5 vs 29.2),
    and the difference sits in apps with few updates, i.e. the first ones after
    launch: P2 83 vs 11 ms for its one update, P4 69 vs 28, P7 max 140 vs 50.
    Likely first-run JIT, class loading and first View creation through JNI --
    unproven. Next: have UpdateTimings report the first update separately, then
    decide whether a warm-up or an ART baseline profile is worth it.
    DONE 2026-10-05, and the guess was wrong. The line now ends in
    `first_ms=` and `rest_median_ms=` (UpdateTimings.swift, its tests,
    csv2_rows.zsh and update_stats_table.zsh carry the two columns; files from
    before have them blank). Android, three runs each, first / rest median ms:
    P1 open-the-root-sheet 15.4 / 55.3, 19.5 / 102.6, 22.6 / 43.0; P2
    expand-the-picker-options 70.1 / 92.4, 161.1 / 96.0, 62.6 / 98.1; P12
    increment-the-counter 35.2 / 69.5, 36.5 / 68.7, 36.4 / 12.1. One run each
    of P0 13.0 / 13.3, P4 59.1 / 50.9, P7 32.3 / 9.0, P66 11.0 / 1.8. The
    slow updates are the later ones that open a sheet or a picker, not the
    first after launch, so a warm-up or baseline profile aimed at start-up is
    not supported; only P7 looks like a start-up cost. (iOS runs use different
    action files, so they are not compared per app.) See the next item.
  - [x] **Android: updates that create views are slow** (found 2026-10-05,
    above). P1's sheet 43-103 ms and P2's picker 92-98 ms on Android. Next:
    time where those updates go -- widget creation through JNI, layout, or the
    Kotlin side -- before choosing a fix.
    - [x] **P2: a quarter of the update was swift-java class lookups** (2026-10-05).
      simpleperf on the emulator (cpu-clock plus --trace-offcpu, dwarf stacks,
      symbols from the unstripped libP2.so), aligned to the update by a temporary
      end-time marker from UpdateTimings (removed again): of P2's 103.9 ms picker
      update, 25.5 ms was `_withJNIClassFromCustomClassLoader` ->
      `JavaClassLoader.loadClass`, reached from `AndroidBackend.updateButton`
      building a new `SwiftAction` and `SwiftObject` for every button on every
      update, and from `JavaClass<CustomButton>()` reads of constants in
      `buttonPadding` and `kotlinRepresentation`. Also in the window: 28 ms with no
      sample at all (the vCPU not running; likely the emulator), 6 ms Kotlin button
      styling, 3.5 ms ART class loading on the main thread. Fixed in
      AndroidBackend+CustomButton.swift: the Java action is built once per button
      and calls a Swift box whose closure is swapped on each update; `set` is called
      only when style, enabled state or colour scheme change (`LastSet`); the
      constants are read once. P2's picker update, three runs each: 92.4 / 96.0 /
      98.1 ms before, 82.6 / 62.7 / 72.5 after. Checked: P12 clicked twice reads
      "counter: 2" (the swapped closure is the one that runs), P21 reads
      "Button -- clicks: 1" with the disabled one dimmed. Not checked: a button whose
      enabled state changes while the app runs.
    - [x] **P1: the sheet is not this.** 63.0 / 51.4 / 57.8 ms after the fix against
      55.3 / 102.6 / 43.0 before -- no clear change. Next: the same profile on P1.
      DONE 2026-10-05: P1's sheet is a cost paid once, the first time. The same
      profile on its 104.4 ms update: 35 ms on the main thread's CPU and one 57.9 ms
      stretch with no sample at all, inside `__swift_instantiateGenericMetadata` ->
      `swift_getGenericMetadata` (the same four libswiftCore frames on both sides of
      the gap; resolved with llvm-symbolizer against the 6.4.0 Android SDK's
      libswiftCore.so). Opening the sheet three times in one run (open, dismiss,
      open, dismiss, open) gave 82.3 then at most 17.7 ms, and 54.9 then at most
      21.3 ms: only the first open is slow. So it is the runtime building the sheet
      view type's generic metadata, plus the emulator not running the vCPU for part
      of it, not per-update work in AndroidBackend. Not pursued: warming that
      metadata at launch would move the cost, not remove it.
  - [x] **Android vs iOS UI gaps (side-by-side of every app's latest capture,
    2026-10-04).** Fix order agreed: 1, 3, 2, then investigate 4 and 5.
    2026-10-05: ticked -- every item under it was already [x].
    - [x] 1. FIXED 2026-10-04 (CustomPopupWindow.showBeside + resolveEdge; new
      P50-arrow-edge-leading.csv). P50 `arrowEdge(.trailing)`: the panel is pushed up above the button
      and the arrow does not point at it. presentPopover places leading/trailing
      top-aligned with the anchor; Android shifts a panel that does not fit, and
      the arrow is computed for the unshifted position. Leading shares the code;
      Android has no leading file.
    - [x] 3. FIXED 2026-10-04 (CustomRadioGroup dims disabled options to 0.4). P74 disabled radio group: labels stay full black on Android; iOS dims
      them.
    - [x] 2. FIXED 2026-10-04 (TableContainer clips to its own frame). P23 table: a long cell wraps to many lines and spills over the text
      below; iOS truncates with an ellipsis. Remaining difference, part of 4:
      Android cells wrap to several lines (column = width / 4) so only ~2.5 of
      12 rows fit, where iOS keeps each row to one truncated line.
    - [x] 4. NOT A DEFECT (measured 2026-10-04). Text in narrow places breaking
      per character on Android ("Sci enc e" P16, "Disa ble it" P29, "Re mo ve 3"
      P51, "u n k n o w n" P47, P23's multi-line cells):
      - P16: identical on iOS -- sidebar 106 pt on both, "Science" 2 lines and
        "Humanities" 3 lines there too; the iOS capture compared was cropped.
      - P51: content wider than any phone; iOS overlaps where Android wraps.
      - P47, P29: the emulator is 411 pt wide against iPhone's 440, Roboto runs
        ~4 % wider than SF (178 vs 171 pt), and Material buttons carry more
        padding. With `wm density 393` (440 pt wide) P29's button fits and P47
        becomes 3 lines (iOS 2).
      Not changed: a 440-pt AVD would invalidate every Android action file's
      coordinates, and 411 pt is a common Android width.
    - [x] 5. NOT A DEFECT (measured 2026-10-04). P41 date pickers "clipped" on
      Android: the page is wider than the phone on BOTH -- iOS puts .graphical
      at x 525 and .wheel at x 499 in a 440-pt window and scrolls too; the two
      action files simply end at different scroll positions. Android's large
      calendar header is the Material picker's own look.
    - [x] iOS, the other way: P57's 500-row List built 29,718 rows on iOS against
      403 on Android. FIXED 2026-10-04 (bca777db): setLazyRows reloaded the whole
      table on every update (343 reloads), and each reload released and rebuilt
      the visible rows; same-count updates now refresh visible rows in place.
      Now 1,913 / 8. A per-cell trace of that run shows 1,906 cellForRowAt calls,
      so each build is one row coming on screen. The rest of the gap to Android
      is the walk, not waste: on iOS the same `scroll 6` rows reach row 446 and
      back (~900), plus a 0..499 burst and 455 scattered rows (6, 33, 71, 119 ...)
      that look like XCUITest's accessibility snapshot making UITableView vend
      off-screen cells -- not yet proven.
    - [x] Harness: P75-close-the-window's capture shows P17-DOE left behind by an
      earlier app; the sweep does not clear the task stack between apps.
      FIXED 2026-10-05: the sweep did force-stop and uninstall each app after its
      file, but as dev.swiftcrossui.testapp.${app:l} -- "p17-doe", while the
      package is "p17doe" (test_android.zsh drops the hyphen). am force-stop of a
      package that does not exist says nothing, so P17-DOE and P15-DARK were never
      stopped or removed. Same spelling fixed in verify_effect_android.zsh,
      verify_replay_android.zsh and test_rootscroll_android.zsh. Verified: sweep
      of P17-DOE then P75 -- close-the-window now ends on the home screen.
    - [x] Android aim after the AVD change (2026-10-05). SoftPCB-mac found P72
      measured on the old api36/SwiftShader AVD, ~62 pt off on api36b. Every
      app with an Android file was launched and its uiautomator tree checked
      against every positioned row (test_support/ios_aim_check.py): 68 apps, 59
      HIT, 6 AFTER (screen changed first; covered by the sweep captures), 36
      MISS -- each read against its note: all land on their target, the MISS is
      the checker failing to match a note written as an action ("cycle 1: none
      -> top") or a target with no text (drop zone, effect tiles, web view).
      None re-aimed. P72 could not be dumped (it animates, uiautomator never
      idles); its files were re-measured by SoftPCB-mac the same day.
  - [x] **Emulator GPU.** DONE 2026-10-04. AVD config pinned to
    hw.gpu.enabled=yes / hw.gpu.mode=host (was no / auto, which fell back to
    software GL under memory pressure). test_android.zsh and sweep_android.zsh
    boot with `-gpu host`; test_android reuses a running emulator, reads the
    renderer from SurfaceFlinger, and if it is SwiftShader/llvmpipe/lavapipe
    restarts that AVD on the host GPU by itself (no flag) and stops if it still
    cannot get one. Proven on an emulator booted with swiftshader_indirect:
    restarted, `Renderer: ... Apple M4 ... Metal`, P1 ran. Full Android sweep
    afterwards: 99 / 99 launched; finals against the previous sweep: 66
    identical, the rest differ only in content (clock, frame counters, files
    the earlier runs saved in Downloads/Recents). That previous sweep was
    already on the host GPU (P72 prints its renderer), so this shows pinning
    changed nothing; it is not a comparison against software rendering.
  - [x] **Disk cleanup: testapp/cleanup.zsh** (2026-10-04). Report by default,
    --apply removes regenerable items: iOS simulators' unified logs (skips
    booted ones), DerivedData, clang module cache, Instruments cache, emulator
    crash db, helper processes left by a dead emulator. Opt-in: --erase-sims,
    --wipe-avd, --deep (SwiftPM/Gradle/Homebrew). First run: 11 -> 18 GB free.
    - [x] scui-wear AVD (1.4 GB, unregistered, untouched since 2026-09-05) and
      its android-34 wear image (4.1 GB): removed 2026-10-04 at the user's
      request (image via sdkmanager --uninstall).
    - [x] test_ios.zsh left a new DerivedData/iOSActionFileRunner-<hash> per
      run (166 on 2026-10-04): `test-without-building` had no
      -derivedDataPath. Fixed; two runs after, zero new folders.
    - [x] Stale build trees removed 2026-10-04 (44 GB on /Volumes/Windows):
      testapp/.compile-work (retired, no suffix), the android31 debug trees
      under .compile-work-android (harness builds release), android28,
      Examples/.build. **Vendor/swift-bundler/.build was removed too and had
      to be rebuilt:** the root `swift-bundler` binary loads its
      ErrorKit_ErrorKit resource bundle from that .build by absolute path, so
      "not modified in 7 days" meant read-only use, not unused. Android P1 then
      died bundling with "unable to find bundle named ErrorKit_ErrorKit"; after
      `swift build -c debug --product swift-bundler` there, Android P1 and iOS
      P12 build and run. Never delete Vendor/swift-bundler/.build.
    - [x] `.swift-bundler-stamp` says the root binary was built from
      swift-bundler 4ad3f14f, the submodule is at 922ba2a7: the installer
      would rebuild it. Pre-existing drift, not changed here.
      CLOSED 2026-10-05, moot: nothing in the harness runs the root binary any
      more -- Android packages through package_android.zsh, and compile.zsh -ios
      no longer has a bundler fallback. CI builds its own from the Vendor commit
      (cache keyed by it), so it never used this binary. The untracked root
      swift-bundler and .swift-bundler-stamp were deleted the same day, at the
      user's request. Scripts/build-tool-install-android-on-Mac.sh (its
      CounterExample check) and Scripts/build-android-bundler.sh still build and
      copy them there, so running either brings them back.
    - [x] **Swift Bundler replaced for Android** (2026-10-05). One tracked Gradle
      project, testapp/androidContainer/gradleProject, built in place at
      .compile-work-android/gradleProject; testapp/package_android.zsh relinks
      compile.zsh's product as lib<Pn>.so from SwiftPM's own link command, strips
      .swift_ast, copies the needed .so files (llvm-readelf), builds libshim.so
      with the NDK's clang, and runs Gradle with the app as -P properties. The
      second Swift build in .build-bundler is gone (27 GB deleted). MainActivity
      is now dev.swiftcrossui.testapp.MainActivity in every app; the four
      scripts that launched `<pkg>/.MainActivity` were updated. Verified:
      bundler and new APKs of P1 hold the same 27 entries, and their manifests
      differ only in that class name; full Android sweep 99/99, finals against
      the bundler sweep of the same day 69 identical, the rest P72 (Mesh3D work
      landed between the runs), P38 (live web page), P57/P75 (counters, files).
      Gradle for a second app: 3-4 s, Kotlin UP-TO-DATE. A first version read
      the 111 MB build plan with yaml.safe_load, 17.5 s per app; now 0.04 s.
      Swift Bundler is still built by the installer for compile.zsh -ios's
      fallback; Android no longer needs it.
    - [x] **iOS: an xcodebuild failure is a defect to root-cause, not something
      for the Swift Bundler fallback to absorb** (user, 2026-10-05). The
      fallback at compile.zsh ~1759 prints one stderr line and carries on, which
      is how P76/P77's "Redefinition of module '_SwiftSyntaxCShims'" at 05:24
      went unnoticed until read back later. Next time it happens: stop, find the
      cause, fix it. Then make the fallback fail loudly (or count it in the
      build manifest and the sweep CSV) so a run that used it cannot read as a
      clean xcodebuild pass, and remove it once xcodebuild has held across a
      full iOS sweep. The _SwiftSyntaxCShims case is root-caused below.
      DONE 2026-10-05: after the root-cause fix, a full iOS sweep built all 101
      files with xcodebuild (101 x "built by: xcodebuild + iosContainer",
      101/101 pass), so the fallback was removed from compile.zsh: an xcodebuild
      failure exits 1 with its log and state, and nothing else runs.
      - [x] Fallback made loud (2026-10-05): compile.zsh -ios keeps the xcodebuild
        output in testapp/output/ios-xcodebuild-<Pn>.log, and on failure appends
        the state (product, DerivedData/TestApps-* with creation times, the
        Redefinition lines) and exits 1. Swift Bundler runs only with
        SCUI_IOS_BUNDLER_FALLBACK=1, reported as a warning and in "built by".
        Proven on a real failure: P12 at 07:00 and 07:05, both
        "Redefinition of module '_SwiftSyntaxCShims'", deterministic. The first
        version died with `print: bad option: -` on its own heading -- the check
        would have read as working until a failure tried to use it.
      - [x] Root cause found and fixed (2026-10-05). xcodebuild had no
        -derivedDataPath, so it resolved packages into
        ~/Library/Developer/Xcode/DerivedData/TestApps-*/SourcePackages while
        Swift Bundler (-derivedDataPath = $ios_derived_data) resolved them into
        .compile-work-ios/.../arm64-apple-iphonesimulator/SourcePackages, and both
        shared OBJROOT. Every target's cached PIF (XCBuildData/PIFCache) carries
        the swift-syntax prebuilts' absolute path, and an unchanged target keeps
        its cached PIF: SwiftCrossUIMacrosPlugin's (2026-09-29, bundler) named
        .build's checkout, MacroToolkit's (regenerated) named DerivedData's, and
        the plugin got both sets of -I. Fix: compile.zsh passes the same
        -derivedDataPath as the bundler, and the stale XCBuildData was removed
        once. Verified: P12, which failed twice in a row, builds; after the
        purge xcodebuild -> bundler -> xcodebuild all succeed with the plugin
        recompiled each time and 0 DerivedData/TestApps paths in any log; P76 and
        P77 run on the simulator built by xcodebuild. Adding the flag WITHOUT the
        purge passed P12 but still showed DerivedData paths from the old PIFs --
        the purge is part of the fix on any tree built before it.
      - [x] Homebrew clang in iOS builds (found in the same log): a shell profile
        exporting CC/CXX=/opt/homebrew/opt/llvm/bin/clang made xcodebuild compile
        the C targets with it, explicit modules off ("did not match the configured
        compiler", 354 times in one P12 build). compile.zsh unsets CC and CXX for
        xcodebuild only; the next P12 build: 0 and 0, BUILD SUCCEEDED.
      - [x] The purge is automatic (2026-10-05, at the user's request): before the
        iOS build loop compile.zsh lists every SourcePackages path in
        XCBuildData/PIFCache, and if any is not $ios_derived_data/SourcePackages it
        says so and removes XCBuildData (one full rebuild). Proven both ways: on
        the clean tree P12 built with no message and XCBuildData untouched; with a
        PIF naming DerivedData/TestApps-fake planted, the run named it, removed
        the cache, rebuilt from scratch (rc 0, xcodebuild), and the rebuilt cache
        names only this tree. Covers clones built before 5deb2156 and trees that
        have moved, without a manual step.
    - [x] .compile-work-android/.build-bundler/bundler/apps/<Pn>/<Pn>.project
      was ~1 GB per app plus a duplicate APK each. Swift Bundler deletes and
      regenerates the project on every bundle (APKBundler.swift), so a shared
      folder would reuse nothing; test_android.zsh now moves the APK out and
      drops the project, so one Gradle project exists at a time (2026-10-05).
      Existing ones removed: 400 -> 456 GB free. P1 then P12 built and
      launched; P12's bundle 33 s against 32 s before.
    - [x] Concurrency: test_ios.zsh shares testapp/.bundledApp (runner project,
      build, and the .xctestrun it edits with PlistBuddy) across all apps, and
      compile.zsh shares one .compile-work-<backend> tree per backend, so two
      runs on the same platform at once are not safe -- they were not before
      the DerivedData fix either.
      DONE 2026-10-05 as serialisation, not parallelism: test_support/
      platform_lock.zsh gives Android and iOS a lock each (mkdir + owner PID,
      dead-owner takeover, re-entrant for a child, released through zshexit),
      taken by test_android.zsh, test_ios.zsh and compile.zsh -android/-ios. A
      second run now waits. Verified on both: two runs started 3 s apart, the
      second printed "waiting for the <platform> lock" and ran after the first,
      both rc 0, the nested compile.zsh passed straight through. True parallel
      runs would need a device and a 5-15 GB tree per run; not done.
  - [-] **CANCELLED 2026-10-04. Kotlin -> pure JNI rewrite (CustomSegmentedGroup etc.): not
    recommended.** Profiling shows the cost is the NUMBER of JNI crossings;
    Kotlin helpers do several things per crossing, pure JNI would add crossings.
    Only worth it to drop the Kotlin/Gradle build dependency.
  - [-] **CANCELLED 2026-10-04. swift-java method-ID cache (fork): deferred** -- not needed at parity.
  - [x] **Per-Pn performance table.** Only P52/P64/P66 report numbers. Proposed:
    an env var that makes SwiftCrossUI print update-time statistics (count,
    median, p95, max) at exit; the sweeps collect them per platform so every
    Pn is compared Android vs iOS vs macOS on the same action file.
    DONE 2026-10-05. SCUI_UPDATE_STATS=1 (or --update-stats, which is how it
    reaches an Android app) makes UpdateTimings.swift time every update in
    Publisher.observeAsUIUpdater and print a cumulative "update-stats: count
    median_ms p95_ms max_ms" line on stderr after 1.5 s of quiet, and every 5 s
    while an app animates without pause -- not at exit, since apps under test
    are killed. test_android / test_ios / test_common (macOS, Windows) pass the
    flag and print the last line as "==> update-stats:"; the sweeps export it
    and write testapp/output/update-stats-<platform>.csv2;
    testapp/update_stats_table.zsh joins the three into one Markdown table.
    Verified on all three with P12 and P66 (P66: android 1.6/3.2/9.3 ms n=309,
    ios 1.1/4.0/16.2 n=231, macos 1.3/1.9/2.4 n=310). The sweep CSVs are now
    written through csv2 (test_support/csv2_rows.zsh) instead of Python csv,
    whose writer put CRLF on every line. Not yet: WSL (print_summary_wsl reads
    the log through wsl.exe) and a full three-platform sweep to fill the table.
  - [x] **Stack ideal width undercounts (P51).** FIXED 2026-10-01: commit-time
    redistribution offered the stack's overflowed result (522) instead of its
    proposal (408); it now offers the smaller of the two. On iPhone the outer VStack
    reports 522 pt while the two-column HStack inside it draws to 579, so the
    root scroll host stops 57 pt short and the second column is cut even
    scrolled to the end. Not iOS-specific -- any window narrower than the two
    columns. Evidence: a dumptree row after P51's scroll.
- [x] **3. P5 on iPad: alerts on two windows at the same time.** DONE 2026-10-02.
  `actions/ios/P5-alerts-on-two-windows-ipad.csv`: the main window is asked for
  an alert in 3 s (P5's new button), the second window opens over it and shows
  its own, and the dumptree lists 'Alert A (Secondary)' and 'Alert A (Main)'
  together. Verified twice, and the control (no delayed press) lists only one.
  Windows are not moved or sized: the iPad Simulator's backboardd aborts in
  Metal ("invalid pixelFormat (0)") during window drags and scene restores, and
  no API sizes an iPad window. `# fresh-install` in an iOS action file now
  uninstalls first, so last run's windows are not restored. Runner: `screen`
  origin, `windowframes`, held slow drags, `taplabel` falls back to a
  non-hittable match (alert buttons report isHittable false).
  - [x] Android P5 re-aimed (2026-10-04, verified: Alert C on top). The AVD
    whose data went bad when /Volumes/Windows dropped was replaced by
    swift-cross-ui-api36b on /Volumes/Windows and the old one deleted; full
    Android sweep on it: 98/98 launched, every capture read.

### Then: iPad testing (after 1-4)

How to run it is in `testapp/README.md` > Devices > iPad (and README_zhTW.md).

- [x] **Windowed mode.** DONE 2026-10-02: `test_support/ipad-windowed-apps.csv`.
  Fastest: set it once by hand in the iPad Simulator,
  Settings > Multitasking & Gestures > Windowed Apps (it persists). Durable:
  have the XCUITest runner drive the Settings app (`com.apple.Preferences`) so
  a fresh Simulator can be set up unattended. `defaults write
  com.apple.WindowManager GloballyEnabled` and `com.apple.springboard
  SBChamoisWindowingEnabled` did NOT switch it (2026-09-30).
- [x] **P59 / P62 on iPad** (2026-10-03): `P59-two-windows-ipad.csv`,
  `P62-two-documents-ipad.csv`, read from the dumptree. P59 found a core bug:
  `Publisher.observeAsUIUpdater` kept ONE merge slot per publisher, so when two
  windows observed the same @AppStorage the second window's update was dropped
  as "merged" (window A stayed AA, B showed AAB). Now one slot per observer;
  verified twice, and full macOS (97/97) and iOS (103/103) sweeps compared
  capture by capture. `-ipad` files are skipped by the iPhone sweep.
- [x] **Mac input source.** Since 2026-10-03 the active input source is Zhuyin
  (com.apple.inputmethod.TCIM.Zhuyin), and the macOS synthesiser's keys go
  through it: P71's Cmd-S / Cmd-Shift-E fire 0 times and P9 types kana instead
  of "hi" -- with the old Publisher too, so not a code change. Switch to ABC
  before macOS sweeps, or make the synthesiser select an ASCII source itself.
  DONE 2026-10-05: AppKitSynthesiser.prepareForReplay switches to the ASCII
  keyboard layout when the file sends keys and the current source is not one,
  reports it, and finishReplay restores the original. Verified with Zhuyin
  selected: P71 plain 1 / shifted 1 / disabled 0, P9 typed "hi", the log reads
  "Zhuyin -> ABC ... restored to Zhuyin", and Zhuyin was current afterwards.
- [x] **P14 rotation on iPad** (2026-10-03): `P14-rotate-ipad.csv` -- proposed
  width 802 portrait, 1178 landscape, 802 again, read from the tree.
- [ ] **P72 cursor on iPad: physical iPad only.** `P72-cursor-ipad.csv` and the
  runner's `hover` verb are ready, and UIKitBackend prints the pointer style the
  system asks for under --debug; but the Simulator delivers no hover to apps --
  neither the style request nor a UIHoverGestureRecognizer fired across two
  hovers the runner logged. Run it on an iPad with a trackpad.
- [ ] **iPad action files**, named `<Pn>-<what>-ipad.csv`, measured on an iPad
  capture (834x1210 points, @2x: points = pixels / 2). One exists:
  `P75-close-the-window-ipad.csv` (verified).
- [ ] **What to test on iPad:** multi-window P5, P59, P62; closing a window
  P75 (done); pointer hover and cursors P72 (iPhone has neither); rotation P14.

## 2026-09-27 found while driving iOS

- [x] **Re-measure the iOS action files: most of them no longer aim at their -> completed.md (archived 2026-10-05)

- [x] **FIXED 2026-09-28 (the lost model; the over-eager re-creation remains).** -> completed.md (archived 2026-10-05)
- [x] **FIXED 2026-09-29: a re-layout reuses each node's kept body.** A node keeps
  the body its view's default layout evaluated (`BodyCapture` / `lastBody`); a pass
  started by a child's resize -- or by the window when its content resized, which
  no longer recomputes the scene -- carries `EnvironmentValues.reusesBodies`, and
  every node on it lays out its kept body instead of evaluating `body`. Commit
  always uses the laid-out body, so a commit builds no views. The flag and the
  cache are pass-only and never stored, so a node's own update still evaluates its
  body. Evidence: the `withKnownIssue` test began reporting "known issue was not
  recorded" and is now a plain expectation that fails without the change (shown);
  whole test product passes. P45Model: 7 constructions per run on macOS before,
  now the 4 at launch and none on any state change; Android 2 at launch and none
  after. Full sweeps on the change: macOS 83/83 and iOS 74/74, each capture
  compared pixel-wise with the last verified one -- all identical but the pages
  that change by themselves (spinning cube, video, network images) and P38, whose
  failures came from example.com now serving localized pages (macOS now follows
  the link with Option-Tab; iOS loads P38's own fixed page via -url). Launch still
  builds the root view a few times (the window probes its minimum and maximum
  sizes with the scene); that is bounded and was left alone.
  **Independently confirmed 2026-09-29 by SoftPCB-mac on 268502a8 (clean
  sources):** GeometryRenderModel.init 28 -> 7, 9, 7 over three runs of the same
  action file (tab 9, a coupon clicked twice); every init before the first
  `select` -- launch and the tab switch -- and none after either click; one model
  ObjectIdentifier throughout, selection held. Probe reverted on their side.
  **2026-09-29 由 SoftPCB-mac 在 268502a8 上獨立確認:**28 次降為三次執行的 7、9、7,全部發生在啟動與切換分頁時,兩次
  點擊之後一次也沒有;model 全程同一個物件,選取保住。Original entry:
  **Core: a child's resize makes its parent re-evaluate `body`, so views are
  re-created on every state change that changes a size.** Every `computeLayout`
  evaluates `body`, and `bottomUpUpdate` climbs through `onResize`. Consequence
  left after the ObservedObject fix: initial-value expressions of wrappers run far
  more often than in SwiftUI.
  **Attempted 2026-09-29, reverted.** A pass-only `reusesChildViews` flag, set by
  `onResize` (node and window) and never stored, so nodes keep their views and the
  window stops recomputing the scene. The whole test product still passed, but the
  new test -- a child's @State change must not construct the child again -- failed
  IDENTICALLY with and without it: laying the parent out evaluates its body, and
  evaluating `VStack { Child() }` builds `Child` whether or not its node takes it.
  The flag only prevented the adoption, which the ObservedObject fix already
  handles, at the price of relayouts no longer applying new views on every
  backend. **What a real fix needs:** a re-layout that does not evaluate `body` --
  each node keeping the body value it last computed and laying that out, which
  touches every default implementation in `View` (children, layoutableChildren,
  asWidget, computeLayout, commit). The test stays in `ObservedObjectTests` under
  `withKnownIssue`; it will report when this is fixed.
  **2026-09-29 試過並撤回。**只屬於該趟的 `reusesChildViews` 旗標無法阻止子 view 被建出:排版父層就會求值 body,
  而求值本身就會建出子 view。真正的修法是重新排版時不求值 body——每個節點保留上次算出的 body 值並排版它,這會
  動到 `View` 所有預設實作。測試以 `withKnownIssue` 留在 `ObservedObjectTests`,修好時會自己報告。
- [x] **Core: a view's own @State change re-creates it from its parent, and an inline -> completed.md (archived 2026-10-05)

- [x] **Read every macOS capture against its file's assertion, as was done for iOS.** -> completed.md (archived 2026-10-05)

- [x] **WITHDRAWN 2026-09-28 -- not a defect.** Pop to root sets pushCount = 0 -> completed.md (archived 2026-10-05)

- [x] **Core crash, ViewGraphNode.swift:13 (`_widget!`): a publish that arrives -> completed.md (archived 2026-10-05)

- [x] **WITHDRAWN 2026-09-27 -- there is no defect; the entry below was wrong.** -> completed.md (archived 2026-10-05)

- [x] **CLOSED 2026-09-29 -- does not reproduce.** A long press held with the menu
  open, captured three times (p72-ios-final-20260929-000335/000434/000453.png):
  Reset the camera and Snapshot shown, no keyboard in any of them. The suspected
  cause does not exist either: `KeyEventWidget` is a view CONTROLLER that becomes
  first responder and adopts no `UIKeyInput`, so UIKit has no text input to show a
  keyboard for. The 2026-09-27 captures predate the RootScrollHost and
  first-responder changes of 09-27/28 and the simulator's one-time typing sheet;
  which of those it was is not known. Original entry:
  **UIKit: a long press on P72's mesh view raises the software keyboard.**
  Seen in every capture of the open context menu on 2026-09-27 (and once as
  the simulator's one-time "Speed up your typing" sheet). Suspected, NOT
  verified: the view takes first-responder status for `.onKeyPress`, and UIKit
  shows a keyboard for a first responder that accepts text input. SwiftUI's
  `.onKeyPress` does not raise one. Check `UIKitBackend+KeyEvents.swift` for
  `UIKeyInput` / `canBecomeFirstResponder` before changing anything.
  **UIKit:P72 的 mesh view 被長按時會叫出螢幕鍵盤。** 2026-09-27 每一張「選單已開啟」的擷圖都看得到
  (其中一次是模擬器一次性的「Speed up your typing」面板)。推測、**未查證**:那個 view 為了 `.onKeyPress`
  取得 first responder,而 UIKit 會為一個接受文字輸入的 first responder 顯示鍵盤。SwiftUI 的 `.onKeyPress`
  不會叫出鍵盤。動手之前先看 `UIKitBackend+KeyEvents.swift` 裡的 `UIKeyInput` / `canBecomeFirstResponder`。

## 2026-09-12 Windows / WSL handover

- [ ] **#123 external verification follow-up (2026-09-17)**: WSLg AT-SPI
  reads label/hint/value and excludes decorative, but still exposes the original
  `X` child. Windows external UIA also lists `X` and `decorative`; Narrator and
  control/content-tree filtering remain unverified. See
  `testapp/plan/verification-followup-20260917.md`. 外部探針已執行，不是完整通過。
  **GTK half fixed later on 2026-09-17:** a labelled button's content is now HIDDEN;
  the WSLg AT-SPI probe passes all five checks (exit 0). Still open: WinUI's UIA tree
  (which view the client read) and actual Narrator/Orca speech.
  **GTK 那一半同日稍晚已修**,外部探針 5 項全過;WinUI 的 UIA 樹與實際朗讀仍開著。
  **WinUI half fixed the same evening:** `p69_uia.zsh` names the view. `X` and
  `decorative` were really in the control view, because `AccessibilityView.raw`
  does not cover children. It is now applied to the subtree, and the probe
  passes 14/14. Found: GtkBackend on Windows has no accessibility backend at
  all, since the gvsbuild GTK is built without AccessKit. See todo.md. Still
  open: actual Narrator/Orca speech.
  **WinUI 那一半同晚已修**(子樹設 raw,14/14);另發現 Windows 上的 GTK 完全沒有無障礙後端。朗讀仍未聽過。
  **2026-09-29, from the Mac side: speech no longer needs a listener -- TalkBack is
  done this way** (see the closed #123 複驗 item and
  `testapp/measurements/talkback-p69-20260929.txt`). The same idea for the two
  readers left here, both on the Windows machine and not runnable from the Mac:
  - **Orca (WSLg):** `orca --debug --debug-file=/tmp/orca.log`, or point
    speech-dispatcher at its `dummy` output module; the debug log records each
    utterance's text. Touch/keyboard-navigate P69 and grep the log for Close,
    Removes the file permanently, 40 percent, Half past twelve, and the absence
    of X and decorative.
  - **Narrator:** it cannot be given another voice, but its utterances are the
    UIA names/help/values it reads, and NVDA -- scriptable, with a speech log at
    log level "debug" -- reads the same tree. An NVDA transcript of P69 is the
    mechanical equivalent; a Narrator-only difference would need a person.
  **2026-09-29,來自 Mac 這一側:朗讀不再需要有人聽——TalkBack 已經這樣驗證。**剩下的兩個閱讀器都在 Windows 那台機器上,
  Mac 這邊跑不了:Orca 用 debug log 或 speech-dispatcher 的 dummy 模組取得逐字稿;Narrator 無法換聲音,但 NVDA 讀的是同一棵
  UIA 樹且可取得語音 log,可作為機器可驗證的等價物。

- [x] **#117 GTK ListView integration and P57 verification — 2026-09-16 完成**: -> completed.md (archived 2026-10-05)

Source corrections to older entries below: #128 is already Double
(`cfe30184`), and WinUI #117 was implemented in `bde16de0`; neither remains
an unimplemented conversion. 原始碼已完成上述兩項，舊條目不可直接當作現況。

由 `heartbeats/heartbeat.zsh` 讀取。**未完成寫 `- [ ]`,完成改成 `- [x]`。**
順序即優先序:第一個未完成項就是下一件事。

Read by `heartbeats/heartbeat.zsh`. Order is priority: the first unchecked
item is the next thing. This file exists because the queue used to live in the
conversation, where it faded with compaction and its absence looked exactly like
an empty queue -- mistakes.md entry 1.

- [x] **1. iOS 動作檔的點擊沒抵達按鈕** — 已解決。按鈕實際在 (55, 218) 點,先前的 y=100 是從縮圖估的。runner 現在會說出它解析到... -> completed.md (archived 2026-10-05)
- [x] **2. 動作檔無法定址第二個視窗** — 已解決。新增 `focus` 動作(第十欄 `target` 放標題),並補上 AppKit 缺少的 `curren... -> completed.md (archived 2026-10-05)
- [x] **1. P50 macOS:「Show title B」按了標題沒變** — 已修。狀態改變若不改變尺寸,就不會有人告訴視窗 preference 變了;新增... -> completed.md (archived 2026-10-05)
- [x] **2. P50 macOS:「按下 press me 後文字位移」—— 不重現,三個 backend 數字一致(2026-09-19 結案)** -> completed.md (archived 2026-10-05)

- [x] **2b. P50:一次 light dismiss 觸發兩次 `onDismiss`** — 已修。`NSPopover` 會把「實作通知形狀方法的 dele... -> completed.md (archived 2026-10-05)
- [x] **2c. 動作檔已能驅動 AppKit 的 popover** — 兩件事要一起改:(1)`targetWindow()` 不再回傳 popover——pop... -> completed.md (archived 2026-10-05)
- [x] **3. P32:Toggle 沒有可見的開啟狀態** — 已修。`onStateBezelColor` 來自 `environment.toggleColor... -> completed.md (archived 2026-10-05)
- [x] **4. P44:vertical stack 空間耗盡** — 已修:那是誤報。`offered 643 / took 643` 相等,什麼都沒不夠;是 `S... -> completed.md (archived 2026-10-05)
- [x] **5. P28:點擊延遲 — 兩條未量的路徑都量完了** — 「真實滑鼠事件合成不出來」不成立:`AppKitSynthesiser` 檔頭那個「CGEven... -> completed.md (archived 2026-10-05)
- [x] **5b. #126 `onEditingChanged`** — 已完成。五個 backend 全數實作,AppKit/UIKit/Android **實測建... -> completed.md (archived 2026-10-05)
- [x] **M1. #32 手勢 — 三份實作完成,拖曳已驅動驗證** — 新增三個協定(`DragGestures`/`MagnifyGestures`/`RotateGestures`,分開是因為 Android 沒有旋轉偵測器)、`onDragGesture`/`onMagnifyGesture`/`onRotateGesture` 三個 modifier,五個 backend 全部實作。**AppKit 的拖曳以真實 `CGEvent` 驅動並對著像素驗過**:面板在螢幕 (80,252)、送出 (150,290)→(230,320),回報 start (70,38)、location (150,68)、translation (80,30),三者一字不差。**縮放與旋轉編過但未驅動**——此處沒有任何合成器產得出觸控板手勢,需要有人在機器前用兩指做一次。順帶抓到的兩件事寫在程式碼裡:pan 辨識器的 slop 門檻會讓 `.began` 的座標偏晚(改用 `translation(in:)` 回推);以及 P65 自己的回報文字變長會推動置中的版面,讓 80 點的拖曳量成 100 點
  - **2026-10-05 由 [~] 改為 [x]:** 當時未驅動的縮放與旋轉,已由 M9(2026-09-17)在 iOS 與 Android 驅動,AppKit 與 X11 以寫明的理由拒絕(見 completed.md 的 M9)。沒有剩下的部分。
- [x] **M2. #125 Table 的 `selection` 與 `sortOrder` — 兩項都已完成於五個 backend(2026-09-16)** —... -> completed.md (archived 2026-10-05)

- [x] **M4. #121 在 iPhone 上已補上 — `UIResponder.keyCommands`(2026-09-16 完成並驅動驗證)** — UIK... -> completed.md (archived 2026-10-05)

- [x] **M5. `LazyListRowLifetimes` — 三個 backend 都已實作,而且三個都已驅動驗證(2026-09-16)** -> completed.md (archived 2026-10-05)


- [x] **M6. 已修,而且它從來不是 AppKit 的缺陷 — 是測試合成器裡的兩個缺陷(2026-09-17)** -> completed.md (archived 2026-10-05)

- [x] **M7. P4 與 P8 在 macOS 上一啟動就崩潰 — 都已修(2026-09-17)** -> completed.md (archived 2026-10-05)

- [x] **M8. `.inspect` 的同一個缺陷 — UIKit 已修並驗證;WinUI 與 GTK 於 2026-09-17 由 Windows 修好並驗證**... -> completed.md (archived 2026-10-05)
- [x] **M3b. #109 popover `arrowEdge` — 兩個 Windows backend 已完成並成對驗收(2026-09-16)** — 決定為 (1):加 `arrowEdge` 當**提示**、backend 可翻轉。落地形狀:獨立協定 `BackendFeatures.PopoverArrowEdges`(一個方法)加上 `.popover(isPresented:arrowEdge:onDismiss:content:)`;**不在 `presentPopover` 上加參數**,那會一次弄壞五個 conformance,而其中四個此處編不動(mistakes 第 10 條)。
  - **2026-10-05 由 [~] 改為 [x]:** 上文已寫明 2026-09-17 五個 backend 全部 conform `PopoverArrowEdges` 並各自以成對動作檔驅動;兩個後續修正也已落地。沒有剩下的部分。
  - **WinUI**(`Flyout.placement`,偏好存在 `Popover` 上以免被 `presentPopover` 的 `.auto` 蓋掉):同一顆按鈕,`.top` 面板在上、`.bottom` 在下,兩張圖含讀數。
  - **GTK**(`GtkPopover.position`):`.top` 尖角**朝下**、`.bottom` 尖角**朝上**。**這一對比 WinUI 那對更強**——方向是 `GtkPopover` 自己畫在圖上的,不是從面板位置推論的。
  - **丟棄過兩組不可證偽的安排**,理由寫在動作檔裡:第二顆按鈕四周都沒空間,`.bottom` 翻到上面、`.leading` 翻到右邊,每一組的兩張圖都相同。**一組不可能不同的對照,無論程式如何運作都證明不了任何事。**
  - **`leading`/`trailing` 在兩邊都解析為 left/right**,因為 `GtkPositionType` 與 `FlyoutPlacementMode` 都不跟隨書寫方向;RTL 版面應當對調,這句話寫在兩個實作裡。
  - ~~**AppKit / UIKit / Android 尚未實作**,那是 Mac 那邊的。~~ **2026-09-17 三個都完成並各自以成對
    動作檔驅動過。** 五個 backend 現在都 conform `PopoverArrowEdges`;P50 的「arrow edge supported」
    在三處都讀到 `yes`。
    - **AppKit**:`NSPopover` 沒有可設定的邊屬性,因此偏好存在 `NSCustomPopover` 上、由
      `presentPopover` 花掉。**第一版對應是反的**:檔案裡原有的註解說「`.maxY` 是下方」(從本 backend
      的翻轉 view 推論而來),而擷圖說相反——`p50-macos-final-20260917-155815.png` 讀數寫 `top` 而面板
      在**下方**、`-155948.png` 寫 `bottom` 而面板在**上方**。`NSPopover` 是在 AppKit 自己 y 向上的
      螢幕座標裡讀 `preferredEdge` 的。修正後:`-160136.png`(top,面板在上、讀數看得見)、
      `-160229.png`(bottom,面板在下)。
    - **UIKit**:`permittedArrowDirections` 指的是**箭頭**在哪一側,與 `Edge` 相反,因此
      `.top -> .down`、`.bottom -> .up`。**而驅動時發現 iPhone 上的 popover 根本不是 popover**:
      compact 寬度下 UIKit 會把它改成 sheet,除非 delegate 拒絕,而 `CustomPopover` 沒有拒絕
      ——`p50-ios-final-20260917-161038.png` 是一塊從畫面頂端整片蓋下、沒有錨定的面板,於是 P50 自己
      「每塊面板都必須落在開啟它的那顆按鈕旁邊」根本無從成立。現已回傳 `.none`。修正後:
      `-161314.png`(top,面板在上、箭頭朝下)、`-161400.png`(bottom,面板在下、箭頭朝上)。
      **那份 `.bottom` 檔案原本預測「兩張會一樣」(下方只有 144 點、面板約 200 點),而執行推翻了它**
      ——UIKit 會把 popover 縮到它擁有的空間,而不是拒絕那一側。
    - **Android**:五個之中唯一「這件事是算術」的。`PopupWindow` 沒有位置屬性,因此
      `createPopover` 改回傳 `CustomPopupWindow`(持有偏好的 Kotlin 子類別),`presentPopover` 算出
      `showAsDropDown` 的位移。**上/下那一對在這台裝置上分辨不出東西,而這是量出來的**:錨點在 914 點
      視窗的 y 755、下方約 140 點對上約 200 點的面板,`showAsDropDown` 會把放不下的 popup 移到上方
      ——`-162100.png`(top)與 `-162204.png`(bottom)是同一塊面板在同一處,各自帶著不同的讀數。
      把錨點捲高也辦不到:內容在 2400 像素中結束於 2391,一列 `scroll` 沒有改變任何 bounds。
      **真的做得出差別的是 `.trailing`**:`-162438.png` 的面板明顯右移、與按鈕同高而非差一列。
    - **兩個後續修正(同日,由「這三件需要修嗎?」問出來的):**
      - **AppKit 的預設側邊改為下方。** 沒有給 `arrowEdge` 的 popover,原本在 AppKit 上開在錨點
        **上方**(`p50-macos-final-20260917-195515.png`,讀數 `none (platform decides)`),而另外四個
        backend 都是下方(`GtkPopover` 預設、`showAsDropDown`、`Flyout` 自動、UIKit 的 `[.up,.down]`)。
        那行呼叫自落地以來一直帶著 `.maxY`,而它上面的註解寫著「那會放在按鈕下方」——意圖對、主張錯,
        而且從來沒有人變動過它去檢查。改為 `.minY` 後:`-195726.png`,面板在下方。
      - **UIKit 在「放不下」時對齊 Android 的做法。** 同一道算術,兩個平台原本答得不一樣:Android 會把
        放不下的 popup **移到**另一側並保持完整,UIKit 則把 popover **縮**進去——而 P50 顯示了代價:
        `-161400.png` 裡面板在按鈕下方,`press me (0)` 與 `close this panel` 被下緣切掉了。
        `UIKitBackend+Popover.swift` 現在會對著 safe area 量出空間(加 13 點箭頭),被要求的那一側
        容不下就改要求相反的一側。修正後:`-200019.png`(同一個 `bottom` 要求,面板在**上方**且完整)、
        `-200123.png`(`top` 重跑,不變)。UIKit 自己的縮小仍是兩側都放不下時的底線。
    - **順帶在 P50 上修掉一個 macOS 的排版缺口**(非 backend):視窗以內容的理想尺寸 780x825 開啟,
      而第 2 區塊的三顆按鈕被畫成三像素高的長條。手動改成 780x1020 就正常、改成更寬的 1400x825 則否,
      因此是高度;`defaultSize` 與 AppKit 儲存的視窗框都蓋不過那次「依理想尺寸重設大小」。P50 現在在
      AppKit 上要求 `.frame(minHeight: 1000)`,而「理想高度比實際能繪製的高度少約 150 點」這件事本身
      寫進了 todo.md。
- [x] **5c. #122 focus / #123 accessibility:protocol 形狀草案已出** — `testapp/plan/plan-foc... -> completed.md (archived 2026-10-05)
- [x] **5c-ANSWER(Windows 回覆,2026-09-10):同步的 `focus` 可以照用,形狀不必改。** -> completed.md (archived 2026-10-05)
- [x] **#120-ANSWER(Windows 回覆,2026-09-10):兩個問題都答「可以走 (b)」。** -> completed.md (archived 2026-10-05)
- [x] **#123 三份實作完成,三個平台都以真實探針驗過** — 新增 `BackendFeatures.Accessibility`(四個單向 setter,co... -> completed.md (archived 2026-10-05)
- [x] **#122 focus 三份實作完成,macOS 與 Android 以真實輸入驗過** — `BackendFeatures.FocusableViews`... -> completed.md (archived 2026-10-05)
- [x] **M3a. #79 GTK 39px — 已修好,且 2026-09-16 以 P61 驅動驗過 `shortfall 0x0`** — 已定案為 (c),由... -> completed.md (archived 2026-10-05)
- [x] **6. P25 多檔** — 已回答並處理。**拖放本來就支援多檔**:`DropPayload.urls` 解析整份 `text/uri-list`,而 P... -> completed.md (archived 2026-10-05)
- [x] **7. P33 / P34 盤點** — 已完成。十六個名字以宣告形狀 grep 加對照組查證,**只有 `LazyHGrid` 缺席**(即 #118);兩... -> completed.md (archived 2026-10-05)
- [x] **7b. P34:兩位數的列在右側被切掉 — 已修** — 成因不在 stack,而在**量測與繪製走不同路徑**:AppKit 以 `NSString.bo... -> completed.md (archived 2026-10-05)
- [x] **9. `DocumentGroup`** — 已完成並驅動 (P62)。`FileDocument`、每份文件一個視窗、`newDocument`/`ope... -> completed.md (archived 2026-10-05)
- [x] **10. #28 動畫 / #32 手勢** — 見第 7 項;此處為重複條目,一併關閉。 -> completed.md (archived 2026-10-05)
- [x] **11. #117 phase 3(依需求建列)— AppKit 已落地,靜止時的問題解決了** — 新增 `BackendFeatures.LazyListRows`(conformance 檢查,與 `ScrollingLists` 同樣可一次轉一個 backend)。**量到:10,000 列 423 MB → 104 MB**,而單列基準線是 102 MB —— 也就是「開在一萬列上的清單,成本等於開在空清單上」。400 列 104、2000 列 103,是**平的**而不只是比較小。關鍵一步是**先建一列來種下高度估計值**:少了它,表格以為清單很短、排出遠多於它會顯示的列,provider 被呼叫 500+ 次才顯示 12 列。**未解決且已量過的界限**:捲動時每造訪一列仍多約 30 KB 且不回收(104→225 MB / 600 段),heap 指出是 AppKit 抓著 view(`NSKeyValueDependency` 1,381→25,835),不是框架抓著節點。下一階段在 backend 側:列捲出視野時要釋放或重用它的 view。**UIKit 也已轉換**:10,000 列 449 MB → 170 MB,而 500 列同樣是 170 MB(平的)。**Android 也已轉換,並已在裝置上量過**:10,000 列 385 → **92 MB**,單列 91 MB(`dumpsys meminfo` 的 `TOTAL PSS`,同一支 APK、同一台模擬器),而 10,000 列時 provider 被呼叫不到 500 次。形狀上:`BaseAdapter` 本來就是「問第 N 列」的形狀,缺的是「帶參數且有回傳值」的 Java→Swift 路徑——用 `external fun` + `@JavaImplementation`(先例是 `MainRunLoopTickler.tickle`),並以一個 id 對應到 Swift 側的 provider,因為 JNI native method 沒有被捕捉的狀態。GTK/WinUI 尚未轉換
  - **2026-10-05 由 [~] 改為 [x]:** 剩下的 `LazyListRowLifetimes`(AppKit / UIKit / Android)已由 M5 完成並驅動(見 completed.md);末尾「GTK/WinUI 尚未轉換」早已更正。2026-10-05 P57 在 macOS、iOS、Android 都重跑通過。
  - **末尾那句「GTK/WinUI 尚未轉換」已經過期(2026-09-16 查證),與第 8 條是同一個錯。**
    `Sources/WinUIBackend/WinUIBackend+LazyListRows.swift:81` 宣告
    `extension WinUIBackend: BackendFeatures.LazyListRows`;
    `Sources/GtkBackend/GtkBackend+LazyListRows.swift:4` 宣告
    `extension GtkBackend: BackendFeatures.LazyListRowLifetimes`,而該協定 refine 了
    `LazyListRows`(`Containers/LazyListRows.swift:5`),因此 **GTK 兩者都滿足,否則編不過**。
    五個 backend 全部有 `LazyListRows`;真正的缺口只在 `LazyListRowLifetimes`,而且在
    AppKit / UIKit / Android 那三個(見第 8 條與 M5)。
- [x] **12. #113 n^1.5 版面成本 — 已跑,結論是「不是 n^1.5,它是線性的」** — P52 四條 arm、12→192 五個尺寸,每格成本是*... -> completed.md (archived 2026-10-05)
- [x] **13. #120 Grid — 已完成:共用欄 + `gridCellColumns`** — 成因不是「需要新的 backend 能力」,而是**父層看不... -> completed.md (archived 2026-10-05)
- [x] **14. #127 `GeometryProxy.frame(in:)` — 已完成(GTK/WinUI 待對方編一次)** — Windows 答覆後路線確... -> completed.md (archived 2026-10-05)
- [x] **15. #28 Animation — 完成(時鐘 + 引擎)** — 引擎接在**狀態**那一端而不是版面那一端:`StateImpl` 的 setter... -> completed.md (archived 2026-10-05)
- [x] **16. #118 LazyHGrid — 已完成** — 先把 `GridLayoutPlan` 的詞彙從 column/row 改成 lane/line ... -> completed.md (archived 2026-10-05)

- [x] **17. #128 `EdgeInsets` — 已完成,這條協調請求已無須回覆(2026-09-17 查證)** — 原本是 Windows 端的一個**協... -> completed.md (archived 2026-10-05)

- [x] **M9. magnify / rotate — 完成(2026-09-17):格式、iOS、Android 都已驅動;AppKit 與 X11 以寫明的理由拒... -> completed.md (archived 2026-10-05)

- [x] **CLOSED 2026-09-29 -- TalkBack's actual speech verified, no human listening.**
  `testapp/test_support/android_log_tts` is a TTS engine that logs every utterance
  (tag SCUI-TTS) and speaks none; as the default engine it receives everything
  TalkBack says. P69 on the api36 emulator, each element touch-explored through the
  real touchscreen device (`adb input tap` bypasses the accessibility filter):
  Close -> "Close, Button" (no "X"); Delete -> "Delete, Button. Removes the file
  permanently"; Volume -> "40 percent, Volume, Button"; the 12:30 text -> "Half past
  twelve" (12:30 not spoken, so the contentDescription override is what a reader
  uses -- the one thing this item had not heard); decorative -> nothing.
  Transcript: `testapp/measurements/talkback-p69-20260929.txt`. What remains is
  Narrator, on the Windows machine, tracked in the item above.
  **2026-09-29 關閉:TalkBack 的實際朗讀已驗證,不需要有人聽。**記錄每段朗讀的 TTS 引擎 + 真正的觸控事件;五項主張全部
  以「唸出的內容」成立。剩下的 Narrator 在 Windows 那台機器上,由上面那一項追蹤。原條目:
  **#123 複驗(2026-09-17,應 Windows 之請):我們這三個 backend 乾淨,但複驗本身找到一個更大的洞**
  - **起因**:那邊的外部 AT-SPI 探針發現 GTK 的 Close 按鈕仍把 `X` 子節點暴露出去。
  - **macOS:沒有這個問題,而且現在證得出來。** `ax_dump` 加了 `--children`,會印出每一顆具名按鈕
    **底下**有什麼:`desc='Close'`(無子節點)、`desc='Delete' help='Removes the file permanently'`
    (無子節點)、`desc='Volume' value='40 percent'`(無子節點),整棵樹裡沒有 `X`、也沒有
    `decorative`。原本那份扁平清單**不可能**顯示出子節點——同一個量測,現在被問了一個它先前答不出的問題。
  - **Android:未壓縮的 dump 確實看得到 `Button desc='Close' → … → TextView text='X'`,以及
    `decorative`。那不是缺陷**,而且原始碼早就寫著:`uiautomator` 的普通 dump 會設
    `FLAG_INCLUDE_NOT_IMPORTANT_VIEWS`,列出螢幕閱讀器永遠抵達不了的 view。`--compressed`
    ——也就是與輔助技術所走訪者相符的那一份——給的是 `Button desc='Close'` **0 個子節點**、
    `decorative` 完全不存在。兩份 dump 同一次執行取得,因此差別在旗標,不在建置。
  - **iOS:在今天之前根本沒有外部探針,而一裝上就抓到東西。** XCUITest 的 runner 現在支援
    `--dump-tree`(`test_ios.zsh`),印出的是輔助技術所走訪的同一棵樹。第一份輸出:**整支 app 只解析出
    一個 `StaticText`,而它屬於測試載具自己的 `actualView` 按鈕**;SwiftCrossUI 畫出的每一段文字都是
    沒有名字的 `Other`——**VoiceOver 對這個 backend 上任何 app 的任何文字都無話可說**。原因是
    `UIKitBackend.TextView` 以 TextKit 自行繪製,因此是普通 `UIView`、不是無障礙元素。已修:設定文字時
    一併發布 `isAccessibilityElement`/`accessibilityLabel` 並加上 `.staticText` trait,並讓
    `namedChild` 認得 `TextView`。修後:七個 `StaticText` 各自帶著自己的內容,
    Close/Delete/Volume 仍帶著名字且**沒有** `X` 子節點,`decorative` 不出現。
  - **給那邊的一條線索(GTK)**:AT-SPI **沒有** Android 那種「不重要」過濾,所以那棵樹就是 AT 走訪的樹
    ——`X` 若在裡面就是真的在裡面。GTK4 可以把內層 label 的 accessible role 設為 `NONE`/presentation,
    或對它 `gtk_accessible_update_state(... GTK_ACCESSIBLE_STATE_HIDDEN, TRUE ...)`。我這邊沒有 GTK,
    無法驗,所以這是線索不是結論。
  - **`.accessibilityLabel` 對 `Text` 的等價檢查已完成(2026-09-19,AppKit 與 Android)**,而它找到的
    不是實作缺陷、是 **P69 自己的主張寫錯了**:
    - **AppKit**:`AXStaticText 'Half past twelve' desc='Half past twelve'`,整棵樹裡沒有 `12:30`。
    - **Android**(`uiautomator --compressed`):**同一個** TextView 同時帶著 `text='12:30'` 與
      `content-desc='Half past twelve'`。
    - P69 原本的主張寫著「出現 'Half past twelve' 而**不出現** '12:30'」——那是 macOS/iOS 的形狀,
      被當成普世規則寫下。在 Android 上 `contentDescription` 是一個「閱讀器**改讀它**、而不是讀 text」
      的**覆寫**,不是替換;`12:30` 留在節點上是正確的。那段主張會把 Android 的 dump 讀成失敗,
      而當時標籤正在正確地做它的事——**最糟的一種錯誤斷言:它指著能用的程式碼。** 已改為逐平台敘述。
    - **兩邊都確認 `decorative` 不出現**(Android 上唯一的那次出現,是在 P69 自己的主張字串裡)。
  - **仍未做**:Narrator / TalkBack 的**實際朗讀**(要有人聽);Android 上「閱讀器會改讀
    contentDescription」是平台的既定行為,我沒有聽過,因此與 Narrator 那一項同列。

- [x] **M10. 一塊 GPU 表面 —— 以 three.js 為量尺,缺的是「app 自己畫」的那一層(2026-09-19,Apple 兩個 backend 已落地)**
  - **2026-10-05 由 [~] 改為 [x]:** Apple 與 Android 都已落地並驅動(M10 的 §10.7 九項都有答案)。剩下的部分各有自己的待辦:GTK / WinUI 的 `Mesh3DViews` 見本檔開頭那一項;UIKit 的 `Cursors` 見「P72 cursor on iPad」;macOS 的 `Cursors` 驗證與 Windows/Linux 的 `hover` 拆成兩項,在下方 T3 之後。
  - **完整分析在 `testapp/plan/plan-3D.md`**,依據是
    `/Volumes/LinuxCS/render/three.js`(submodule `ea56c2f4`,0.185.0)、該處的 wiki 筆記、
    `/Volumes/LinuxCS/render/metal-tools`,以及本 repo 的 `BackendFeatures/`。
  - **缺的不是一項功能,而是一整層,但它們全都等同一件事:** three.js 是「scene graph + renderer」;
    我們有 `Paths`(app 描述、backend 畫)、`Gradients`、`VisualEffects`、`GeometricEffects`
    (2D widget 上的 `CATransform3D`)、`FrameClocks`、`GraphicsAdapters`(只決定由哪張 GPU 畫 UI)。
    **沒有任何一種 view 會把「一塊可以自己畫的表面」交給 app。**
  - **證據是這棵樹自己繞過它三次**:`WinUIBackend/D3D11VideoInterop.swift`、
    `Gtk/Widgets/NV12GLView.swift`,以及 P6 在 Apple 上**每一幀**解碼成 `Image` 再交給框架
    (`testapp/P6.swift:966`)——那是每幀一次 CPU 上傳,只因為沒有表面可以放 texture。
  - **2026-09-19 更正與定案(在寫任何程式碼之前):** 「這個框架沒有表面可畫」**是錯的**——
    `/Volumes/Windows/proj_Win/SoftPCB/SoftPCB-UI` 今天就用 `NSViewRepresentable` 後面的 `MTKView`
    畫 3D 板,而**五個 backend 全部**都有逃生門(`NSViewRepresentable`、`UIViewRepresentable`、
    `AndroidViewRepresentable`、`GtkWidgetRepresentable`、`WinUIElementRepresentable`)。
    真正的代價是**可攜性**:一支 app 要為五個 backend 各寫一個 view、各 import 一個 backend。
    另外,SoftPCB `plan.md` §10.7 那張「對照原始碼查過」的九項缺口清單,**今天有四項已經關掉**
    (拖曳、縮放/旋轉、焦點、每幀時序),仍開著的是捲動、原始按鍵、游標、右鍵選單、快照。
  - **使用者定下的方向:把 renderer 升到協定層,Metal 實作先進 macOS 與 iOS backend,其餘平台後補。**
    因此提議改為 `BackendFeatures.Mesh3DViews`(`createMesh3DView` / `updateMesh3DView(scene:)`),
    SwiftCrossUI 只放與 backend 無關的值型別(`Mesh3D`、`Mesh3DVertex`、`Mesh3DCamera`、`Mesh3DScene`);
    Metal 放在新 target `SwiftCrossUIMetal`,由 AppKit 與 UIKit **共用**(`MTKView` 兩邊同一個類別),
    寫兩份正是兩個 backend 開始各說各話的起點。驗收:**P72 相隔一秒的兩張擷圖,frame count 要前進、
    立方體角度要不同**。
  - ~~**原提議的形狀:** 一個 conformance 檢查的 `BackendFeatures.GPUSurfaces`——~~
    `createGPUSurface()`、`gpuSurfaceDrawableSize()`(**像素**與 scale,不是點)、
    `setGPUSurfaceHandler()`,交回一個 `GPUSurfaceHandle` enum(`.caMetalLayer`、`.glArea`、
    `.androidSurface`、`.swapChainPanel`)。**刻意不做最小公約數 API。** 每幀驅動沿用既有的 `FrameClocks`。
  - **不做的事:把 three.js 的 scene graph 移植過來。** 那是好幾週的工作,而第一張誠實的擷圖仍然只是
    一個三角形;有了表面之後,app 可以用 SceneKit、RealityKit 或自己的 Metal renderer。
  - **第一刀與驗收:** 協定 + AppKit/UIKit(`CAMetalLayer`)+ 新的 **P72**(一塊表面、一個會轉的三角形、
    讀數含 backend / 像素尺寸 / frame count)。**判定完成的條件是相隔一秒的兩張擷圖 frame count 要前進、
    三角形角度要不同**——單獨一張三角形只證明表面存在,不證明有東西在驅動它(M9 的同一個分野)。
  - **Android 是我的,排在 Apple 之後;GTK 與 WinUI 是你們的**,而那兩個 case 從第一個 commit 起就在
    enum 裡,因此補上它們是實作、不是改協定。
  - **給你們一個問題(不是假設,我這裡建不了 WinUI):** 在 2026-09-17 那個單執行緒 apartment 啟動之下,
    XAML island 裡的 `SwapChainPanel` 行為正常嗎?若否,那個 case 可能要改成 composition surface。
  - **2026-09-19 第一刀已落地並驗過(macOS + iOS):**
    - `BackendFeatures.Mesh3DViews`(conformance 檢查)、`Mesh3DView`、`Mesh3D`、`Mesh3DVertex`、
      `Mesh3DTransform`、`Mesh3DCamera`、`Mesh3DScene`、`Mesh3DFrameInfo`。
    - 新 target **`SwiftCrossUIMetal`**:一個 `MTKView` 子類別,著色器在執行期由原始碼編譯(不放
      `.metal` 檔,因為 `Bundle.module` 的查找正是那種「在某個平台上找不到」的東西),AppKit 與
      UIKit **共用同一份**。非 Apple 主機上它整份包在 `#if canImport(MetalKit)` 裡,編成空模組。
    - **`Mesh3DTransform` 在協定層,不在 app 層。** 先前版本是 app 自己旋轉那 24 個頂點,結果 renderer
      每秒重傳 60 次幾何資料去畫同一個立方體;把變換移進 `Mesh3D` 之後,幾何只上傳一次、角度以 uniform
      傳遞,而 Android/GTK/WinUI 會**繼承**同一個自轉,不必每支 app 各自重做。
    - **P72**:立方體、相機繞 Y 公轉、mesh 在 XY 平面自轉、`Auto spin` 開關、`Stop the clock` /
      `Check again`。驗收擷圖:macOS frames 176→249、iOS 659→743,兩邊角度都不同。
    - 動作檔 **`actions/mac/P72-stop-and-check.csv`** 與 **`actions/ios/P72-stop-and-check.csv`**
      都已重放通過(AppKit 停鐘後 1 幀、UIKit 3 幀;自走的話是 90)。
  - **這一刀抓到三個「不會報錯」的缺陷,都記在程式碼裡:**
    1. `SIMD3<Float>` 的 stride 是 **16 不是 12**,`Mesh3DVertex` 因此是 48 位元組而著色器那邊是 36。
       畫出來的不是崩潰也不是空白,是一團立方體大小、被拉長、顏色漸層的三角形散射——看起來像投影矩陣壞了。
    2. `FrameClocks` 給的是**開機以來的秒數**(量到 177182)。轉成 `Float` 後精度間距 0.0156,而每幀只前進
       0.01 弧度,於是旋轉會量化成階梯。改為減去第一個時間戳。
    3. 擋住 `MTKView` 自走 60 Hz 的是 **`enableSetNeedsDisplay`,不是 `isPaused`**。這是「預期它會失敗
       而去跑、結果它沒失敗」量出來的——先刪 `isPaused` 得到 1 幀,刪 `enableSetNeedsDisplay` 才得到 90。
  - **glTF 2.0 匯出已落地(2026-09-19):** `Mesh3DScene.glbData()` 在 `SwiftCrossUI` 裡、手寫、零相依。
    驗證用的是 **three.js 自己的 `GLTFLoader`**,不是在 writer 旁邊寫的 reader——而那個選擇當場就有回報:
    GLB magic 被我寫成 `gltF`(與 `glTF` 差一個位元),長度、兩個 chunk 標頭、JSON 與 buffer 全都正確,
    因此 Swift 這一側寫的每一項檢查都通過,只有 three.js 拒絕它。驗證腳本:
    `testapp/test_support/measure/gltf_check.mjs`。
  - **§10.7 第 9 項「渲染結果匯出成圖檔」已關掉(2026-09-19):**
    `BackendFeatures.WidgetSnapshots` + `WidgetSnapshot`(RGBA8,與 `Images` 同一個格式)+ 自帶的 PNG
    編碼器(stored deflate,不需要 zlib)。AppKit 與 UIKit 各有兩條路徑:`Mesh3DMetalView` 走**離屏
    texture 重畫一幀再讀回**(不是去擷取 drawable——那個 texture 屬於一個會立刻重用它的 pool),
    其餘 widget 走 `cacheDisplay` / `layer.render(in:)`。
    **這一項關掉的是 SoftPCB `plan.md` §10.7 那張「真正的阻礙」表裡的第二列**——「`MTKView` 內部畫了
    什麼,inspection 看不到」。P72 的斷言不是視窗截圖(那不論 view 畫了什麼都會過),而是**那個 view
    自己的像素**:尺寸、相異顏色數、中心像素。兩種都量過——有立方體時 3 色、中心 222,163,45;
    `meshes: []` 時 1 色、中心 20,23,33(正好是背景色)。
  - **仍然沒做:** Android(我的)、GTK 與 WinUI(你們的)的 `Mesh3DViews` 與 `WidgetSnapshots`;
    那三個 backend 目前走 `Mesh3DView` 的降級路徑——畫一個空盒子、每個 backend 警告一次,
    而不是 `fatalError`。
  - **§10.7 第 2 項「滾輪縮放」已關掉(2026-09-19):** `BackendFeatures.ScrollGestures` +
    `ScrollGestureValue` + `.onScrollGesture`。**它不是 `ScrollContainers`**——捲動容器自己移動內容、
    應用程式看不到事件;這個把事件交出去、自己什麼都不動,那才是「自己畫自己內容」的 view 需要的。
    符號約定寫在框架裡一次(`delta.y` 為正 = 往內容的前方),不交給五個 backend 各自決定。
    採 conformance 檢查而非 `@CastBackend`(理由同 `Mesh3DViews`)。
    - **AppKit**:`NSView.scrollWheel(with:)`(AppKit 沒有捲動辨識器)。實測:五格滾輪 → 一個
      `dy 80.00`、`notched` 的事件(每行 16 點),相機 3.400 → 2.600 → 3.400。**已證明會失敗**:
      把指標移到 view 之外再捲,SCROLL 行數為**零**。
    - **UIKit**:帶 `allowedScrollTypesMask` 的 `UIPanGestureRecognizer`。**一指,不是兩指**——
      第一版寫成兩指,結果 iOS 動作檔裡每一列 scroll 都被送達然後靜默忽略;觸控螢幕上 scroll view
      是一指捲的,而這棵樹自己的 iOS runner 也正是把 scroll 轉成一指拖曳。實測:四格 → 20 個
      `precise` 事件,相機 3.400 → 1.944。
    - **UIKit 的一個誠實缺口**:`UIPanGestureRecognizer` **沒有** `scrollType`(查證過,是編譯錯誤),
      承載 `.scroll` 的 `UIEvent` 也不會交給 action 方法,因此 iOS 上 `isPrecise` 一律為 true;
      接了滑鼠的 iPad 上,一格滾輪會被誤報為 precise。AppKit 有 `hasPreciseScrollingDeltas`。
      這一點寫在程式碼裡,而不是靜默採用預設值。
  - **[!] 開著的問題:`actions/ios/P72-stop-and-check.csv` 在 iOS 上跑不完。** 啟動後只有**第一個**
    互動會落地,其後每一列都毫無作用。以三種方式查證過:座標在 `--dump-tree` 與擷圖之間一致;
    app 之後仍持續算繪(沒有卡住);調換順序會改變「哪一個動作觸發」。同一段序列在 11:21、於捲動與
    快照加入之前是跑得完的。**它不是捲動的缺陷**——`actions/ios/P72-scroll.csv`(只有捲動)通過,
    而 macOS 那份六項全過。該檔頭部已加上不會被誤讀為通過的警示。
  - **§10.7 第 4 項「原始按鍵」與第 5 項的焦點那一半已關掉(2026-09-19,macOS):**
    `BackendFeatures.KeyEvents` + `KeyPress` + `.onKeyPress`。macOS 實測全部四項:
    `KEY 1 'U+F700' shift=no step 0.1 height 1.40` / `MODIFIERS down shift=true` /
    `KEY 2 'U+F700' shift=yes step 1.0 height 2.40` / `MODIFIERS up shift=false`。
    - 重用既有的 `KeyEquivalent` 與 `EventModifiers`,不另造第二套語彙;連帶繼承其限制並寫明:
      它是**字元**而非實體按鍵,**AZERTY 上的 WASD 是 ZQSD**。
    - `KeyPress.key` 可為 `nil` = 只有修飾鍵改變。SwiftUI 沒有這個情況,而第 4 項要的正是它。
    - 焦點由 backend 在 `NSWindow.didBecomeKeyNotification` 時取得(第 5 項的一半)。
      **先前版本在 `viewDidMoveToWindow` 就搶,那時 `isKeyWindow` 是 false、`firstResponder` 是 nil,
      因此什麼都沒搶到。**
  - **我先前把這一項判成「建好、未驅動」,那是錯的,而錯在我自己的臨時動作檔。** 我寫了
    `key,,,,,up`,而合法的名稱是 `upArrow`;同時我每次都用 `>/dev/null` 丟掉重放本身的輸出,
    因此那個解析錯誤從來沒有浮出來。教訓:**丟掉重放的輸出,等於把「檔案根本沒跑」偽裝成「功能沒作用」。**
  - **這一刀在 synthesiser 裡抓到兩個真缺陷(`AppKitSynthesiser`,兩個都會靜默地騙人):**
    1. **方向鍵送達的是 U+001E,不是 U+F700。** `UCKeyTranslate` 對 `kVK_UpArrow` 回傳 ASCII 的記錄
       分隔符,而 AppKit 在任何 view 看到事件之前會換成 `NSUpArrowFunctionKey`。因此**重放的方向鍵與
       實體方向鍵是不同的鍵**:任何以方向鍵為主的測試,都會自己跟自己一致、卻跟現實不一致。
       已加 `functionKeyCharacter(for:)`,涵蓋方向鍵、F1–F20、home/end/pageUp/pageDown/forwardDelete。
    2. **修飾鍵放開時,事件仍聲稱它被按住。** `.keyUp` 是先 post 再 `release`,而 flagsChanged 帶的是
       「此刻」的狀態。於是一個「看修飾鍵切換模式」的 app 會切進去、再也切不回來。已改為先 release。
  - **另一個關於測試設備的發現:`test.zsh` 不會清掉 app 自己存的視窗尺寸。** 把 `.defaultSize` 由 660 改成
    780 之後,重放跑的仍是舊的 660(bundle id `dev.swiftcrossui.testapp.p72` 有自己的 autosave domain),
    於是每一個座標都落空。`window_sizes_mac.zsh` 記過這個陷阱,但 `test.zsh` 沒有清。
  - **UIKit 那一份仍未驅動**:用 `pressesBegan`/`pressesEnded`(不是 `UIKeyCommand`——後者回報不了鍵放開、
    也回報不了單獨按住修飾鍵),但模擬器沒有實體鍵盤,iOS runner 也還沒有 key 這個動作。
  - **§10.7 第 6 項「游標」已關掉(2026-09-20,AppKit,含侷限性):**
    `BackendFeatures.Cursors` + `Cursor`(七個 case)+ `.cursor(_:)`。AppKit 走 `NSTrackingArea` 的
    `.cursorUpdate`,**不是** `addCursorRect`——後者靠 `resetCursorRects` 重建,而 AppKit 不認為
    「尺寸以程式設定、未經視窗縮放」的 view 算失效,而這棵樹每次 commit 都在設尺寸。
    - **`Cursor` 刻意很小**:七個 case,每一個在 AppKit、GTK、WinUI、Android 上都存在。
      **沒有 `wait`**(AppKit 沒有公開的忙碌游標),**沒有 `grab`/`grabbing`**(WinUI 沒有系統形狀)。
    - **證據(`actions/mac/P72-cursor.csv`,需搭配 `screencapture -C`)**:指標在 mesh view 上 → **十字**;
      同一個視窗裡指標在純文字上 → **箭頭**。第二張才是關鍵——如果到處都是十字,第一張也會是十字。
    - **修掉一個真實的設計錯誤**:第一版也從 `mouseEntered` 與屬性 `didSet` 呼叫 `NSCursor.set()`,
      而 `set()` 是**全域**的;指標離開之後十字會留著,因為普通文字 view 不會把它改回來。
  - **順帶修好 synthesiser 的一個大洞:`move` 現在會 warp 實體指標。**
    在 2026-09-20 之前,它只送出一個給**應用程式**的合成 mouse-moved 事件,螢幕上的游標不會跟著走。
    凡是由事件流驅動的東西都能運作(hit testing、hover、拖曳),所以幾個月來沒有任何東西抗議;
    不能運作的是**讀取真實指標**的那些東西:游標形狀、`NSEvent.mouseLocation`,以及任何
    `screencapture -C`。本模組 README 早就寫著這個動作是「移動指標」。
    **`.click` 刻意仍然不 warp**:這棵樹每一份已驗證的動作檔,都是在「點擊不會動到指標」的前提下量的。
    - **我為此錯讀過一次證據並記在程式碼裡**:我看到十字出現在距離該 view 三百點外,判定「游標區域太大」,
      還據此改了 modifier 順序。正確的讀法是「滑鼠在那邊」——那張擷圖畫的是我的實體滑鼠。
  - **§10.7 第 7 項「右鍵選單」已關掉(2026-09-20,AppKit):**
    `BackendFeatures.ContextMenus` + `.contextMenu { }`。**選單是一個 `ResolvedMenu`**——與
    `PopoverMenus` 所取的同一個值,由同一個 renderer 轉成 `NSMenuItem`。第二套選單表示法,等於多一個
    地方讓 submenu / toggle / 分隔線的意思產生些微差異。
    - AppKit 那一側**只設 `NSView.menu`**:AppKit 會從被點擊的 view 往上走、逐一詢問各自的 `menu`,
      因此不需要手勢辨識器、不需要覆寫 `rightMouseDown`、也不需要自己彈出選單。
    - **斷言的是「項目有執行」,不是「選單有出現」**(`actions/mac/P72-context-menu.csv`):
      右鍵 → 下鍵 → Return → log 出現 `CONTEXT MENU reset the camera: dist 3.40 high 1.30`。
      **已證明會失敗**:把右鍵點擊移到純文字上(y 140),CONTEXT MENU 行數為**零**——那個選單屬於
      那個 view,不屬於那個視窗。
  - **UIKit 的 `Cursors` 與 `ContextMenus` 已落地(2026-09-20):**
    - **`ContextMenus` 已驗證**:`UIContextMenuInteraction`,長按叫出選單,**而且項目會執行**
      (`actions/ios/P72-context-menu.csv` → `CONTEXT MENU reset the camera: dist 3.40 high 1.30`)。
      形狀與 AppKit 不同:UIKit 先要一份 configuration、等到要呈現時才要 `UIMenu`,因此項目是在
      **呈現當下**才建立;每次都重建、不快取,否則會執行昨天那個 action。
      **兩個 backend 唯一使用者看得見的差異**:UIKit 沒有分隔線元素(分段靠巢狀 inline `UIMenu`),
      因此 `.separator` 被丟棄。
    - **`Cursors` 已實作、未驗證**:`UIPointerInteraction`。**UIKit 沒有游標集合**——查證過,iOS 27 SDK
      的形狀 case 只有 `path` / `roundedRect` / `beam` / `verticalBeam` / `horizontalBeam`,
      **沒有** `crosshair`。因此 crosshair、兩個 resize 與 notAllowed 都是**畫出來的路徑**,
      `text` → `.verticalBeam`,`pointingHand` → `.highlight` 效果。
      **驗不了的原因寫明**:iPhone 模擬器沒有指標裝置,而 `UIPointerInteraction` 沒有指標時是惰性的。
      要驗需要 iPad 模擬器加上指標,或實機加觸控板。
  - **為了驗 iOS 的右鍵選單,動作檔格式多了一個動作:`longpress`。**
    觸控螢幕上的右鍵選單是靠「按住」叫出來的,而 mousedown/mouseup 表達不了——runner 固定按壓 0.1 秒,
    不論中間夾了幾列 `sleep`(`sleep` 暫停的是重放、不是手指)。**桌面的三個 synthesiser 都會拒絕它**
    並指向 `click ... right`;一個「在三個平台上靜默變成右鍵」的動作,會藏起跨平台測試正要找的那個差異。
    `micros` 是**必填**:沒有時長的長按就是一次點擊。
  - **[!] 我先前說 `UIKitBackend+KeyEvents.swift` 編得過,那是錯的——它從來沒編過。**
    macOS 主機上的 `swift build` 不會建 UIKitBackend,而我寫完之後沒跑過 `compile.zsh -ios`。
    它在 `ContainerWidget`(一個 view **controller**)上覆寫了 `didMoveToWindow`(一個 `UIView` 的方法)。
    已改為 `viewDidAppear`,現在 iOS 建得起來。記為 **mistakes 第 10 條的第二次發生**。
  - **Android 的 `Cursors` 與 `ContextMenus` 已落地(2026-09-21):**
    - **`ContextMenus` 已驗證,而且項目會執行。** Android 有**兩種**叫出脈絡選單的方式,分屬兩個
      listener 插槽:手指長按(`View.OnLongClickListener`)、滑鼠/觸控筆次要點擊
      (`View.OnContextClickListener`)。兩個都裝上,並共用 `AttachedMenus` 本來就在建的那個
      `PopupMenu`——不另造一套選單表示法。沒有用 `registerForContextMenu`,因為它會繞經
      `Activity.onCreateContextMenu`,那個 callback 不知道是哪個 view 在問。
      **證據**:`testapp/actions/android/P72-context-menu.csv`(新的 `longpress` 動作)長按 mesh view,
      `p72-android-final-20260921-181017.png` 裡有帶著 **Reset the camera** / **Snapshot** 的彈出選單;
      接著 `adb shell input tap 254 1063` 讓 logcat 印出
      `CONTEXT MENU reset the camera: dist 3.40 high 1.30`。
      **已證明會失敗**:同一份檔案把長按移到標題文字(點 y 34),完全沒有彈出選單。
    - **為什麼按項目那一步不是動作檔的一列。** `AndroidSynthesiser.dispatch` 走
      `Activity.dispatchTouchEvent`,只抵達本 activity 的視窗;`PopupMenu` 是 WindowManager 持有的
      **另一個視窗**。這正是 P2/P17/P19/P20 都在一次點擊後停住的同一個限制
      (`AndroidSynthesiser.swift:566` 已寫明)。因此那一步改用 `adb shell input tap` 在系統層級注入。
    - **`longpress` 現在在 Android 上是真的按住。** Android 不從事件裡讀時長:`View.onTouchEvent` 在
      ACTION_DOWN 時 post 一個 `CheckForLongPress`、在 ACTION_UP 時取消它,所以兩個背靠背投遞、
      `eventTime` 相差 500 毫秒的事件就只是一次點擊。睡眠留在重放執行緒上,好讓主執行緒有空跑那個
      runnable。
    - **`Cursors` 已實作、未驗證,而這次「未驗證」是可以指出原因的。** `View.setPointerIcon` +
      `PointerIcon.getSystemIcon`,七個 case 全部對應真正的系統圖示(`TYPE_NO_DROP` 是禁止圈,
      兩個縮放用雙向箭頭)。**這個 AVD 根本沒有指標裝置**:`dumpsys input` 的 Event Hub 只有
      `gpio-keys` 與十二個 `virtio_input_multi_touch_*`,`MousePointerControllers` 是空的,
      而三次以 `uinput` 註冊虛擬滑鼠(root 與 shell 各試)都沒有產生裝置。沒有 `PointerController`
      就沒有 sprite 可畫。**能驗的已經驗了**:conformance 確實被採用——`CursorDegradation` 的警告從
      logcat 消失,而 `Mesh3DViews` / `ScrollGestures` / `KeyEvents` 的警告仍在。
      要看到十字,需要一台帶真滑鼠的裝置或模擬器。
  - **[!] Android 的整個 `SwiftCrossUI` 核心,從 M10 落地那天起就沒有編過。**
    `Sources/SwiftCrossUI/Views/Mesh3DExport.swift` 在 `SIMD3<Float>` 上呼叫 `sin(euler.x / 2)`。
    Darwin 的數學模組有 `Float` 多載,Bionic 的 `math.h` 只有 `sin(double)` 與 `sinf(float)`——
    於是 Android 上連 `/` 是什麼意思都定不下來,一次六個錯誤;`testapp/P72.swift` 的相機環繞也同一行。
    那不是 backend 的檔案,是**每個平台都連結的核心**,因此 macOS 與 iOS 全綠的那幾天裡,
    Android 一個二進位都產不出來。已改為以 `Double` 運算再轉回 `Float`(不需要 `#if`)。
    記為 **mistakes 第 24 條**,也是本樹第一次記下 `mistakes_prevention` 的**關口 4**。
    **2026-09-23:它現在有一道自動關卡,不再只是一條寫下來的規則。**
    `Scripts/check_android_build.sh`(已接入 `Scripts/test.sh`)會在「與 `origin/develop` 的差異觸及
    `Package.swift`、或觸及任何一個不屬於非 Android 平台 backend 的 `Sources/` 目錄」時,為 Android
    編譯一次。用**排除**清單而非納入清單,好讓新的 target 會觸發、而不是溜過去。
    **無相關改動時 0.25 秒,真的要跑時 73 秒。** 已雙向證明:把 `sin(euler.x)` 放回
    `Mesh3DMatrix.swift` → 以 1 結束並指出那一行;改回來 → 真的編過之後以 0 結束。
    找不到 SDK 時是**大聲的**跳過並仍以 0 結束(不擋住沒有 SDK 的人,也不讓沉默被讀成「Android 沒問題」)。
    修好之後已重跑 macOS 的 `actions/mac/P72-stop-and-check.csv`:十項斷言全數重現,
    `.glb` 仍通過 three.js 的 `GLTFLoader`(2356 bytes,node euler z 1.0829 rad)。
  - **Android 的 `ScrollGestures`、`KeyEvents`、`WidgetSnapshots` 已落地並驅動過(2026-09-22):**
    - **`ScrollGestures` 已驗證。** 一個屬於本 modifier 自己的 `ViewGroup`,同時覆寫 `onTouchEvent`
      (單指,與 UIKit 同樣的選擇,因為 runner 用一根手指拖曳)與 `onGenericMotionEvent`
      (真正的 `ACTION_SCROLL` 滾輪,因此 `isPrecise` 在此處**真的**分得出兩種裝置——AppKit 可以,
      UIKit 不行)。不用 listener 的理由是算術:一個 `View` 只有一個 `OnTouchListener` 插槽,
      而 `ButtonPressState` 與 `.onTapGesture(.secondary)` 已經在搶它。
      **證據**:`actions/android/P72-scroll-and-keys.csv` —— 16 次各 10 點的 `onChange`,
      把相機距離帶到 3.400 → 2.600 → 3.400,與 macOS 兩次各 80 點的端點完全相同。
      **已證明會失敗**:同樣幾列移到標題文字上,SCROLL 行數為零。
    - **[x] 已修(2026-09-23):Android 的 `DragGestureValue` 原本回報像素,而協定寫的是點。**
      `ContinuousGestureContainer` 把 `event.x` 原樣交出去,而 AndroidBackend 的排版是「點乘上
      density」(P72 的 340×240 點量到 892×630 像素)。在 density 2.625 的裝置上,一次拖曳回報的距離
      大了 2.625 倍;換一台裝置就是另一個錯數字。新的 scroll 容器有做除法,舊的三個手勢沒有。
      已在 `ContinuousGestureContainer` 裡除以 density,並以新的 `actions/android/P65-drag.csv` **雙向證明**:有換算時 `translation (80, 0)`,把換算拿掉重建 APK 之後是 `translation (210, 0)`——也就是 80 × 2.625。縮放與旋轉不需要動:一個是兩個 span 的比值、一個是角度,單位都約掉了。同時掃過其餘 Kotlin:`CustomSlider` 比的是像素對像素的 touch slop(正確),`HoverContainer` 不回報座標,`ScrollGestureContainer` 從第一行就有換算。
    - **`KeyEvents` 已驗證,而且它逼出了第二項工作。** 一個可聚焦的容器覆寫 `dispatchKeyEvent`,
      `super` **先**跑(持有焦點的文字欄位保有自己的按鍵),而且回傳 `false`(不吞掉 Back 與 Tab)。
      `onKeyDown`/`onKeyUp` 不夠用:Shift 在抵達它們之前就被框架的 meta-state 追蹤吃掉了,於是
      「只有修飾鍵改變」永遠不會送達。`KEYCODE_DPAD_UP` 對到 `U+F700`——`KeyEquivalent.upArrow`
      本來就用的那個 scalar——因此 `press.key == .upArrow` 在兩個平台上都成立。
      **第二項工作**:`AndroidSynthesiser` 原本整個拒絕按鍵列,現在有了 ``Key`` → keycode 的對照表
      與「被按住的修飾鍵」追蹤;F13–F20 是**逐一具名**拒絕(`android.view.KeyEvent` 停在 F12),
      而不是整個動作一起拒絕——已實測:`key,,,,,f13` 讓重放以
      `key 'f13' on Android: android.view.KeyEvent has no keycode for it` 失敗。
      **產出的行與 macOS 逐字相同**:`KEY 1 'U+F700' shift=no step 0.1 height 1.40`、
      `MODIFIERS down shift=true`、`KEY 2 'U+F700' shift=yes step 1.0 height 2.40`、
      `MODIFIERS up shift=false`。**最後那一行第一次跑出來是 `shift=true`**——修飾鍵的位元在事件
      建好之後才移除。AppKitSynthesiser 在 2026-09-19 有一模一樣的缺陷,修法也一模一樣。
    - **`WidgetSnapshots` 已驗證。** `View.draw(Canvas)` 畫進一張軟體 `ARGB_8888` Bitmap,再
      `copyPixelsToBuffer` 進一個 heap `ByteBuffer` 並取 `array()`——整張圖一次 JNI 呼叫,
      而不是 326,400 次。不用 `getDrawingCache`(自 API 28 起棄用,且回傳的是上一次的合成結果)。
      **證據**:`actions/android/P72-snapshot.csv` —— `SNAPSHOT 892x630 px`(340×240 點 × 2.625)、
      1 種顏色(Android 還沒有 `Mesh3DViews`,那個 widget 就是一個空盒子——那是一張**真實的**
      空盒子快照)。從裝置拉回來的 PNG 經 `file` 與 `sips` 判讀為合法的 892×630 8-bit RGBA。
    - **[!] 那一項需要先修兩個東西,而兩個都會說謊。** (1) `Mesh3DView` 把 snapshotter 綁在
      「只有實作了 `Mesh3DViews` 才會走」的路徑裡,於是一個「有 `WidgetSnapshots`、沒有
      `Mesh3DViews`」的 backend 會印出 `SNAPSHOT UNAVAILABLE -- no WidgetSnapshots conformance`
      ——一句錯話,而且從 app 這一側看不出來。綁定已移到 `commit`。
      (2) P72 的輸出目錄在 `#else` 分支用行程的當前目錄,而 Android 上那是 `/`(唯讀)。
      快照本身成功了,寫檔以 `Code=642 "The volume is read only."` 失敗——那次失敗很大聲,
      也是它沒有被讀成「快照壞了」的唯一原因。Android 改用 `NSTemporaryDirectory()`。
  - **Android 的 `Mesh3DViews` 已落地並驅動過(2026-09-22)——M10 在 Android 上收尾:**
    - **一個 `GLSurfaceView` 加 OpenGL ES 2.0,而 fragment shader 是 Metal 那一份的音譯。**
      同一個 Lambert、同一個 0.25 環境光;常數保持一致,才不會讓差異以「Android 的立方體比較暗」
      這種無從指認的形式出現。
    - **`RENDERMODE_WHEN_DIRTY` 是承重的那一行。** 預設是 `RENDERMODE_CONTINUOUSLY`——不論發生什麼、
      每秒約六十幀——而那**正是** P72 存在所要偵測的「自走 renderer」。
      **證據**:`actions/android/P72-stop-and-check.csv` —— `STOPPED at frame 6`、
      `CHECK at frame 9, 3 since the stop`。一個自走的 view 在那 1.5 秒裡會畫約九十幀;三幀是 UIKit
      給出的同一個數字。`renderer` 讀作 `Android Emulator OpenGL ES Translator (ANGLE ... SwiftShader)`,
      `drawable 892 x 630 px`。
    - **矩陣不再是逐 backend 各寫一份。** `Mesh3DMatrix4`(`SwiftCrossUI/Views/Mesh3DMatrix.swift`)
      現在帶著 model / rotation / lookAt / perspective,而**兩個** renderer 都用它;深度範圍是一個
      參數(Metal 用 `.zeroToOne`、GL 用 `.minusOneToOne`),因為那是兩個 API 真正不同的唯一一件事。
      原本那四個函式是 `Mesh3DMetalView` 的私有函式,各自帶著一段「它選了哪個慣例」的註解——再寫一組,
      就是多四次選錯的機會。已重驗:macOS 的 `P72-stop-and-check.csv` 十項斷言全數重現,
      snapshot 的中心像素仍是 13,35,61,`.glb` 仍通過 three.js。
    - **快照必須為它多開一條路,而且是**必須**。** `GLSurfaceView` 是 `SurfaceView`:
      `View.draw(Canvas)` 會忠實地畫出它在版面上挖的那個**洞**,回傳一個空盒子而不是失敗。
      `snapshotWidget` 因此先檢查 mesh view,並向它要一次在 GL 執行緒上的 `glReadPixels`,
      再把 OpenGL 由下而上的列翻成本套件的由上而下——與 AppKitBackend 讓 `cacheDisplay` 遠離 `MTKView`
      是同一個結構。
    - **穩定的斷言是顏色**數**,不是中心像素。** Android:`SNAPSHOT 892x630 px, 4 distinct colours`;
      而「4 種顏色」正是「讀到 GL 表面」與「讀到 SurfaceView 挖的那個洞」(只有 1 種顏色)的分野。
      **中心像素不寫進動作檔,而我差點寫了。** 有一次執行,Android 與 macOS 都回報 `13,35,61`
      ——那是 0.20/0.55/0.95 各乘上 0.25 環境光,也就是未被照亮的藍色面;它是「兩個 renderer 的著色
      常數一致」的證據。但它**不穩定**:相機在繞行,哪一面落在中心取決於當下那一刻;同一份檔案稍後
      再跑一次,讀到的是 `169,124,34`(橘色面)。
      從裝置拉回來的 PNG 是一張合法的 892×630 RGBA,畫的是一個有明暗的立方體。
    - **`actions/android/P72-snapshot.csv` 已刪除。** 它是在 renderer 落地**之前**寫的:座標是舊版面的
      (renderer 字串會折成五行,把下方控制項推下約 100 點),而它期待的結果是「1 種顏色的空盒子」。
      兩者都已不成立,而 `P72-stop-and-check.csv` 對真正的 GL 表面斷言同一顆按鈕,嚴格更強。
    - **量測附記:本 app 不能用 `uiautomator dump` 來量。** 它回報
      `ERROR: could not get idle state`——那個 frame clock 從不讓視窗進入 idle。
      對本處任何一支會動的測試 app 都適用。
  - **動作檔多了一個動作:`hover`,而它是「游標」那一項唯一的量測方式(2026-09-22)。**
    它移動**真實**指標,然後印出**平台**回報的游標:`-actionfile: cursor at (x, y) is <name>`。
    macOS 讀 `NSCursor.currentSystem`;Android 投遞一個來自 SOURCE_MOUSE 的 ACTION_HOVER_MOVE、
    再讀 `View.onResolvePointerIcon`。**第二列才是斷言**:一列在 view 內、一列在 view 外,
    那是「游標有沒有被侷限在提出要求的那個 view」的唯一檢驗方式,而任何擷圖都顯示不出這件事。
    - **[!] macOS 仍然未驗證,而且我一度回報成已驗證——那是錯的。** 有一次執行給出
      「view 內 crosshair、view 外 arrow」,我據此把它寫成通過。**原封不動連跑三次**的結果是
      (arrow, crosshair)、(arrow, arrow)、(crosshair, arrow)——三次三個樣。
    - **2026-09-23:飄的問題解決了,而答案變成一個**可重現的否定**。** 找到並處理了三個成因:
      (1) 讀數原本是用**固定時間**等一個非同步效果,現在改為等一個**訊號**(游標改變),
      並把「始終沒改變」的列標記為 `unchanged after Nms`,而不是印出過期值;
      (2) `NSCursorTarget` 的 tracking area 是 `.activeInKeyWindow`——只要有東西搶走 key 狀態,
      AppKit 就**完全不送** `cursorUpdate`,因此該動作現在會先要求 key 狀態;
      (3) 那份檔案的座標是過期的(**又一次 mistakes 第 22 條**):量自 520x780 的視窗,
      而 harness 底下的 content view 是 421x705,mesh view 在 client (0,346 340x240)。
      三者都處理之後,**三次執行完全一致**——一致同意的是:**兩個位置都是 `arrow (unchanged)`**。
      也就是說在 harness 之下那個游標根本沒有改變。那是一個比出發時更窄的問題。
    - **2026-09-23:加了儀器,六個候選被量測排除,而問題仍未解。** `NSCursorTarget` 現在會印出
      `-cursor:` 行(以 `DebugFeatures.isEnabled` 為條件,與 `-hittest:` 完全一致),它回答了讀數
      回答不了的那個問題:**`cursorUpdate` 一次都沒有被呼叫**。已排除:讀數時序、讀哪個屬性、
      座標(`NSEvent.mouseLocation` 確認指標落在 AppKit y 511,而目標佔 391..631)、
      啟用狀態(`app active=true window key=true`)、tracking area 的存在與尺寸(bounds 0,0,340,240)、
      以及「它在視窗成為 key 之前註冊」(現已在 `didBecomeKeyNotification` 重新註冊,log 同時看得到
      `key=false` 與 `key=true` 兩次重建)。事件來源也換過:從 `CGWarpMouseCursorPosition`
      (不產生事件,因此本來就永遠不可能奏效)換成投遞到 `.cghidEventTap` 的真正 `CGEvent`
      ——**必要而不充分**。
      **2026-09-25 再排除三個,剩一個。** (7) 不是 hit-test 路徑:一次執行的 30,168 行 `-hittest:`
      全部落在固定的六個點上,沒有一個是指標所在之處——AppKit 根本沒在指標位置做 hit test。
      (8) 不是遮擋:在執行**當中**向 window server 取樣,P72 的視窗在 (700, 75, 520, 808)、
      hover 點在它裡面,排在它前面的只有 Window Server 與 Dock。
      (9) 不是 `NSWindow.acceptsMouseMovedEvents`:預設 false 而 tracking area 不會替你開它,
      所以這是真候選;設成 true 之後沒有變化。
      **唯一還站著的候選是巢狀結構**:P72 先套 `.cursor` 再套 `.contextMenu`,因此 `NSCursorTarget`
      是 `NSContextMenuTarget` 的**子 view**。把那兩行對調,一次執行就能回答,而那還沒試過。
      **追這件事做了三個改動,沒有一個讓症狀改變**——`mouseExited` 還原箭頭、tracking area 在
      `didBecomeKeyNotification` 重新註冊、設定 `acceptsMouseMovedEvents`。三者在構造上都是對的,
      而也**只**基於這個理由被保留;那比平常更弱,因此在檔頭與此處都明說。
    - **量測本身另外踩了兩個坑,寫在 `AppKitSynthesiser` 裡。** `NSCursor.current` 是**應用程式**的
      堆疊、而且是黏著的(離開 view 時沒有東西彈掉它);而 `NSCursor.currentSystem` 交回的是一份
      **複本**,識別比對一律失敗,因此改以熱點與影像尺寸比對(兩者相同時如實回報
      `one of arrow/notAllowed`,而不是挑一個)。
    - **`NSCursorTarget` 還是加了 `mouseExited` 還原 `.arrow`,但那是**推論**、不是量測。**
      理由是構造上的:`NSCursor.set` 是一次沒有堆疊可彈的全域指派,`cursorUpdate` 只在指標位於
      tracking area 內時才送達,而這支 app 裡沒有別的東西會設定游標——因此**不存在**任何能把箭頭放回去
      的程式路徑。AppKit 真正會做的那個還原屬於 cursor rect 那套機制,而本類別刻意不用它。
      這個分別有寫進該檔:推論出來的,與量出來的,不是同一件事。
    - **Android 已驗證,而且完全不需要指標裝置。** `View.onResolvePointerIcon` 是公開的,
      而那正是 Android 自己用來決定的方法;`ViewGroup` 的實作會往下 hit-test,因此它同時檢驗了**區域**。
      結果:mesh view 上 `crosshair`,標題文字上 `none`(null,代表「此處沒有 view 認領圖示」)。
    - **UIKit 仍是未驅動,而理由現在是精確的。** 需要兩樣東西,這台主機兩樣都沒有:一個指標裝置
      (`xcrun simctl ui` 沒有指標選項;Simulator 的「Send Pointer to Device」是選單項目,
      三次探查都找不到對應的偏好鍵),以及一個「向平台詢問它會顯示什麼」的查詢——**iOS 沒有**。
      整個決定都住在由 app 提供的 `UIPointerInteractionDelegate` 裡,去呼叫它等於自己問自己。
      要驗它需要什麼,寫在 `UIKitBackend+Cursors.swift` 的開頭:一台 iPad(或由人手動開啟
      Send Pointer to Device 的 iPad 模擬器)、把指標移到 mesh view 上,然後
      `xcrun simctl io <device> screenshot`——iPadOS 會把自己的指標畫進 frame buffer。
    - **Windows 與 Linux 的 `hover` 尚未實作,且是具名拒絕。** 各自該用的 API 寫在拒絕訊息裡:
      Win32 是 `SetCursorPos` 加 `GetCursorInfo`(把 `hCursor` 與 `LoadCursorW(nil, IDC_*)` 比對),
      X11 是 `xdotool mousemove` 加 `XFixesGetCursorImage`。
  - **UIKit 的 `KeyEvents` 已驅動(2026-09-22),而它一跑就抓到一個缺陷。**
    `actions/ios/P72-keys.csv` **完全沒有座標**:backend 自己會取得 first responder,因此經由模擬器
    實體鍵盤的 `typeKey` 就夠了;那也順帶避開了 iOS 上「啟動後只有第一次座標互動會生效」那個未解問題。
    - **第一次執行印出 `keys: 2 ... high 1.30`,而且 `last U`。** UIKit 的
      `charactersIgnoringModifiers` 對方向鍵回傳的是 `UIKeyCommand.inputUpArrow`——一個十八字元的
      字串 `"UIKeyInputUpArrow"`;取它的第一個字元就是字母 `U`,而那是**另一個鍵**的合法
      `KeyEquivalent`。於是 app 的 switch 落到 `default`:按鍵計數上升、相機不動,而沒有任何東西回報。
      具名按鍵現已改由 `UIKey.keyCode`(HID usage)對照到 AppKit 與 AndroidBackend 所用的同一組
      私有使用區 scalar。
    - **第二次執行接著抓到 `MODIFIERS up shift=true`** ——mistakes 第 25 條的第三次發生。
      這一次不在 synthesiser 裡:Shift 的 `pressesEnded` 上,`UIKey.modifierFlags` **確實**仍含有
      `.shift`,因此必須由 backend 自己減掉。
    - 兩個都修好之後,iOS 印出的四行與 macOS、Android **逐字相同**。
  - **SoftPCB §10.7 全部九項到此都有了答案。** 其中 macOS 上做完並驗過的是:拖曳、縮放/旋轉、焦點、
    每幀時序、捲動、原始按鍵、游標、右鍵選單、快照。**仍欠的**:GTK / WinUI 的 `Mesh3DViews`、
    `WidgetSnapshots`、`ScrollGestures`、`KeyEvents`、`Cursors` 與 `ContextMenus`(那是你們的);
    **UIKit 的 `Cursors`** 仍未被驅動(理由見上:iOS 沒有對應的查詢,這台主機也沒有指標裝置);
    **macOS 的 `Cursors` 仍未驗證**——不是因為缺路徑,而是因為 `hover` 在 macOS 上的讀數有競爭條件,
    那是一項獨立的待辦。Windows 與 Linux 的 `hover` 動作尚未實作(拒絕訊息裡寫了各自該用的 API)。
    **Android 這一側的 M10 與 §10.7 到此全部關閉。iOS 只剩游標,macOS 只剩游標的量測同步。**

## 為什麼缺陷排在功能之前 / Why the defects moved above the features

**上面八項是使用者在一個已發布的 backend 上親眼看到的。** 一個缺席的 API 不會讓人在畫面前困惑;
一個「按了沒反應的按鈕」會,而且它會讓人懷疑其餘每一樣東西。`DocumentGroup` 從第 3 位掉到第 9 位,
不是因為它變得不重要,而是因為它從來不曾造成任何人的困惑。

**其中的順序也不是照回報順序。** 前四項各自只有一個症狀、可重現、而且看得出對錯;第 5 項(P28 的
延遲)排在它們之後,是因為「大約一秒」是一次觀察而不是一個量測——CLAUDE.md 的關卡二明說單一樣本
不足以下結論。第 6 項是設計決定,需要你;第 7、8 兩項在盤點完成之前,連規模都還不知道。

The eight above were seen by a person using a shipped backend. A missing API does
not confuse anyone in front of a screen; a button that does nothing does, and it
casts doubt on everything else. Ordering inside them is not the order they were
reported: the first four each have one reproducible symptom, the latency one
needs a measurement before a cause, the multi-file one is a decision, and the
last two do not have a known size yet.

- [x] **T3. AndroidBackend 已遷到 Swift 6 language mode(2026-09-16)** — 五個並行性問題修好並保留:stdi... -> completed.md (archived 2026-10-05)
- [x] **macOS `Cursors`:驗證(由 M10 拆出,2026-10-05)。** 已實作;未驗證的原因是 `hover` 在 macOS 上的讀數有競爭條件(見 M10 的「游標」段)。要的是一份不靠那個讀數也站得住的量測。
  - **2026-10-05 結案——其實 2026-09-27 就已完成(`1fea7901` "The macOS cursor works"),我拆出這一項時依據的是 M10 裡 9/23、9/25 的舊段落,沒有查最新紀錄。** 真正的兩個原因當時已找到並修好：座標是照「相對於父 view」的 frame 量的，以及 `hover` 等待時沒有把排隊的事件交給 `sendEvent`。今天重跑 `actions/mac/P72-cursor.csv`,用不依賴 hover 讀數的證據確認:`NSCursorTarget` 自己的 `-cursor:` 行顯示指標在 340x240 的 mesh view 內時 `cursorUpdate ... -> set`(34 次),移出時 `mouseExited`;讀數也一致——(239,284) crosshair、(239,124) arrow。
- [ ] **Windows 與 Linux 的 `hover` 動作(由 M10 拆出,2026-10-05)。** 目前是具名拒絕,各自該用的 API 寫在拒絕訊息裡;要在那兩台機器上實作並驅動。
- [ ] **WinUI:`frameClockToken?.dispose()` 真的取消訂閱了嗎(由背景段落拆出,2026-10-05)。** 設計上對,但從沒量過:P64 繞過 `AnimationDriver`。實驗很便宜:start → stop → 再 start,量第二段速率——仍約 141 Hz 表示取消有效,約 283 Hz 表示第一次訂閱洩漏、每次動畫再洩漏一次。原文在 completed.md「減少不必要的重繪」一節。Windows 那台機器上做。
- [x] **T4. #121 step 2 — 與 Windows 撞了同一個功能,採用他們的設計** — 合併時才發現兩邊都實作了 `.keyboardShortcut(_:modifiers:)`:**檔案不同,所以 git 沒報衝突,是編譯器報的**(`invalid redeclaration`)。他們走 **environment**(`environment(\.keyboardShortcut, …)`),而且**已在 GTK 與 WinUI 兩個 backend 上驗過**;我走的是「在 `ResolvedMenu.Item.button` 上加第三個 associated value」,只在 AppKit 驗過。**留他們的**——一個功能兩套機制比其中任何一套都糟,而他們那套已經有兩個 backend 在讀。我的 `ResolvedMenu`/`MenuItem`/`Menu.resolve` 改動與那個 modifier 全部還原,AppKit 與 Android 改讀 `environment.keyboardShortcut`。**AppKit 以 actionfile 重新驗過**(`actions/mac/P71-shortcuts.csv`,選單全程關著):`plain 1、shifted 1、disabled 0`。Android **已驗證(2026-09-23)**,三項斷言全中、含那個已停用的項目:Ctrl-S 觸發 PLAIN、Ctrl-Shift-E 觸發 SHIFTED、Ctrl-D 在已停用項目上什麼也沒觸發。**是 Ctrl 不是 Command**,而那正是 `EventModifiers.command` 那條慣例從驅動端看過去的樣子。**但它驅動不了**——`AndroidSynthesiser` 經由 `Activity.dispatchKeyEvent` 投遞,那抵達得了 view 階層(P72 的 `.onKeyPress` 就是這樣被驅動的),而 app 選單快捷鍵住在 `View.OnUnhandledKeyEventListener`,由 `ViewRootImpl` 在任何 app 投遞得到的層級**之上**執行。成對的證據才是這項發現:動作檔把 21 個動作全部重放完成而計數器停在 0/0/0,同一個 Ctrl-S 改用 `adb shell input keycombination -t 120 113 47` 就觸發了。與觸控側的 `PopupMenu` 限制同族。**[x] 2026-09-25 已解決:動作檔現在驅動得了它。** 見下方。原文保留:**繞過去的辦法試過了,被拒絕。** `Instrumentation.sendKeySync` 是公開 API、經由 `InputManager` 注入,會像鍵盤一樣從 `ViewRootImpl` 進入;而 `InputDispatcher` 的權限檢查對「uid 持有聚焦視窗」的注入者是豁免的,一次重放正是如此。建好、接在 activity 路徑之前、實際執行:**七次全數被拒**,`SecurityException: Injecting input events requires the caller ... INJECT_EVENTS permission`。那個權限在豁免被觸及之前就檢查了——因此這個限制是「一個應用程式持有不了的權限」,不是「少想到一個辦法」。那段程式碼已移除(一條在每個受支援組態下都被拒的路徑,只會在每一列按鍵上輸出日誌);移除後已重驗 P72 的按鍵列,結果不變。**解法(2026-09-25)**:要找到的是**兩**件事,而第二件才是關鍵。(1) 那些快捷鍵住在 decor view 的 `OnUnhandledKeyEventListener` 上,而 `ViewRootImpl` 在任何 app 投遞得到的層級之上執行它。(2) **一個按鍵事件跟著焦點鏈走**——`ViewGroup.dispatchKeyEvent` 只派給 `mFocused` 或自己,否則直接回傳 false;它**不會**走訪子節點。P71 沒有聚焦任何東西,所以 decor 的 `mFocused` 是 null,它底下沒有任何 view 看到過那個按鍵。第二件是靠「對 `ShortcutHostLayout` 加儀器、而它在 21 個重放動作之間一行都沒印」量出來的——在那之前我改了兩次都是猜的。現在 `ShortcutHostLayout` 就是視窗的 content view:它在 `super.dispatchKeyEvent` 拒絕之後查同一張表(與「unhandled」是同一個時刻,只是低一層),並以 `FOCUS_AFTER_DESCENDANTS` 取得焦點,因此只在沒有別的東西要焦點時才持有它。**結果**:`PLAIN 1、SHIFTED 1、DISABLED 0`。**兩項回歸都查過**:不會觸發兩次(本檔跑完 PLAIN=1 後,再送一次系統層級 Ctrl-S 變成 2、不是 3);焦點仍然正常(同版本的 P70 回報 `focused field: name`、`focus changes heard: 1`,文字欄位贏過根節點)。P72 的按鍵列不變。**UIKit 是缺口**,並在原地寫明理由:`UIAction` 收 closure 帶不了按鍵,`UIKeyCommand` 帶得了按鍵卻收 selector、經 responder chain 派送。**測試 app 是新的 P71**,它斷言計數器而非選單外觀——每個 backend 都畫得出「⌘S」,而那樣的截圖與能用的一模一樣。
  - **2026-10-05 由 [~] 改為 [x]:** 上文已寫明 2026-09-25 解決:`ShortcutHostLayout` 成為 content view,動作檔驅動得了 Android 的選單快捷鍵;AppKit 與 Android 都讀 `environment.keyboardShortcut`。沒有剩下的部分。
- [x] **4. #121 鍵盤快捷鍵 — 五個 backend 全數完成(2026-09-16 傍晚由原始碼查得)** — UIKit 那一格已由 Mac 補上(`U... -> completed.md (archived 2026-10-05)
- [x] **5. focus / accessibility(#122 / #123)— 五個 backend 全數完成** — GTK 與 WinUI 於 2026-... -> completed.md (archived 2026-10-05)
- [x] **6. #74 `-GPU` on macOS — 已實作(AppKit + UIKit)** — 那個「設計問題」其實已被協定的形狀回答了:`Graphic... -> completed.md (archived 2026-10-05)
- [x] **7. #28 動畫 / #32 手勢** — 五個 backend 全部 conform(`DragGestures`/`MagnifyGestures`/... -> completed.md (archived 2026-10-05)
- [x] **8. #117 phase 3 — 五個 backend 都有 `LazyListRows`;缺的換成 `LazyListRowLifetimes`,而且是在你們那三個** — **GTK 的 `LazyListRows` 早就完成**(`5739d453`):它是由 `LazyListRowLifetimes` **繼承**而來的,因此任何「找具名 extension」的掃描都會說它沒有——那正是這一條原本寫錯的原因。**[!] 這一句在 2026-09-23 之前一直是錯的,而我差點照它再做一次。** 它原本寫著「`LazyListRowLifetimes` 只有 GTK 與 WinUI 有,AppKit / UIKit / Android 沒有」。那在 `24319bd6` 之後就不成立了——那個 commit 的標題就是「LazyListRowLifetimes on the three backends that only had LazyListRows」,而三個 conformance 都在:`AppKitBackend+LazyListRows.swift:49`、`UIKitBackend+LazyListRows.swift:40`、`AndroidBackend+LazyListRows.swift:158`。我根據這一句把它推薦為「下一件最大的事」,而接住它的是 `grep`,不是這份文件——**mistakes 第 13 條的第二次發生**。**真正還缺的是驅動,不是實作**:macOS 已驅動且通過(`actions/mac/P57-scroll-the-whole-list.csv`,讀數 19 而不是 ~500);iOS **2026-09-27 已驅動且通過**(`actions/ios/P57-walk-the-list.csv`,建過/持有 1734 / 8,啟動時 1 / 1;先前每一次拖曳都從視窗中心、也就是清單上方的文字開始,什麼都沒推動——在重放當下拍照證實——加了一列 `move 200,810` 到清單上才解決;原本寫的「三十列 scroll 完全沒有移動那個清單」是真的,但成因不是一格的大小);Android **建了、且在小尺度上觀察到釋放**(兩列,而那個模擬器上大約只放得下兩列)。iOS 與 Android 的共同阻礙都是「清單沒有被捲動」。**2026-09-27 更正:**那**不是**與 `actions/ios/P72-stop-and-check.csv` 同一族的問題——那一個是 `RootScrollHost` 在第一次觸控時移動版面(已修),這一個在 iOS 上是拖曳沒有落在清單上(已修)。Android 那一半仍待查,而不應假設它是這兩者之一。WinUI 那份以對照組量過:掃 5000 列,有釋放 146/150 MB、扣住回呼 221/222 MB。原文保留:WinUI / AppKit / UIKit / Android 都 conform `LazyListRows` 並量過(AppKit 423→104 MB、UIKit 449→170、Android 385→92)。**GTK 目前只 conform `LazyListRowLifetimes`**(回收那一半),`LazyListRows` 尚未;Windows 標為 active。那句「400 列 114 MB、10,000 列 423 MB」是**修好之前**的數字,留在此處會讀成現況。
  - **2026-10-05 由 [~] 改為 [x]:** Android 那一半已驗證:2026-10-05 的 Android 全部重跑中 P57 走完清單,rows built / held 為 409 / 2 與 391 / 2(10-04 為 403 / 2)——清單有被捲動、列有被釋放。五個 backend 都有 `LazyListRows` 與 `LazyListRowLifetimes`,沒有剩下的部分。
  - **上面那一條自己前後矛盾,而後半段是錯的(2026-09-16 查證,型別系統就是證據)。** 它開頭說
    「GTK 的 `LazyListRows` 早就完成,是由 `LazyListRowLifetimes` **繼承**而來」——**這是對的**;
    結尾卻又說「GTK 目前只 conform `LazyListRowLifetimes`,`LazyListRows` 尚未」。兩句不可能同時
    成立。`Sources/SwiftCrossUI/Backend/BackendFeatures/Containers/LazyListRows.swift:5` 寫的是
    `public protocol LazyListRowLifetimes: LazyListRows`,而
    `Sources/GtkBackend/GtkBackend+LazyListRows.swift:4` 宣告
    `extension GtkBackend: BackendFeatures.LazyListRowLifetimes` —— **編譯器不可能讓它只滿足一半**,
    否則那個 extension 根本編不過。所以 **GTK 兩者都有**,Windows 這一側的 #117 phase 3 沒有缺口。
  - 錯的那半句留在原處,因為它示範的正是這一條開頭已經點名的那個陷阱:**「找具名 extension」的掃描
    看不見繼承而來的 conformance**。同一條目裡先寫對、再照著錯的方式重述一次,說明光是把陷阱寫下來
    並不足以擋住它。
- [x] **9. #79 GTK 39px / #109 popover anchor API — 兩項都已定案並落地(2026-09-16),此條為重複指標,一併關閉... -> completed.md (archived 2026-10-05)
- [x] **10. #80 P42 縮放通知 — WinUI 通過;GTK 值與執行期變更皆已完成並驅動驗收(2026-09-16,`cd90458e`)** — 需要... -> completed.md (archived 2026-10-05)
- [x] `SceneStorage`(P59)、`Settings` scene(P60)—— 即 Windows 表的 #35 前兩項 -> completed.md (archived 2026-10-05)
- [x] #117 phase 2 / 4a / 5:五個 backend 的 list viewport -> completed.md (archived 2026-10-05)
- [x] Review 4:兩個 ScrollViewReader,AppKit 與 Android 雙向驅動(P58) -> completed.md (archived 2026-10-05)
- [x] heartbeats/:兩台機器以 session id 送達並實測 -> completed.md (archived 2026-10-05)

## 背景資料已搬到 completed.md / Background notes moved to completed.md (2026-10-05)

下列各節是背景、決定與當時的量測，不是待辦項目。原文搬到 completed.md 的「背景資料」一節，內容反映各自寫下的日期。
其中唯一還沒做的事(WinUI 時鐘取消訂閱的量測)已拆成上方的 [ ] 項目。
These sections were background, decisions and measurements of their day, not items; their text is in
completed.md under "Background notes". The one thing in them still to do is now an open item above.

- 這份佇列是怎麼來的 / Where this list comes from
- Q8 note — what was measured before writing any code
- Windows 端回覆 — 2026-09-10 晚 / Answers from the Windows side
- 四個決定
- 兩個量測問題的答案
- 更正:#123 在 GTK/Windows 上**做得到**,我先前說反了
- Correction: #123 IS reachable on GTK/Windows
- 為什麼那不擋路
- 誠實的成本
- 減少不必要的重繪 / Reduction of unnecessary redraw
- 已經在位的部分 / What is already in place
- 沒有被跑過驗證的部分 / What has NOT been verified by running
- 相鄰但**不同**的一項,不要混為一談 / An adjacent item that is NOT the same
- 這份 queue 會漂,而重新產生它的指令在這裡(2026-09-16)
- 每個 backend 真正宣告的 BackendFeatures conformance
- The command that regenerates this, because this file drifts (2026-09-16)
- 五個 backend 的能力缺口,逐格開成待辦(2026-09-16 由原始碼查得)
- The capability gaps, one todo per cell (read from the source, 2026-09-16)
- 停在待辦上:iOS 的按鍵驅動(低優先,2026-09-16)
- Parked: driving keys into iOS (low priority, 2026-09-16)
- #125 Table 的 selection 與 sortOrder:開工前先講形狀(2026-09-16,Windows 端)
- selection 進度(2026-09-16 當天完成一半並驗收)
- Selection, half done and verified the same day
- #125 Table selection and sortOrder: the shape, before writing any of it
