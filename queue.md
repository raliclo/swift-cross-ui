# queue

## Open items at a glance / 待辦一覽 (2026-10-13)

Kept at the top at the user's request ("Organize todo in a table so we keep it in mind"). One row per open
item; the entry further down holds the detail. Update a row when its state changes, and remove it when the
entry is closed.
應使用者要求放在最上面。每個未結項目一列，細節在下方對應的條目;狀態改變時更新該列，條目結案時移除。

| # | Item | Where it is done | State | Next step |
| --- | --- | --- | --- | --- |
| 1 | `CommandGroup` as SwiftUI has it, all twenty placements, `enableMenu` switch | Mac | DONE on the Mac 2026-10-14: macOS, GTK (on macOS), iPad, iPhone, Android. Since then: items pressed in the iPad's real menu bar; Hide Others and Show All pressed on GTK; GTK undo by action file; one app menu and Command shortcuts for GTK on macOS; launch windows as SwiftUI (`SceneLaunch`); GTK's TextEditor undoes one change at a time through `TextUndoHistory`, by keys and by Edit > Undo and Redo (P94) | Not as SwiftUI, on purpose: `windowList` and `singleWindowList` are accepted on iOS. The iPad Format menu follows SwiftUI since 2026-10-20: none, even when the app fills `textFormatting` |
| 2 | `CommandGroup` on WinUI, and on GTK under Windows and WSL | Windows | WinUI DONE 2026-10-19: StandardCommands (WinUIBackend+StandardCommands.swift); Edit > Paste and Undo verified by hand on P92, all menus shown at 640 wide | LOW PRIORITY (user, 2026-10-19): an actions/win P92 file; synthetic input runs only the first menu item per launch (press and release 0.12 s apart), later presses close nothing and run nothing -- find why; then P92 on Windows GTK and WSL |
| 3 | `.focusable(_:)` on WinUI; GtkBackend's on Windows and WSL untried | Windows | WinUI DONE 2026-10-19: FocusableTargets (a tab-stop Canvas with a ring), `actions/win/P91-focusable.actions` passes | GtkBackend on Windows and WSL: replay P91 there |
| 4 | `onContinuousHover` and `taplabel` on WinUI, GTK under X11 and Windows; and the touch-hold hover of queue item 10 (2026-10-15) on WinUI, and on GTK with a real touch screen | Windows / WSL | done 2026-10-23 | taplabel (P10) and the pointer hover (P88) pass on WinUI, Windows GTK and WSL GTK (results.csv2 2026-10-21 to 2026-10-23). WinUI touch-hold hover written and driven 2026-10-23 with synthetic touch (`testapp/touch_gesture.zsh hold`): quick drag 0 hovers, 0.8 s hold then move 31 and ended, 0.3 s hold 0. Windows GTK touch-hold hover fixed the same day (`GtkBackend+WindowsTouch.swift`): quick drag 0 hovers, 0.8 s hold 30 and ended, 0.3 s hold 0. GDK does get the touch there and `GtkTouchHold` reports it; the emulated mouse Windows sends beside it was taken for a mouse hover, and is now ignored while a finger is down and 0.5 s after. (This row first said "Windows GTK gets no touch at all ... `GtkTouchHold` never runs" -- wrong, a trace showed 30 GDK_TOUCH_UPDATE and GTK's long press.) WSL GTK touch not tried (WSLg forwards no touch to X11 clients as far as known -- unverified). Was: "waits for Windows (user) | run P88 and P10-taplabel there. WinUI: a touch PointerPressed has to wait for a hold timer before PointerMoved counts as hover -- not written yet, nothing here compiles WinUI. GTK: `GtkTouchHold` in `GtkBackend+PointerHover.swift` was measured on macOS with the mouse standing in (results.csv2 2026-10-15); a real GDK_TOUCH_* sequence needs a touch screen" |
| 5 | P89 on WinUI, and on GTK under Linux/WSL and Windows | Windows / WSL | done 2026-10-20 on the Windows side (WinUI, GTK on Windows, WSL; results.csv2 rows of that day) | run it |
| 6 | `Mesh3DViews` on WinUI | Windows | DONE 2026-10-07 (a94c68af; detail at "GTK and WinUI: no `Mesh3DViews`"), the row was stale -- found 2026-10-19 | only driven on WARP (no GPU in that session); P72/P76/P77 on the RTX 4060 not yet |
| 7 | WinUI parity: date picker colour, font design, picker font, scale-change notice, fullscreen | Windows | four of five DONE 2026-10-07 (detail at "WinUI parity TODOs"); the row was stale -- found 2026-10-19 | the scale-change notice: P42 with the display scale changed in Settings while it runs (needs the user) |
| 8 | #123 accessibility: WinUI's UIA tree, Narrator and Orca speech | Windows / WSL | open | -- |
| 9 | P64 cell `fail 2026-09-10` in coverage.md | Windows (gtk4 column) | DONE 2026-10-19: re-run, the frame clock ticks (51.2 Hz, then 67.9 Hz idle-ish, PASS 1; it was TICKS 1); WinUI 131.1 Hz on the 144 Hz panel. results.csv2 rows of that date | regenerate coverage.md |
| 10 | iPhone hover: `onContinuousHover` reports nothing without a pointer | Mac | DONE 2026-10-15: the user chose "long click is hover". iOS: a finger held 0.5 s (UIKit's default); Android: the system long-press timeout (400 ms by default, follows the Accessibility touch-and-hold delay). From then on every move is reported and the lift ends it. P88 on iPhone, iPad, Android, macOS and GTK on macOS, see results.csv2 | -- |
| 11 | iPad: eleven action files (P80-cursor-ipad shows all six cursor shapes on the simulator, 2026-10-14; P94-undo-ipad); nothing run on a physical iPad | Mac | DONE 2026-10-15: the user accepts the iPad simulator ("It is ok to just have it on iPad") | -- |
| 12 | `reaim_android`: a real cross-build move, parking rows, several files in one write | Mac | done 2026-10-20 on swift-cross-ui-tablet36 | Cross-build move: P83 rebuilt with one extra 40 pt line on top; `aim` moved both points 30 pt down onto Drafts and Sent (moved=2), `write` put (57,253) and (247,287) in the file, `check` replayed it as written -> same; the change was then reverted. Parking row: P80's `move` before its scroll aimed clean. Same-build record/aim of P83, P103, P80, P102: 4 clean, moved 0. Several files in one `write` (2026-10-20): P83 and P103 recorded, both apps rebuilt with a 40 pt line on top, both aimed (P83 moved 2 points 25 down -- its content is centred, so it moves half -- and P103 moved 3 points 52 down), then `write P83-select-in-both-lists P103-tap-long-press` changed the five rows and no other line; `check` gave same for both, P103's capture shows 便利商店's picker open; apps and files reverted. `report` prints a clean, unchanged file only with -v. |
| 15 | P94 (TextEditor undo) on WinUI, and on GTK under Windows and WSL; `TextUndoHistory` for a `GtkTextView` has run on macOS only | Windows / WSL | done 2026-10-23 | all three pass with the expected p94-undo.log lines (matrix_coverage/results.csv2 2026-10-23). Found and fixed: WinUI did not redo on Ctrl+Shift+Z (TextBox knows only Ctrl+Y; `LongPressTextBox.onKeyDown` now takes both), and GtkBackend did not redo on Ctrl+Y (`TextUndoHistory` now takes Ctrl+Y, Control only, as well as Ctrl/Cmd+Shift+Z). `actions/win/P94-undo-gtk4.actions` clicks the editor instead of the Tab: GTK on Windows focuses it at start and the Tab was typed into it. Was: "replay the DRAFTS ... (written on the Mac 2026-10-14, never run; focus by Tab)" |
| 16 | P6 in the macOS sweep: `P6-transport-toggles` fails capture here because its stream folder `~/proj/LZFSE2/swift_tar/images` exists neither on this Mac nor on the Mac mini (2026-10-14) | M4 | handed to the M4 (user, 2026-10-15) | replay `actions/mac/P6-transport-toggles.actions` on the M4, where the folder is |
| 17 | AppKitBackend text layout, found by the GTK/macOS comparison (2026-10-16): (a) a caption wider than its sibling with a fixed frame is not drawn -- P10's "Under a transparent overlay" and "Under an opaque allowsHitTesting(false)" (VStack of Text + fixed-size ZStack), the button below rising as if the text had zero height; the same shape in P2, P8, P11, P13, P17, P17-DOE, P27, P29, P30, P43, P44, P50, P83; (b) one-line Text clips descenders (P88 "yes", "keys", "y=192"); (c) table cells overlap (P23, P26) | Mac | done 2026-10-16 | (a) and (b): the zero height proposal came back 1 pt tall from NSTextField, so Text now keeps whole lines, at least one (7efbaede and the follow-up); (c) AppKitBackend never implemented setColumnWidths, so its columns kept AppKits widths (about 234 pt) while Table measured cells at its own share (about 392 pt), and the inset table style added 32 pt; now the columns take Tables widths with no spacing, full-width style, and a wrapped cell ends in an ellipsis as on GTK. Checked on P10, P23, P26, P88 (AppKit), P10 and P23 (GTK), P10 (iOS). Re-captured P2, P8, P11, P13, P17, P17-DOE, P27, P29, P30, P43, P44, P50, P83 with GTK the same day: every listed caption is drawn; 18 comparison rows added to results.csv2, 12 aligned; what is left is item 26 |
| 18 | GtkBackend on macOS, from the same comparison: wrapped text ends in an ellipsis instead of wrapping (P51, P59, P62, P70); dark-grey text on black (P3); SF Symbols drawn as truncated names (P47); coordinate spaces read 0,0 (P63); no graphics adapter listed (P68); no initial focus (P91); `.floating` window level unsupported (P37); a lazy list builds 205 rows where AppKit builds 10 (P57); destructive tint over a set colour (P82); toolbar placement (P53) | Mac | done 2026-10-19 | done, from window captures of both backends (results.csv2 2026-10-19 unless named): wrapped text whole on P51, P59, P62 and P70 (869298ff, 2c679452), and on P17, where GTK now reports a wrapped label as whole lines of its one-line height; P3 captions light on black and legible; P63 reads global 90,294 against AppKit's 92,294; P82's blue set stays blue, and its bordered destructive button is red text on the ordinary bezel, the disabled one dimmed red, as on AppKit (GtkBackend no longer adds destructive-action to a Button); P47, P68 and P37 by items 17 and 22; P53 by 8691793f; P57 answered in item 31 (a GTK constant, no API); P91 focus at launch and its ring (b6902bdf). P3's lists on black as AppKit's: GtkListView (node listview) now transparent like GtkListBox (628acffa); its rows are 32 pt against AppKit's 28. |
| 19 | Android: a 1-px light seam between two adjacent same-colour views at a fractional pixel boundary (P95, 120 dp = 315 px on a 2.625 density) | Mac | done 2026-10-16 | `layoutLength` rounds sizes up while positions stay truncated; P95 on the emulator: the white pixel at x 314 of the strip is gone, the row reads 204 77 64 throughout |
| 20 | UIKitBackend: a `LinearGradient` of one colour to itself reads 216 104 88 where the colour is 204 77 64; Android and macOS draw it as the plain swatch beside it (P95, 2026-10-16) | Mac | done 2026-10-16 | `Color.Resolved.cgColor` was `CGColor(red:green:blue:alpha:)`, Generic RGB; the gradient space was not the cause (an sRGB CGGradient read 216 98 80, a CAGradientLayer 216 99 81). Now `CGColor(srgbRed:...)`: the gradient reads 204 76 63 beside 204 77 64 on the iPhone 17 simulator |
| 21 | macOS gtk4 sweep (2026-10-16): 112 files replayed and captured, but checked against each file's stated end state only 50 had their effect; 39 clicks measured on AppKit land beside their control on the taller GTK layout (testapp/measurements/gtk4-aim-20261016.csv2 lists each miss with GTK coordinates). P50 and P53 are done as `-gtk4` files | Mac | done 2026-10-16 | the `-gtk4` files were written and the re-sweep ran: 112 of 112 replayed; checked against the stated end states, 98 ok, and the 4 misses (P5, P19, P23, P41) were re-aimed and re-run (gtk4-aim-20261016-run2.csv2) |
| 22 | GtkBackend on macOS, defects the gtk4 sweep found: synthesised wheel events scroll nothing (P8, P21, P34, P57, P72; the List also builds all 205 rows); Escape does not close a one-button alert (P31); stacked alerts are dismissed oldest first (P5); a toggle stays drawn on when its getter says false (P45); two ScrollViews scroll together (P58); magnify/rotate never arrive (P65); no adapters listed (P68); Down/Return go to GTK focus navigation instead of a context menu (P72); a menu opens with an item already focused (P19) and Right does not open a submenu (P20); at zero width text becomes a hyphenated column (P9); `.automatic` DatePicker is the graphical one (P41); WebKitGTK missing (P27, P38); `.floating` level (P37) | Mac | done 2026-10-16 | all fixed and re-run; the re-sweep (testapp/measurements/gtk4-aim-20261016-run2.csv2) found seven more, also fixed the same day: one wheel event per notch (P21, P22, P72), buttons keep focus where it was (P70, P72), Slider editing and trough drag (P61), Table click in a cell gap (P23), keys for a focused WKWebView (P38). What is left is item 24 |
| 23 | GtkBackend on Linux/WSL, never compiled or run there (2026-10-16): the /sys/class/drm adapter list and DRI_PRIME / PRIME-offload selection (`GtkBackend+GraphicsAdapters.swift`), and the cross-platform GTK fixes made on macOS (one-button alert Escape, newest alert on top, scroll-to only in its container, zero-width text, compact `.automatic` DatePicker reporting month arrows, GtkFixed transforms for GeometryProxy origins; the visual-effect chain drawn in the container snapshot, whose grayscale needs GTK 4.20 component transfer -- below 4.20 it falls back to the CSS grey, so check the distribution's GTK version) | Windows (WSL) or a Linux machine | open; 2026-10-19: GtkBackend builds and runs in WSL (Swift 6.4.1), P68 lists both GPUs through DXCore (gtk_dxcore.c, the vgem device skipped), P95-P109 run there | port gtk_webview2.c (WebView2 over the HWND) and gtk_webkit.c (WebKitGTK in the box) to the `GtkWebEngine` protocol macOS's WKWebView now uses (GtkBackend+WebEngine.swift: one Swift host moved on the frame clock's after-paint, not a 50 ms timer); build GtkBackend there; run P68, P31, P5, P58, P9, P41, P63 and compare with the macOS gtk4 captures |
| 24 | GtkBackend, two questions from the gtk4 re-sweep (2026-10-16): (a) the arrow keys in a GTK popover menu start from a different item from run to run -- the first Down reached Button item in one run and Toggle item in another, and a reopened P19 menu drew Button item highlighted while one Down chose Second button item; clearing and resetting the menu model did not change it, so P19-gtk4 now clicks; (b) P39: CSS `saturate(0)` and `grayscale(1)` give the same grey on GTK, as the spec defines them, while AppKit draws grayscale through CIColorMonochrome tinted 0.5 (94 against 144) and the file calls equal greys a wiring fault -- decide which grey is right before changing either backend | Mac | (a) done 2026-10-19 on macOS; (b) done 2026-10-16 except WinUI (item 25) | (a) cause, from GTK 4.22's source: `gtk_popover_show` focuses the first item only when the popover has no focus child (gtkpopover.c), the focused GtkModelButton becomes the menu's selected item (`focus_in_cb`), and a pointer resting on an item selects it (`pointer_cb`); so the first Down went to the second item, and a reopened menu kept the focus child of its last opening. `GtkMenuKeyboardStart` clears the focus children before each opening, draws GTK's first item unselected, and on the first key selects it for Down, closes the menu for Return or space, and leaves Up (which wraps to the last item) to GTK. Measured on both backends with P19: Down + Return chose Button item, Up + Return Second button item, Return alone nothing and closed the menu (GTK was Toggle item, Second button item, Button item); nothing highlighted at open or on reopening; the AppKit key sequence ends button item and toggle item true (results.csv2 2026-10-19). P19-open-the-menu-gtk4.actions still clicks and still passes; it could use the keys again. Not done: a pointer that enters the first item while GTK already has it as the active item is not seen as a selection. (b) the user chose AppKit's grey: CIColorMonochrome in Core Image's linear working space, out = encode(overlay(L, c)) with L the linear luminance (0.2125, 0.7154, 0.0721), c = 0.21404 (0.5 grey in linear), overlay 2Lc below L = 0.5 and 1 - 2(1 - L)(1 - c) above, a partial amount blended in linear light. GtkBackend draws its whole effect chain in the container's snapshot now (component transfer, GTK 4.20+; the GPU renderer takes only about 33 table entries, so the curves are gamma functions), UIKitBackend wraps the filter in the sRGB tone curves, AndroidBackend uses an AGSL RuntimeShader on API 33+. P39 checked against the formula at 5-6 points per backend: GTK within 1 level (grayscale 0.5 within 2), iOS within 1, Android exact, AppKit exact. GtkBackend brightness also became additive (CSS `brightness()` multiplied, leaving black black where AppKit, UIKit and Android lift it); the other GTK cells are unchanged to 1 level |
| 25 | WinUIBackend grayscale (2026-10-16, from item 24b): it uses Win2D's GrayscaleEffect, which is the sRGB-luma grey (the same as saturation 0) and has no amount at all, so `grayscale(0.5)` draws fully grey. Needs the AppKit grey from item 24b, and cannot be built on the Mac | Windows | DONE 2026-10-19: grayscale 1 and 0.5 within 2 levels of the formula on P39; composition needs a tree, so the upstream is built once per branch (done as planned below) | in the composition effect graph: LinearTransfer (slope 1/1.055, intercept 0.055/1.055) then GammaTransfer (exponent 2.4) to decode; ColorMatrix to linear luminance in every channel; the overlay as max(2cL, 1 - 2(1 - c)(1 - L)) = 2cL + clamp((1 - 2c)(2L - 1)), e.g. two branches joined by ArithmeticComposite; GammaTransfer (amplitude 1.055, exponent 1/2.4, offset -0.055) to encode; CrossFade with the decoded original for an amount below 1. Expected on P39 (control pixel -> grey): (255, 103, 49) -> 102, (38, 200, 111) -> 119, (239, 61, 144) -> 90, mid grey 127 -> 85. Check first that the composition effect factory accepts each of these Win2D effects |
| 26 | AppKitBackend, differences left after the item 17 re-capture (2026-10-16): (a) P8's H0-H8 labels are cut off by the horizontal scroll bar of the strip inside the vertical ScrollView, where GTK shows them in full; (b) P17's measurement labels (subject:, control:, stack:, picker:) are drawn as blank white rectangles and its Picker as a wide blue bar; (c) P43's gradient-stroke ring is clipped flat on four sides, where GTK draws it round; (d) P27 and P39's angular and sweep gradients run the opposite way round from GTK's | Mac | done 2026-10-19 | each measured against GTK in window captures of the same run (results.csv2 rows of 2026-10-19). (a) AppKit heard preferredScrollerStyleDidChange on the distributed centre instead of its own, so layout kept a scroller width of 0; H0-H8 whole above the 15 pt scroller (2bc435a4). (b) the readouts were white text on white, now black on white on both; the blue bar is P17's own blue measuring background behind the pop-up, 350 x 18 from its widest option (GTK 373 x 24) (2bc435a4). (c) GTK was right, as SwiftUI draws the half of a stroke outside the shape: AppKit's path view clipped its drawing to its bounds; it no longer does, and the ring is 134 x 134 pt on both (was 120, flat). (d) GTK was wrong, the conic start was -90 instead of +90 from CSS's twelve o'clock; P27 and P39 now red at three o'clock, clockwise, on both (2bc435a4) |
| 27 | GSAP on SwiftCrossUI (2026-10-16), phases 1, 2a and 2b done on four backends, phases 3a (Flip) and 3b (ScrollTrigger) on two, 3c (direct path for effects animated by `withAnimation`) on three. Phase 1: `TimingCurve` with GSAP's eases (`.power2(.out)` etc.), `Steps`, `CubicBezier`, `Spring` and SwiftUI's `.spring`/`.smooth`/`.snappy`/`.bouncy`; `delay`, `speed`, `repeatCount`, `repeatForever` (SwiftUI names; GSAP's `repeat: n` is `repeatCount(n + 1)`, `yoyo` is `autoreverses`) through the pure `TweenClock` -- P96, P97. Phase 2a: `withAnimation(_:_:completion:)`, `.onStart`/`.onRepeat`/`.onUpdate` (once per call), `.stagger(i, of:, each:, from:)` -- P98. Phase 2b: `AnimationTimeline` (positions `.afterPrevious`, `.withPrevious`, `.at`, `.label`) and `TimelinePlayer` (play, pause, reverse, restart, seek, `timeScale`, `onUpdate` for a bound slider) on a driver ticker -- P99. All pass on AppKit, GTK (macOS), iOS and Android. Phase 3a (2026-10-17): Flip as `matchedGeometryEffect(id:in:properties:anchor:isSource:)` and `@Namespace` -- a moved view, a view replacing one with the same id, and an `isSource: false` follower fly from the old frame by a translation and scale set on the widget each frame (no re-layout); a non-tweenable assignment inside `withAnimation` arms a `LayoutTransaction` that the next updates (0.3 s window) read, and frames are measured after the commit, before the frame is drawn. Found on the way: AppKit's `originInWindow` read the previous layout (positions are constraints) and now flushes layout first, WinUI the same by `updateLayout` (untested); group callbacks fire after every tween of a frame has written. P100 passes on AppKit and GTK (macOS): mid-flight error 0.00 pt on all three cases. iOS and Android not run: the disk had under 1 GB free and the iOS build failed for space. Phase 3b (2026-10-17): ScrollTrigger as `scrollTransition(_:axis:transition:)` (`.interactive(timingCurve:)` = GSAP scrub, `.animated(_:)` = toggleActions, thresholds `.visible(_:)` and `.centered`; the closure gets SwiftUI-style content with `opacity`, `scaleEffect`, `offset`, `rotationEffect`, `blur` ...), `onScrollVisibilityChange(threshold:_:)` (onEnter/onLeave) and `onScrollGeometryChange(for:of:action:)` with `ScrollGeometry` (scrubbing a `TimelinePlayer`), on a new conformance-checked `BackendFeatures.ScrollOffsetReporting` that all five shipped backends implement (NSClipView bounds notification, UIScrollView contentOffset KVO, GtkAdjustment value-changed, Android ScrollView onScrollChanged through a SwiftAction, WinUI ScrollViewer ViewChanged); effects are set on the widgets on each scroll, no re-render. AppKitBackend scrollTo was fixed on the way (it scrolled past the content). P101 passes on AppKit and GTK (macOS), opacity error 0.000 over 20 rows at three scroll positions; UIKit, Android and WinUI code is written but not compiled or run here (disk full; WinUI cannot build on the Mac). P96 about 60 fps on AppKit, about 10 fps on GTK (33 shape paths per frame); the first tick arrives 0.1 s (AppKit, iOS) to 0.2-0.3 s (GTK, Android) after the call. **Compositor decision (2026-10-17): no `CompositorAnimations` protocol, measured.** P96 drew about 60 fps on AppKit and about 10 fps on GTK, but its animation goes through `@State`: every frame re-evaluates the body, re-lays out and redraws 33 shape paths. P100's flip animates the same kind of property (a transform) by setting it on the widget each frame from the same main-thread frame clock, with no re-render: 61 frames in its 1 s flip on GTK and 62 on AppKit, mid-flight error 0.00 pt, done at 1.03 / 1.04 s. So the 10 fps was the re-render, not the lack of a compositor, and the direct path already reaches the display rate on the slow backend. A compositor protocol (Core Animation `CAAnimation`, Android `ViewPropertyAnimator`, WinUI Composition) would also split the five backends: GTK has no off-thread animation API, so GTK would be the one left on the main thread, and the rule here is that every feature works on all five. The first-tick delay (0.1 s AppKit/iOS, 0.2-0.3 s GTK/Android) is the frame clock starting, which a compositor would not remove. What followed instead is phase 3c below; reopen the compositor question only if a measured frame is lost to main-thread work while the direct path is in use. **Phase 3c (2026-10-17): `.offset`, `.scaleEffect`, `.rotationEffect`, `.transformEffect`, `.opacity` (and blur and the colour effects) on the direct path** (Sources/SwiftCrossUI/Animation/EffectAnimation.swift). When an update runs under an animation -- a `withAnimation` assignment that cannot tween (a Bool, an enum) armed a `LayoutTransaction`, or a new SwiftUI `.animation(_:value:)` above the modifier saw its value change -- each effect modifier whose value changed tweens its widget from the drawn value to the new one on the frame clock (`EffectTween`, one tween per modifier per transaction), with no body re-evaluation or re-layout; SwiftUI semantics, so an effect moves in a straight line between two renders, and a view that should follow a curve gives that coordinate its own animation. A tweenable `@State` (Double) inside `withAnimation` keeps its own tween and per-frame re-render: P66 animates `.padding` that way and P96-P99 read the intermediate state values, and the view graph does not record which views read a state for something other than an effect, so that path cannot be made direct automatically. Unchanged backend protocols (all five already implement `setGeometricEffect`/`setVisualEffect`); written for the per-frame cost: GtkBackend now puts geometric effects on the parent GtkFixed child transform instead of CSS `transform` (Fixed.setChildMatrix; with CSS the dots alone drew 28 fps on GTK, most of each frame in gtk_css_node_validate), and UIKit, Android and WinUI skip rebuilding the filter snapshot / RenderEffect / Win2D graph when only the opacity changed. P96 now flips one `running` Bool (x linear, y through each tile's curve via `.animation(.timingCurve(curve), value:)`, both direct; the driven tweens moved to their own child view) and logs FRAMES and ERROR. Measured on this Mac, first 3 s of the run, frame-clock ticks: **AppKit 181 before, 181 after (60 fps), but one tile's body evaluated 2327 times before and 3 after; GTK 25-27 before (8-9 fps), 98-100 after (33 fps) while the driven panel re-renders, and 97-180 (32-60 fps) for the dots alone at 5-8 s** (spread from machine load: another session's Android emulator was running). ERROR: drawn y against the curve at the drawn x, 0.000 pt on all 33 tiles at 1.0/1.5/2.0/2.5 s on both backends; x against the clock 0.000. Driven tweens on GTK 22-26 distinct values per 0.8 s (before 7-9). What is left on GTK per frame is GTK re-rasterizing the 33 curve strokes through cairo (sampled). P100 and P101 re-run on AppKit and GTK: err 0.00 / 0.000 as before; P40 captured on GTK with the child transform, every transform drawn as before. 286 + 14 unit tests pass (8 new in EffectAnimationTests), one known issue. iOS (iPhone simulator, UIKit compiled and run): 180 ticks in the first 3 s (60 fps), 3 tile body evaluations, curve and x error 0.000 pt; no tick-count baseline exists for iOS (the 2026-10-16 row has 21-26 distinct driven values per tween). On iOS the tiles were committed by an update not begun in observeAsUIUpdater (LayoutTransaction.active nil 14 ms after arming), so the x offsets jumped; the effect transaction now also reads the armed 0.3 s window, one tween per modifier per token. P96 flips `running` only once the dots have been drawn at their start (onAppear runs before the first commit). Android and WinUI parts written, not compiled or run (the emulator belongs to another session; WinUI does not build on the Mac) | Mac, then Windows | phases 1-2b done on the Mac; 3a, 3b and 3c run on AppKit, GTK (macOS), iOS and Android (2026-10-19: P100, P101, P104 on the iPhone simulator and the tablet36 AVD, P96 on Android, all within their limits; P104 on iOS needs `--steps-after 6`, as XCUITest attaching holds the main thread for most of a second); WinUI untested | run P96-P101 on WinUI and GTK under Windows, P96 (3c) on WinUI; GTK draws Shapes as GSK nodes since 2026-10-19 (render time per frame in P96 about 2.7 -> 0.8 ms), and on macOS the GTK frame clock now runs at the display rate (2026-10-19: GDK 4.24 stopped its CVDisplayLink after every frame and a restart less than about 10 ms before a refresh called back one refresh late, measured with testapp/test_support/measure/gtk_frame_trace.c; GtkBackend keeps the link running while its frame clock runs: P96 ticks 176-177 per 3 s driven and 180 dots alone, before 100-103 and 169-174; P104 WITH 60-61 frames, before 33-58), GTK on Windows and Linux does not use that path and is unmeasured; `.animation(_:value:)` also drives layout and drawn state since 2026-10-18 (row 30) |
| 28 | Long-press drag selection in text fields (2026-10-17), from the api18 WebView: `longPressTextSelection(_:)` (not SwiftUI API; off by default, opt-in, inherited by every `TextField`/`TextEditor` below) on a conformance-checked `BackendFeatures.LongPressTextSelection`, implemented on all five shipped backends with each toolkit's hit-testing (AppKit `characterIndexForInsertion(at:)` with its own field editor; UIKit `closestPosition(to:)`; GTK `gtk_text_view_get_iter_at_position` and GtkText cursor extents through a capture-phase legacy controller; Android `getOffsetForPosition` in `CustomEditText.kt`; WinUI `GetRectFromCharacterIndex` in `LongPressTextBox`). P102 passes on AppKit, GTK (macOS), iOS and Android: forward selection in the field, backward in the editor, nothing for the plain field or a quick drag | Mac, then Windows | done on four, and on WinUI 2026-10-19 (`actions/win/P102-long-press-drag.actions` passes) | GTK under Linux/WSL with a real touch screen (Android: done 2026-10-20, `actions/android/P102-long-press-drag.actions` passes through AndroidSynthesiser on swift-cross-ui-tablet36) |
| 29 | The api18 "interested places" list as library components (2026-10-17): `EmojiPicker(selection:keyword:)` (grid plus filter field; EMOJI_NAMES ported, Chinese and English; keyword matches first on #e1bee7 with a #8e24aa border; OK/Return takes a typed value no name matches), `EmojiToggleButton(emoji:isOn:keyword:)` (tap toggles, long press opens the picker in a sheet), `EmojiKeywordList(items:)` (rows of toggle, colour bar, keyword, ✕; field and Add with PALETTE colours and 📍), `EmojiKeywordListButton(items:isOpen:)` (the 📍 pin that opens the list), model `EmojiKeywordItem` (alias `InterestedItem`) with api18's CSV rows. The tap and the long press on one view are a new conformance-checked `BackendFeatures.TapAndLongPressGestures` behind `onTapAndLongPressGesture(onTap:onLongPress:)`, implemented on all five (AppKit/UIKit: the click requires the press recogniser to fail; GTK: tap on release unless the long press fired; Android: the consumed long click; WinUI: a timed press). Also fixed: AppKit/UIKit `.longPress` fired again on every `.changed`; UIKit's `TappableWidget` never forgot a removed long-press recogniser. 17 unit tests; P103 passes on AppKit and GTK (macOS) with two action files each | Mac, then Windows | done on AppKit and GTK (macOS); P103 on the iOS simulator and the tablet36 AVD 2026-10-19 (results.csv2); WinUI not run from the Mac | run P103 on the iOS simulator and Android (actions/ios, actions/android files); build WinUIBackend and run P103 on Windows; GTK on Linux/WSL; a sheet cell is clicked by AppKitSynthesiser since 2026-10-20 (the long press's mouseup had gone to the sheet it opened; releases now go to the pressed window) |
| 30 | GSAP, what is left after item 27 (2026-10-18). Done 2026-10-18: `.animation(_:value:)` and a `withAnimation` assignment that cannot tween drive `.frame`, `.padding`, a `Color` view and a `Shape`'s flat fill and stroke (585a8085, ParameterTween in Animation/LayoutAnimation.swift); P104 on AppKit and GTK (macOS): mid-flight err 0.00 pt, colour 0.0. Done 2026-10-19 (P105-P109, each run on AppKit and GTK on macOS from debug builds in the package's own .build through `test.zsh -n`; UIKit, Android and WinUI take the same SwiftCrossUI code, not compiled or run): (1) insert/remove `.transition(_:)` with SwiftUI's `AnyTransition` (`.opacity`, `.scale`, `.scale(scale:anchor:)`, `.slide`, `.move(edge:)`, `.offset`, `.push(from:)`, `.asymmetric`, `.combined(with:)`, `.animation(_:)`, `.identity`) for `if`, `if`/`else` and `ForEach`; a removed view stays in its container, drawn, until its removal ends (bfa82049, Animation/Transition.swift). P105: err 0.00 pt, opacity and scale err 0.000 for seven transitions, if/else and ForEach; onDisappear 1.03 s after a 1 s removal. (2) `keyframeAnimator` (repeating and trigger), `KeyframeAnimator`, `KeyframeTrack` with `LinearKeyframe`/`SpringKeyframe`/`CubicKeyframe`/`MoveKeyframe`, `KeyframeTimeline`, `UnitCurve`, `phaseAnimator`/`PhaseAnimator` (90e1aa01, Animation/Keyframes.swift). P106: drawn values equal the timeline (err 0.000 over 300+ checks), timeline equal to closed forms, phases 1,2,0 about 0.52 s apart for 0.5 s steps. (3) MotionPath as `.motionPath(_:progress:anchor:orientsAlongPath:)` plus `Path.trimmedPath(from:to:)`, `currentPoint`, `length`, `point(at:)`; progress tweens, so the view runs along the path (4bd2af19, Animation/MotionPath.swift). P107: centre against a closed form err 0.000 pt, direction within 0.12 degree. (4) Draggable with inertia as `.inertialDrag(offset:bounds:axes:decelerationRate:)`, `Inertia` (UIScrollView deceleration, tau 0.4995 s, stops on bounds) and `DragGestureValue.velocity`/`predictedEndTranslation`/`predictedEndLocation` from `DragVelocityTracker` (470f5c2a, Animation/DragInertia.swift). P108 with real drags from action files: coasts on the closed form err 0.0000 pt, release velocity within 0.4 pt/s of the received speed, a held drag gives velocity 0 and no coast. Fixed on the way: AppKit hit-tested a geometric-effect container at its layout frame (a thrown card could only be picked up where it was laid out); GtkBackend on macOS gave the first frame-clock tick 1.5-4.2 s late after an animation had ended (now a 60 Hz fallback tick until the clock's first, 0.05 s). (5) `Text` `.foregroundColor` / new `.foregroundStyle(_:)` and Linear/Radial/Angular gradients (stop colours and locations, points, radii, angles) tween (f3d646e2, Animation/StyleAnimation.swift). P109: colour err 0.0/255, geometry err 0.000. Fixed on the way: AppKit's linear and radial gradient views redrew only on a size change (UIKit's and Android's got the same fix, not run). Done 2026-10-19 (P105 DEFAULT, P110, P111; AppKit and GTK on macOS from debug builds through `test.zsh -n`; UIKit, Android and WinUI written, not compiled or run): (6) default transition: without a `.transition` a view an `if`, `if`/`else` or `ForEach` inserts or removes under `withAnimation` or `.animation(_:value:)` fades (`.opacity`), not without an animation, `.transition(.identity)` opts out, a view with a `matchedGeometryEffect` flies instead of fading when removed or when inserted with an id another view held; the container wraps the view's widget in a visual-effect container (DefaultTransitionSlot, Animation/Transition.swift) before insertion, or at its commit for a removal, at the position the layout last gave it (9d63a575). P105 DEFAULT: opacity err 0.000 for if, if/else and ForEach, onDisappear 1.01-1.03 s after a 1 s removal, no frames without an animation, `.identity` at opacity 1; mid-removal captures show the removed row fading in place; P100 err 0.00. (7) gradients that tween: `.foregroundStyle(_:)` takes a LinearGradient or RadialGradient for text and unfilled shapes; shape fills/strokes and text foreground are a FillDrawing (colour, linear, radial) tweening colour to colour, gradient to gradient and colour to gradient; text gradients drawn by AppKit/UIKit (sourceIn over the glyphs), GtkBackend's containers (GSK mask node, gtk_text_paint.c, GTK 4.14+), Android (paint shader), WinUI (TextBlock brush) (c478ea48). P110: colour err 0.0/255, point and radius err 0.000 for two texts and four shapes, `.animation(value:)` at the clock's p (0.500 against 0.499-0.507); captures show gradient text. (8) keyframe velocities: `SpringKeyframe(startVelocity:)` (else the previous keyframe's end velocity), `CubicKeyframe(startVelocity:endVelocity:)` on a Hermite curve (else Catmull-Rom through cubic neighbours, a neighbouring keyframe's velocity, half the average at the track's ends), a move stops the motion; velocities measured from the new `AnimatableValue.animatableZero` (Double, Float, SIMD2) (f84ff881). P111: timeline value err 8.6e-15 pt, slope err 0.008 pt/s, drawn err 0.0000 pt. Also: the P105-P107, P109 macOS GTK action files said platform gtk and failed ActionFileTests; now macos (01b5ae76); P105 action files wait 26 s (30 s on iOS). 379 + 14 unit tests | Mac, then Windows | done on AppKit, GTK (macOS), iOS and Android for P105-P109 as before; P110 and P111 also on iOS and Android (2026-10-19), P105 DEFAULT on Android (2026-10-19) and iOS (2026-10-20); WinUI part not run from the Mac | run P105 DEFAULT, P110, P111 on iOS, Android, WinUI and GTK on Windows/Linux (compile UIKit's TextView gradient draw, Android's FittedTextView shader and WinUI's text brush first); AngularGradient is a ShapeStyle since 2026-10-20 (ResolvedFillStyle.angularGradient; P112 on AppKit, GTK GSK and cairo, iOS, Android); WinUI still paints its midpoint colour with a notice -- XAML has no conic brush and swift-winui projects no ImageBrush; RadialGradient radii in a fill or text are points as in SwiftUI since 2026-10-20 (P112 on AppKit, GTK, iOS, Android), WinUI still to change; a removed matchedGeometryEffect view fades and flies to the view that takes its id since 2026-10-20 (P100 HERO on AppKit, GTK, iOS, Android); text gradients need GTK 4.14 (below that the text takes the gradient's middle colour); `Int` has no animatableZero, so Int keyframe velocities are not used; P106 PHASE on GTK (macOS) was 23.0, 15.4, 10.2 ms in three runs against 17 ms; run P105-P109 on WinUI and GTK on Windows/Linux; Android P106 PHASE closed 2026-10-19 (each drawn value checked at its first 8 ms sample: 6.4-8.3 ms on tablet36; 6.2 and 7.8 ms on api36b 2026-10-20); P96-P104 on WinUI and GTK under Windows and Linux |
| 31 | The GTK/macOS pairs deck reviewed by the user (2026-10-18), on the 2026-10-15 captures: P27 and P38 WebView on GTK; P29, P30, P32 AppKit captions covered; P37 GTK `.floating`; P41 `.hourAndMinute` should be two defined looks on every platform, a clock (as macOS) and rows (as GTK); P42 gap; P44 window size gap and AppKit; P47 GTK text; P51 wrapped text ends in an ellipsis; P52 GTK grid alignment, follow macOS; P53 window size differs; P54 prefer the macOS output; P57 which list is more efficient; P68 gap; P90 the wheel style is missing on macOS, can it be drawn in Swift; P91 align GTK with macOS. Colour differences are acceptable | Mac | open: action files and other hosts only | Done, every item of the deck: P27 and P38 (GTK draws WKWebView on macOS), P29, P30, P32, P37, P42, P47, P68 (GTK lists Apple M6) by items 17 and 22; wrapped Chinese no longer cut to one line (869298ff); a growing window grows to its ideal size, P44 and P51 captions whole (2c679452); P53 header bar out of `.defaultSize` (8691793f); AppKit-sized GTK buttons and fields, CSS before the first view, P52, P54, P91 (b7b60803); `.datePickerStyle(.wheel)` on every backend, P90 (efa2b093); P41 `.clock` and `.rows` on every backend, and the native `.wheel` read from the environment again in `_BuiltinDatePickerImplementation`; P57 answered (AppKit builds the visible rows, 58 MB; GtkListView keeps about 200 built, 112-150 MB, a GTK constant with no API); P91 focus ring outside panel A on GTK (b6902bdf); 2026-10-19 also P29 TextEditor background, P32 slider trough, P27 and P39 conic direction (2bc435a4; P39 checked in window captures, results.csv2 2026-10-19). 2026-10-20 the Swift wheel, rows and clock are driven: actions/mac/P41-swift-wheel-rows-clock.actions (AppKit: Swift wheel and rows, NSDatePicker clock) and its -gtk4 twin (Swift wheel and clock, GTK rows), checked by the readbacks (results.csv2 2026-10-20); it found two defects, both fixed: the `.rows` minus and plus never stepped on AppKit (NSBezierPathView took clicks across its whole frame, now only where the shape is drawn) and the wheel took no mouse wheel on GTK (a 16 pt notch is a gesture of its own and ended short of the 24 pt row; `_WheelColumn.scrollStep`). The two older P41 mac files were re-aimed for the four-row layout. Left: Windows and Linux not checked (WebView2, WebKitGTK 6.0, `.floating` needs X11 `_NET_WM_STATE_ABOVE`); P6 and P6-v2 capture nothing, as in every capture |
| 32 | P96-P109 never run on WinUI, nor on GTK under Windows or Linux/WSL; the GskPath change (f84ee359, shapes drawn as GSK fill and stroke nodes) not yet compiled on Windows (GTK 4.22) or Linux (added 2026-10-19 at the user's request) / P96～P109 在 WinUI 上全部沒跑過，在 Windows 和 Linux 的 GTK 上也都沒跑過；GskPath 的改動在 Windows(GTK 4.22)和 Linux 上也還沒編譯過 | Windows / Linux | done 2026-10-23 | P107 on the NVIDIA dGPU closed 2026-10-23 as a hardware property (the user's choice, not fixed in code): the dGPU sleeps after about 0.3 s idle and the first frame after it waits for the wake-up, 97-158 ms growing with the idle time and 16-21 ms after 0.05 s idle; GTKs layout-to-paint of that one frame, every GPU renderer, not cairo; results.csv2 2026-10-23. Keeping the GPU awake would cost power and needs to know an animation is coming. test.zsh prefers the dGPU, so P107 there still reads FAIL on progress vs clock. Verified 2026-10-23 against results.csv2: P95-P109 each have a passing row on windows/winui, windows/gtk4 and wsl/gtk4, P95 (resize), P103 (clicks) and P108 (drags) included; the Windows GTK start latency is 0.19-0.22 s since the warm-up frame (2026-10-21). The last empty cell, P102 on Windows GTK, ran 2026-10-23 with the new actions/win/P102-long-press-drag-gtk4.actions. Was (stale by 2026-10-23): "left: P95 (window resize), P103 (clicks) and P108 (drags) need input; open findings (P104 resolved: 2 body evaluations is right): start latency ~0.4 s after onAppear, P107 on Windows GTK 145 ms; then run P96-P109 on WinUI, Windows GTK and WSL GTK, writing `actions/win` and `actions/wsl` files" |

## 2026-10-10 onContinuousHover (for SoftPCB's Cmd node probe)

- [x] **`View.onContinuousHover(perform:)` with modifiers** (Mac side).
  SoftPCB tab 9 reads the nearest node's value while Command is held over
  the 3D view, so the hover has to carry the pointer location *and* the held
  modifiers, and has to report a modifier change without the pointer moving.
  `PointerHoverPhase` (`.active(location:modifiers:)`, `.ended`; the name
  avoids PortingKit's `HoverPhase`) and `BackendFeatures.PointerHover`.
  A backend without the feature degrades to "never called" with a one-time
  log, like `onKeyPress`, instead of `@CastBackend`'s fatalError.
  AppKit: an `NSTrackingArea` (`.mouseMoved`, `.inVisibleRect`) on the
  container itself -- no overlay view, so drags on the content still work --
  plus a `flagsChanged` local monitor while the pointer is inside. UIKit:
  `UIHoverGestureRecognizer` + `modifierFlags`. GTK: an
  `EventControllerMotion` and `gtk_event_controller_get_current_event_state`.
  Android: `PointerHoverContainer.kt` overriding `dispatchHoverEvent`.
  Found on the way: `AppKitSynthesiser`'s HID mouse events carried no
  modifier flags, and `AndroidSynthesiser`'s hover carried no meta state;
  both now carry the held modifiers. P88 (new), every capture read:
  macOS all lines including "seen (cmd)" on a Cmd press without moving;
  GTK on macOS pointer, cmd and drag (no still-change report: GTK sends no
  motion for a key alone); Android emulator pointer 182,58, cmd 152,88,
  drags 1; iPad simulator hover 2 reports, ended, drags 1 and control
  drags 1 -- cmd is not checkable there, XCUITest hover carries no
  modifiers.
  2026-10-15, queue item 10: on a touch screen a held finger is hover --
  `UILongPressGestureRecognizer` (0.5 s, direct touches only, cancels no
  touches) in `PointerHoverWidget`, and `dispatchTouchEvent` with the system
  long-press timeout in `PointerHoverContainer.kt`. P88 now has "last active"
  and an orange panel while hovered; every P88 cell was re-run and recorded
  in results.csv2 the same day (macOS and GTK on macOS had no row before).
  2026-10-15,queue 第 10 項：觸控螢幕上按住的手指即是 hover。P88 多了「last active」,hover 時面板變橘色;
  各平台當天重跑並寫進 results.csv2(macOS 與 macOS 上的 GTK 之前沒有紀錄)。
  - [x] **WinUI: `onContinuousHover` -- written, NOT compiled** (2026-10-10,
    on macOS). `WinUIBackend+InputTargets.swift`: `PointerMoved` /
    `PointerExited` on a `WinUIFeatureTarget`, modifiers from
    `currentModifiers()` (Control is `.control`, so SoftPCB accepts either).
    No report for a key pressed while the pointer rests, as GTK. Windows:
    build it, then P88 with `actions/win/` coordinates; if it does not
    compile, the fix or the removal is yours to make.
    **DONE 2026-10-20 on the Windows side** (23b35cc1, "P88 on WinUI passes"):
    built and run; P88 reads hover reports 44, last with cmd recorded, and 1
    drag, once its pointer rows are `hover` (SendInput steps) rather than a
    buttonless `move`, which SetCursorPos performs and WinUI does not treat as
    pointer input. This box stayed unticked until 2026-10-22, when a review of
    open items found it stale.
    **2026-10-20 已在 Windows 端完成**(23b35cc1):已建置並執行,P88 讀到 44 次 hover 回報、最後一次帶 cmd,以及 1 次拖曳。
    此勾選框一直未勾，直到 2026-10-22 檢查未完成項目時才發現它已過期。
- [x] **AppKit: `.offset` (any geometric effect) on a view that appears
  later was not applied** (2026-10-10, found in SoftPCB's tab 9: a
  conditional label drawn at the overlay's corner). When Auto Layout gives a
  layer-backed view a new frame, AppKit puts its layer's transform back to
  identity. A view present from the start is committed again once sized, so
  it never showed; one that appears later is committed once, at zero size.
  `AppKitHitTestingContainer` now keeps the transform and assigns it again
  after each frame change, on the next turn of the main queue -- assigned
  inside the layout pass it is overwritten again (measured: 100,-160 after
  the commit, 0,0 once the frame was 97x16; `setFrameSize`/`setFrameOrigin`
  overrides were not called by Auto Layout). P89 (new): five offset views
  in one overlay, the one appearing after two seconds at the corner before
  and on the line after; macOS only.
  - [x] **P89 on the other backends.** Run 2026-10-10 on this Mac: UIKit (iPhone
    and iPad Pro 11-inch simulators), Android (emulator) and GTK (macOS, `TEST_BACKEND=gtk4`) all keep the
    effect on the late view -- A, B, C, D and the circle start on the red line in
    the after state. Still not run: WinUI, and GTK on Linux/WSL and Windows (no
    such machine here).
    **DONE 2026-10-20 on the Windows side**: WinUI, GTK on Windows and WSL all pass (sleep-only `P89-offset-in-overlay.actions` in actions/win and actions/wsl).
  - [x] **Waits for the Windows side (user, 2026-10-13), with onContinuousHover there.** 等 Windows 端。
    **`taplabel` on WinUI, and on GTK under X11 and Windows.** Works on
    AppKitBackend and on GtkBackend on macOS (2026-10-10, `actions/mac/P10-taplabel.actions`:
    Direct, Covered and Hidden clicks all 1 on both): the backend sets
    `ActionFileReplay.locateLabel` and the replay loop clicks where it points.
    GtkBackend's locator is the same code on every OS but has only run on macOS.
    WinUIBackend sets none, so the row reaches Win32Synthesiser, whose refusal
    (`case .tapLabel`, like XdotoolSynthesiser's) is written from the Mac and not
    compiled -- a non-exhaustive-switch error there is this.
    **DONE 2026-10-22 on the Windows side.** WinUIBackend now sets a locator
    (`WinUIBackend+LabelLocator.swift`: open popups first, then the content;
    TextBlock or TextBox text). Run with `actions/win/P10-taplabel.actions` and
    `actions/wsl/P10-taplabel.actions` (Direct / Covered / Hidden):
    GTK on Windows 1/1/1; GTK under WSLg 1/1/1 (twice; the first run after a
    fresh build registered only Covered, with the same three positions);
    WinUI 1/0/1, where the 0 is not the locator: the coordinate file
    `actions/win/P10-hit-testing.actions` also leaves Covered at 0 on WinUI.
    **2026-10-22 已在 Windows 端完成。** WinUIBackend 已設定定位器(先找開著的 popup,再找內容;比對 TextBlock 或 TextBox
    的文字)。P10:Windows 上的 GTK 1/1/1;WSLg 上的 GTK 1/1/1(兩次；剛建置完的第一次只有 Covered 生效，三個位置相同);
    WinUI 1/0/1,其中的 0 不是定位器的問題：以座標點擊的 `actions/win/P10-hit-testing.actions` 在 WinUI 上同樣讓
    Covered 停在 0。
  - [x] **WinUI: a transparent overlay swallows the click meant for the button under it.**
    P10's "Click me too" sits under a `Color.clear` overlay; on WinUI a click there
    leaves Covered clicks at 0, by `taplabel` and by coordinates alike (2026-10-22),
    while GTK on Windows, GTK under WSLg and AppKit all count it. Likely a XAML
    hit-test rule (a Transparent brush is hit-testable, a null brush is not); not
    yet looked at.
    WinUI:透明覆蓋層吞掉了要給下方按鈕的點擊。P10 的「Click me too」上方蓋著 `Color.clear`;在 WinUI 上，不論用
    `taplabel` 或座標點擊，Covered 都停在 0(2026-10-22),而 Windows 上的 GTK、WSLg 上的 GTK 與 AppKit 都有計數。可能是
    XAML 的命中測試規則(Transparent 筆刷會被命中,null 筆刷不會);尚未調查。
    **FIXED 2026-10-22:** WinUIBackend.setColor gives a fully transparent colour no
    brush (null background), so XAML lets the pointer through. P10 on WinUI: Covered
    clicks 1 by `taplabel` and by coordinates.
    **2026-10-22 已修正:** WinUIBackend.setColor 對完全透明的顏色不給筆刷(null 背景),XAML 便讓指標穿過。WinUI 上的 P10:
    `taplabel` 與座標點擊的 Covered 都是 1。
  - [ ] **WSL sweep of 2026-10-22, three leftovers (P81 and P26 fixed; P6-v2 open).** All 134 WSL action files ran
    under X11 with `GTK_CSD=1` (`sweep_drive_wsl.zsh`, adaptive showtime and
    `# expect:` checks); all replayed to the end except one P81 run (below), and
    of the 14 that declare an expectation, the 13 the sweep can judge were met (P54's is `expect: screenshot`, judged by eye). Three need a look:
    - P6-v2-transport-toggles: the replay finishes (15 actions) but the final
      capture finds no window, with `GTK_CSD=0` and `=1` alike, and the 1 s
      capture is 0-4% non-black. A plain run's final capture is fine (87.8%),
      so the deck is unaffected; something after the drop-down rows.
    - P81-sheet-from-window-b: failed once in the sweep ("no visible window of
      this process has title P81 window B") while Windows was building P75,
      then replayed to the end twice. Window B can take longer than the file's
      3 s; and the final capture is of window A only, so the sheet's placement
      is not in the image.
      **FIXED 2026-10-22, and "replayed to the end twice" above was wrong.** Those
      runs never pressed the sheet button: XdotoolSynthesiser.prepareForReplay
      forgot the focused window, and the replay loop calls it again when `focus`
      changes the target, so window B's click used window A's geometry (the log
      showed A's frame after "target window changed"). The forget moved to
      finishReplay; `focus` also waits up to 5 s for the window; test_P81.zsh sets
      TEST_FINAL_CAPTURE=desktop. A desktop capture now shows "sheet from window
      B" over window B. P1-open-root-sheet, the only other WSL file with a `focus`
      row, re-measures sheet and main window correctly and still passes.
      **2026-10-22 已修正，且上面「之後兩次都跑完」是錯的。** 那兩次從未按到 sheet 按鈕:XdotoolSynthesiser.prepareForReplay
      把聚焦的視窗忘掉，而 `focus` 改變目標時重放迴圈會再呼叫它，於是給視窗 B 的點擊用了視窗 A 的座標。清除改到 finishReplay;
      `focus` 也會等視窗最多 5 秒;test_P81.zsh 設定 TEST_FINAL_CAPTURE=desktop。桌面截圖現在看得到視窗 B 上的「sheet from
      window B」。另一個有 `focus` 列的 WSL 檔 P1-open-root-sheet 仍然通過。
    - P26 from inside WSL: `capture_gtk.zsh --wsl P26` run IN WSL fails twice at
      test_P26.zsh's appCache checks ("index has two headers and one record:
      expected 3, got 0") and skips the GUI run, while the same command run
      from Windows passes and captures. test_P26.zsh calls wsl.exe itself, so
      running it inside WSL goes back out through interop; the deck capture was
      taken from Windows.
      P26 在 WSL 內部執行 capture_gtk.zsh 時，兩次都在 test_P26.zsh 的 appCache 檢查失敗並略過 GUI;同一個指令從 Windows 端
      執行則通過並拍到。test_P26.zsh 自己會呼叫 wsl.exe,在 WSL 內執行等於經 interop 繞出去再回來；簡報的截圖改從 Windows 端拍。
      **FIXED 2026-10-22:** test_P26.zsh runs its steps with `zsh -lc` when it is
      already inside WSL; `capture_gtk.zsh --wsl P26` in WSL then exits 0.
      **2026-10-22 已修正:** test_P26.zsh 已在 WSL 內時直接以 `zsh -lc` 執行；在 WSL 內的 capture_gtk.zsh P26 以 0 結束。
    2026-10-22 的 WSL sweep:134 個 WSL 動作檔全部以 X11 加 `GTK_CSD=1` 跑過，除了 P81 的一次之外都重放到結尾;宣告通過條件的 14 個中，sweep 能判定的 13 個
    全部 met(P54 是 `expect: screenshot`,靠人看)。剩兩項待查:P6-v2-transport-toggles 重放完成，但最後那次截圖找不到視窗，`GTK_CSD` 開或關皆然(一般執行正常，
    簡報不受影響);P81 在 sweep 中失敗一次(視窗 B 晚於 3 秒才出現，當時 Windows 正在建置 P75),之後兩次都跑完，但最後截圖只拍到
    視窗 A,看不到 sheet 的位置。
  - [x] **GTK drew P89's 14 x 14 stroked Circle as a rounded square** (fixed -> completed.md (archived 2026-10-18)

## 2026-10-09 SVG in Image (user request, priority one)

- [x] **Image renders SVG with a pure-Swift renderer in the core** (Mac side).
  `Sources/SwiftCrossUI/SVG/`: own XML reader (FoundationXML exists in the
  Android 6.4.0 SDK too, but would add libxml2 + libFoundationXML to every
  APK/Windows bundle), path data (all commands, arcs), shapes, transforms,
  CSS (`style`, simple `<style>` selectors), colours, nonzero/evenodd,
  stroker (caps, joins, miter limit, dashes), 16-subsample scanline AA,
  group opacity. `Image(url)` picks it by `.svg` or by sniffing;
  `Image(SVGDocument)`, `.svgRasterSize(width:height:)`; re-rasterised at
  displayed size x scale, last 4 sizes cached. Anything not drawn is in
  `SVGDocument.diagnostics`, logged once, outlined in magenta plus a corner flag.
  Found on the way: AppKit, UIKit, Android and WinUI read `updateImageView`
  bytes as premultiplied while ImageFormats gives straight alpha (AppKit
  measured: (200,0,0,128) over white -> (255,127,127), correct 227); all four
  now premultiply (`ImagePixels`). SVGTests: 27 tests incl. golden vs CoreSVG.
  P84 (new): six action files each on macOS, iOS simulator, Android emulator,
  every capture read.
  - [x] **Windows side: P84 on WinUI, GTK (Windows) and WSL.** The WinUI
    premultiply edit in `WinUIBackend.updateImageView` has never been
    compiled. Coordinates for `actions/win/` still to be measured.
    **DONE 2026-10-20**: compiled and drawn; the seven files for each of WinUI, Windows GTK (`-gtk4`) and WSL, measured and replayed -- features-alpha reads max 64, mean 0.104 on all three, as on macOS.
  - [x] **GTK on macOS: P84 verified 2026-10-09** (gtk4 4.24.1, libepoxy
    1.5.10, graphene 1.10.8, pango 1.58.2, gdk-pixbuf 2.44.8, librsvg 2.63.2
    via `testapp/install_tool_mac.zsh`). `compile.zsh -gtk4` now works on
    macOS (Homebrew branch; output `P84-gtk4`; AppKitBackend dropped, since
    DefaultBackend prefers `canImport(AppKitBackend)` and a stale module made
    the second build an AppKit app). `TEST_BACKEND=gtk4 test.zsh Pn --macos`
    runs it. Seven files `actions/mac/P84-*-gtk4.actions`, every capture read:
    same difference numbers as macOS (boards max 14, features max 64 mean
    0.104), larger/smaller sizes, sample 5's six diagnostics. Clicks: posted
    NSEvents reach GDK as press/release but never fire a GtkButton, so
    AppKitSynthesiser now sends GDK windows HID clicks (move, 150 ms, down,
    150 ms, up; needs the Accessibility grant). Premultiplied alpha: GTK is
    right as it is (straight bytes into GdkPixbuf); `GtkImageAlphaTests` pins
    (200,0,0,128) -> premultiplied (100,0,0,128) = (227,127,127) over white,
    and on screen the 0.5 rects read src*a + bg*(1-a) on both images.
  - [x] **SVG features not drawn before 2026-10-10** -- all drawn now (sub-items below).
    What stays reported and outlined is refused on purpose: `<image>` of a file outside
    the document's folder or on the network, and a filter holding an element SVG does not
    define. Gradients, clipPath, mask, patterns, markers, images and every SVG 1.1 filter
    primitive are drawn since 2026-10-10; P87 shows the common ones together.
    - [x] **Visible `<text>`: drawn by each platform's own text engine** -> completed.md (archived 2026-10-18)
    - [x] **WinUI: SVG text.** `BackendFeatures.SVGText` on WinUIBackend, e.g.
      Win2D `CanvasRenderTarget` + `CanvasTextLayout` drawn white on a
      transparent target and read back as alpha; then P85 on WinUI (and GTK on
      Windows/WSL, which already has the PangoCairo path but has not been run).
      **DONE 2026-10-20** with DirectWrite + Direct2D rather than Win2D (WinUIInterop/svg_text_mask.cpp, WinUIBackend+SVGText.swift): P85 passes on WinUI, and on Windows GTK and WSL (their first runs).
    - [x] **Gradients: `linearGradient` and `radialGradient`** (2026-10-10), in -> completed.md (archived 2026-10-18)
    - [x] **`clip-path` and `mask`** (2026-10-10), in the core rasteriser: the -> completed.md (archived 2026-10-18)
    - [x] **`<pattern>` paint** (2026-10-10), in the core rasteriser: the tile -> completed.md (archived 2026-10-18)
    - [x] **Markers: `marker-start`, `marker-mid`, `marker-end`** (2026-10-10), -> completed.md (archived 2026-10-18)
    - [x] **`<image>` with a `data:` URI** (2026-10-10): PNG, JPEG and the -> completed.md (archived 2026-10-18)
    - [x] **`<image>` of a file, and of an SVG** (2026-10-10). A document read -> completed.md (archived 2026-10-18)
    - [x] **Filters, the common subset** (2026-10-10), run on the element's -> completed.md (archived 2026-10-18)
    - [x] **The rest of the SVG 1.1 filter primitives** (2026-10-10): feMorphology, -> completed.md (archived 2026-10-18)
  - [x] **`Mesh3D.opacity`: translucent meshes** (2026-10-10), for SoftPCB's
    air box (a very light, highly transparent grey, the user's choice). Below 1
    a mesh blends source-over, is depth-tested and writes no depth; translucent
    meshes are drawn after every opaque one, in array order among themselves.
    Metal (AppKit/UIKit) takes the opacity as a uniform; GTK and Android carry
    it as 255 x transparency in bits 8-15 of the existing per-mesh flags, so no
    C or JNI signature changed. P86 (new: a red square in front of a 50% veil
    stays pure red, a blue square behind one turns light blue, a yellow strip
    behind the veil still shows) passes on macOS, GTK on macOS, the iOS
    simulator and the Android emulator. Open:
    - [x] **WinUI: `Mesh3D.opacity`.** WinUIBackend+Mesh3DView ignores it and
      draws translucent meshes opaque. Needs a blend state (src-alpha /
      one-minus-src-alpha), a depth state that tests without writing, the
      opacity in the pixel shader, and the two passes; then P86 on WinUI.
      **DONE 2026-10-20**: all four, as listed; P86 passes on WinUI, Windows GTK and WSL. The same run found the D3D view drawn 1.25x too large and cut off at 125% -- the swap chain now gets the inverse rasterisation scale (`RawD3D11Device.setCompositionScale`).

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

- [x] **Android: `BackendFeatures.IncomingURLs` is not implemented.** It is part -> completed.md (archived 2026-10-18)
- [x] **File dialogs never filter by type, on any platform.** The core never sets
  it: `PresentSingleFileOpenDialogAction.swift:54`, `PresentMultipleFileOpenDialogAction.swift:73`
  and `PresentFileSaveDialogAction.swift:49` all pass `allowedContentTypes: []`,
  and `DocumentGroup` does not hand its `FileDocument`'s readable types to the
  open dialog. Backends: Android maps them to MIME types; UIKit has `TODO(#235)`
  (`UIKitBackend+FilePicker.swift:37`); AppKit ignores them in both panels
  (`AppKitBackend.swift:1764`, `:1803`); GTK and WinUI never read the field.
  Needs a public API first, then the three backends. DONE 2026-10-06 except
  WinUI's run: `chooseFile`/`chooseFiles`/`chooseFileSaveDestination` take
  `allowedContentTypes` and `allowOtherContentTypes`; `openDocument` exposes
  `readableContentTypes` / `writableContentTypes`. AppKit sets the panels'
  `allowedContentTypes`, UIKit passes the type identifiers to the picker (and
  names an exported file with an allowed extension), GTK adds a `GtkFileFilter`
  per type, WinUI fills `fileTypeFilter` / `fileTypeChoices`. P62 has an
  "open…" button; actions/{mac,ios}/P62-open-dialog-filters.actions: on macOS
  not-text.png is greyed (it was selectable with the old AppKit code), on iOS
  too; also-text.swift stays selectable on both, correctly -- Swift source
  conforms to plain text. GTK compiled only (no open panel driven).
  - [x] **WinUI: compile and run the file-dialog filters.** DONE 2026-10-07, -> completed.md (archived 2026-10-18)
  - [x] **WinUI: the save dialog ignores `defaultFileName`** -- FIXED 2026-10-07 -> completed.md (archived 2026-10-18)
  - [x] **Android: plain-text open hides source files such as also-text.swift.** -> completed.md (archived 2026-10-18)
  - [x] **Android: a document chosen in the open dialog cannot be read.** Found -> completed.md (archived 2026-10-18)
  - [x] **`DocumentGroup`'s doc says it opens through the open dialog and
    writes back through the save dialog; it does neither.** It only registers
    `newDocument` / `openDocument(url)`; nothing saves a document. Either the
    doc or the scene is wrong. FIXED 2026-10-06, the scene: `saveDocument()`
    (environment action in every document window) writes to the file, or
    through the save dialog (writableContentTypes, "<title>.<ext>") when
    untitled or `saveAs: true`; the window takes the file's name. P62 gains
    "save"; actions/mac/P62-save-untitled.actions: type A, save, Return ->
    "save -> true", window titled Untitled.txt, the file holds "A". P62 passes
    `saveDocument(initialDirectory:)` a fresh temp folder, so a sweep neither
    litters ~/Documents nor meets a "replace?" prompt.
    The doc now says what the scene does.
- [x] **AppKit: `Slider` ignores `decimalPlaces`** (`AppKitBackend.swift:978`,
  "TODO: Implement decimalPlaces"). DONE 2026-10-06, 585788b5: rounded as UIKit
  does. P61 now logs the unformatted value; actions/mac/P61-drag-then-code.actions
  read 0.10666666666666667 before, 0.11 after. "The other four read it" was
  wrong -- WinUI does not either (next item).
- [x] **WinUI: `Slider` ignores `decimalPlaces`** (`WinUIBackend.swift:1907`,
  `decimalPlaces _: Int`). Found 2026-10-06 while fixing AppKit. Round in the
  ValueChanged handler as UIKit and AppKit do. Windows machine.
  DONE 2026-10-07: `updateSlider` wraps the change action, rounding with
  `.toNearestOrEven` to `decimalPlaces` (clamped 0...17), the AppKit code.
  P61 on WinUI (actions/win/P61-drag-the-trough.actions, rerun by hand with
  SCUI_DEBUG_EVENTS_DIR): began=1 ended=1 values=1, "value 0.81" from the drag,
  "value 0.91" from the code button. This run does NOT discriminate: WinUI's
  `stepFrequency` is 0.01, so a drag already lands on a hundredth and 0.81 is
  exact in Double either way. A value such as 57 * 0.01 = 0.5700000000000001
  would show it; not reached by this file.
  2026-10-07 完成：比照 AppKit 依 `decimalPlaces` 四捨五入。P61 讀到 0.81 與 0.91,但這次執行
  無法區分修改前後——`stepFrequency` 為 0.01,拖曳本來就落在百分位上。
- [x] **`Picker.inspect` is commented out on all five backends** -> completed.md (archived 2026-10-18)
- [x] **UIKit: `preferredColorScheme` on the window -- verify.** `updateWindow` -> completed.md (archived 2026-10-18)
- [x] **Android TODOs to verify, each a possible gap:** navigation titles -> completed.md (archived 2026-10-18)
- [-] **The csv2 rule (CLAUDE.md) in the tools that still use Python's csv:** -> completed.md (archived 2026-10-18)

- [x] **macOS sweep leaves the UI lock held after a failed run** (2026-10-07). -> completed.md (archived 2026-10-18)

- [x] **PENDING by the user (2026-10-13: "it is ok, put this in pending") -- not to be worked on until asked.** **Closed 2026-10-23: the user keeps it as the desired design ("Leave it as desired-design"); not a defect to fix. The record below is kept as written.**
  使用者 2026-10-13 指示擱置,未被要求前不處理。**2026-10-23 結案：使用者決定維持現狀，視為預期的設計("Leave it as desired-design");以下紀錄保留原文。**
  **Android: everything a test app draws comes out at 92.5% brightness** (found
  2026-10-09, SoftPCB-mac on P85). Every channel is multiplied by ~0.9255:
  P85's SVG background #fffbe6 shows as (236,232,213), the decor view's white
  (#ffffffff, set by setWindowBackground) shows as (236,236,236) -- the grey
  "Android background" in every capture since at least 2026-10-05 -- and the
  Material3 colorBackground (255,251,254) as (236,232,235). The status bar and
  the system Settings app show true white, so the device is not dimmed.
  Ruled out: the pixels (Android receives 255,251,230,255), any view with alpha
  < 1, a foreground or a hardware layer (walked from the decor view), the
  window's LayoutParams (no alpha, no DIM_BEHIND), SurfaceFlinger
  (dimmingRatio 1.0; the two Dim layers are hidden), and screencap (the macOS
  emulator window shows the same 236). Cause not found yet.

### Windows side (GTK and WinUI)

- [x] **Five optional features declared by neither GTK nor WinUI:** `ContextMenus`, -> completed.md (archived 2026-10-18)
- [x] **Picker styles:** GTK lacks `.wheel` (`supportedPickerStyles`, -> completed.md (archived 2026-10-18)
- [x] **WinUI parity TODOs:** date picker ignores the foreground colour
  (`WinUIBackend.swift:3202`), font design / monospace (`:1540`), picker font
  (`:2033`), no notification when the window's scale factor changes (`:1151`),
  fullscreen not detected (`:726`). GTK: button label colour from the environment
  (`GtkBackend+Button.swift:17`) -- GTK DONE 2026-10-07, no change needed: the
  TODO was stale. `updateSimpleButton` already sets `cssProperties`, whose
  `color` the label inherits; on GtkBackend (macOS) Menu labels drew red, blue,
  orange from a parent, and a disabled green dimmed. The TODO is replaced by
  that note. WinUI items remain (Windows session).
  **WinUI 2026-10-07 (Windows): four of five driven, the scale change is not:**
  - foreground colour on date pickers: P41 with a temporary
    `.foregroundColor(.red)` (reverted) -- DatePicker, TimePicker, `.compact`
    date, seconds box and the graphical month header and days all red; with it
    removed, the theme's colours return. `Foreground` alone reached only the
    DatePicker and TimePicker. The others needed `CalendarItemForeground` and
    painting the text blocks inside the templates. Overriding the
    `CalendarDatePickerTextForeground` / `ComboBoxForeground` resources did
    nothing.
  - font design: `.monospaced` maps to "Cascadia Mono, Consolas, Courier New"
    in both `apply(to:)`; P74 (temporary edit) drew "1111 WWWW iiii" in equal
    columns beside a proportional line. Italic is now also cleared, not only set.
  - picker font: the TODO was stale -- `apply(to: picker)` already ran; P74's
    menu picker with `.font(.system(size: 22).italic())` showed 22 pt italic
    closed and in all three drop-down items.
  - scale-factor change: `WM_DPICHANGED` in the window procedure recomputes the
    window environment on the next main-queue turn. **NOT DRIVEN -- this item
    stays open for it.** The machine has one display (1920x1080, 96 DPI, read
    with `GetDpiForMonitor`), so there is nowhere to drag the window to, and
    changing the scale in Settings would disturb the live session. Drive it by
    dragging P42 to a display with another scale and reading its
    "scale factor ->" line.
  - fullscreen: `isWindowProgrammaticallyResizable` answers
    `presenter.kind != .fullScreen`. ~~BUILT ONLY: nothing in SwiftCrossUI puts a
    WinUI window into full screen to drive it.~~ Wrong -- the app can do it
    itself (pointed out by the Mac session). Driven the same evening with a
    temporary P74 edit (reverted) calling `AppWindow.setPresenter(.fullScreen)`:
    presenter read back full screen, the window 0,0 1920x1080, and it stayed
    there through two relayouts (wheel -> Sun, segmented -> Three); `.default`
    returned it to 536x659.
  WinUI 項目：日期選擇器前景色、等寬字型、picker 字型(TODO 已過時)、全螢幕偵測已驅動驗證;**縮放變更未驅動**
  (這台只有一台 96 DPI 的螢幕),因此本項維持未勾。
  **Scale change DRIVEN 2026-10-20 (Windows), item closed.** The display scale was changed live with
  SPI_SETLOGICALDPIOVERRIDE (125% -> 150% -> 125%, restored) while P42 --debug ran: WinUI and Windows GTK
  both logged scale factor 1.25 -> 1.5 -> 1.25 (changes 2-4, after a 1.0 before the window existed).
  **縮放變更已於 2026-10-20 驅動驗證，本項結案。**以 SPI_SETLOGICALDPIOVERRIDE 即時改縮放(125%→150%→125%,已還原):WinUI 與 Windows GTK 都記到 1.25→1.5→1.25。
- [x] **`Button(_:role: .destructive)` changes nothing on any backend** (found -> completed.md (archived 2026-10-18)
## 2026-10-12 API gaps P31 still names: `.focusable` and `CommandGroup`

P31's "Missing APIs" line named six. Checked against `Sources/SwiftCrossUI` on
2026-10-12, four exist -- `@FocusState` and `.focused` (#122, P70),
`.keyboardShortcut` and `KeyEquivalent` (#121, P71) -- and the line in `P31.swift`
now says so. The two below do not exist. They were not written then because the
question was whether the line was still true; the user asked for them to be queued.
Each is a feature for all five backends (CLAUDE.md), not a line in one file.

P31 的「Missing APIs」那一行原本列了六項。2026-10-12 對照 `Sources/SwiftCrossUI`,四項已存在——`@FocusState` 與
`.focused`(#122,P70)、`.keyboardShortcut` 與 `KeyEquivalent`(#121,P71)——`P31.swift` 的那一行也已改成這樣寫。
下面兩項不存在。當時沒有動手寫，因為問題是「那行字還對不對」;使用者要求把它們排進來。每一項都是五個 backend 都要做的
功能(CLAUDE.md),不是某個檔案裡的一行。

- [x] **`.focusable(_:)` on WinUI** -- the rest is DONE 2026-10-13: `BackendFeatures.FocusableTargets` on
  AppKitBackend, UIKitBackend, GtkBackend and AndroidBackend, test app P91 with action files for macOS (AppKit and
  gtk4), iOS, iPad and Android, all replayed. WinUIBackend has no conformance, so `.focusable` warns once and changes
  nothing there (a Control with IsTabStop is the place to start); GtkBackend's is untried on Windows and WSL. The
  user asked for the non-Windows backends first.
  **WinUI DONE 2026-10-19** (3d3a3d70): `FocusableTargets` on WinUIBackend; P91 passes on Windows. Ticked 2026-10-20.
  Also changed with it: `.focused` acts on a disagreement only when the app asked for something new -- it used to
  take the focus back from a view the user had just pressed or tabbed to; a key target around a `.focusable()`
  view no longer takes the focus itself; a `key,tab` row on Android moves the focus as the view root does.
  WinUI 以外已於 2026-10-13 完成(四個 backend、測試 app P91、各平台動作檔皆已重放)。WinUIBackend 尚未實作，
  `.focusable` 在那裡只會警告一次;GtkBackend 的實作在 Windows 與 WSL 上尚未執行。使用者要求先做非 Windows 的 backend。
  Was: **`.focusable(_:)`** -- lets a view that is not a control take keyboard focus, so
  `@FocusState` / `.focused` and `onKeyPress` reach it. `grep -rn "func focusable"
  Sources/SwiftCrossUI` finds nothing. Wanted on GtkBackend, WinUIBackend,
  AppKitBackend, UIKitBackend and AndroidBackend, with a test app that tabs to a
  plain view and types into it (P70 is where focus is driven today).
  **`.focusable(_:)`**——讓一個不是控制項的 view 能取得鍵盤焦點，使 `@FocusState`/`.focused` 與 `onKeyPress`
  到得了它。`grep -rn "func focusable" Sources/SwiftCrossUI` 找不到任何東西。五個 backend 都要：GtkBackend、
  WinUIBackend、AppKitBackend、UIKitBackend、AndroidBackend,並要有一支測試 app 用 Tab 走到一個普通 view 再對它
  打字(目前驅動焦點的是 P70)。
- [x] **`CommandGroup`, as SwiftUI has it -- decided by the user on 2026-10-13, in progress.** (g) DONE 2026-10-20 on the Windows side: WinUI, Windows GTK and WSL match the SwiftUI reference in all five P92 modes, read back with `SCUI_DEBUG_MENU_DUMP=1`; WinUI's missing New Window fixed in `_App` (menus applied again once window openers exist).
  The decisions, in the user's words where quoted:
  1. Shape: "exactly the same" as SwiftUI -- `CommandGroup(replacing:)`, `before:`, `after:` and
     `CommandGroupPlacement`. Where there is no SwiftUI to copy (GTK, WinUI, Android), "use swift code to
     mimic the UI": the menus are built by this framework, in Swift.
  2. Order: macOS -> GTK -> iOS -> Android, all on the Mac. "Leave windows and WSL be done on windows."
  3. The baseline is measured, not remembered: a real SwiftUI app whose menu bar is dumped, on macOS and on
     iPad, and the iPhone's behaviour looked at the same way.
  4. "Default behavior stays the same": no menu bar appears on GTK or WinUI, and nothing visible on a phone,
     unless the app asks. "User shall be able to enable menu by calling enableMenu or set that as variable to
     be true."
  5. The default items (Undo, Redo, Cut, Copy, Paste, Select All and the rest) on GTK, WinUI and Android are
     under the same switch -- "this is tunable" -- and are implemented in Swift.
  6. WinUI is written from the Mac and run on the Windows side.
  7. All twenty placements, not a first nine: "All shall be included in the first demo app on macOS."
  8. DECIDED 2026-10-13, "follow SwiftUI": `CommandMenu("File")` is no longer merged into the default File
     menu by title (AppKit and UIKit did that). What SwiftUI does with a same-named menu is taken from the
     reference app, not from memory; putting items into a system menu is `CommandGroup`'s job.
  DONE 2026-10-13: (a), (b), (c) -- AppKit's menu bar equals the SwiftUI dump in all five modes of P92;
  (d) GtkBackend on macOS -- `BackendFeatures.StandardCommands` in Swift, menus read and pressed through
  System Events, switch off and on. On macOS GTK adds an app menu of its own before the framework's.
  (e) DONE 2026-10-14: the iPad baseline was read after all -- the system builds the menu bar only once a key
  or the pointer arrives, so the reference app was run under the action-file runner -- and UIKitBackend
  builds the bar the same way; the phone gets a menu button with enableMenu. (f) DONE 2026-10-14: Android's
  menu button and standard commands. (g) is the hand-over to the Windows side.
  The note that stood here, kept for the record: a SwiftUI reference app runs on the iPad simulator, but
  its menu could not be read on 2026-10-13 -- `buildMenu(with:)` on a `UIApplicationDelegateAdaptor` delegate was
  never called, and neither was UIResponder's own implementation after it was wrapped and
  `UIMenuSystem.main.setNeedsRebuild()` sent, in 25 s. Known from the compiler: `windowList` and
  `singleWindowList` are unavailable on iOS, so iOS has eighteen placements. Still to try: XCUITest's view of
  the iPad menu bar. UIKitBackend also still replaces a system menu by a `CommandMenu` of the same name
  (`mapMenuIdentifier`), which is the merge the user decided against.
  Steps: (a) reference dump from real SwiftUI, (b) the core types and the resolution of groups into menus,
  (c) AppKitBackend and a demo app with all twenty placements, (d) GtkBackend on macOS, (e) UIKitBackend on
  iPad and iPhone, (f) AndroidBackend, (g) hand WinUIBackend and GTK on Windows/WSL to the Windows side.
  `CommandGroup`,照 SwiftUI 的形狀——使用者 2026-10-13 決定，進行中。決定:形狀與 SwiftUI 完全相同;沒有 SwiftUI 可對照的
  平台(GTK、WinUI、Android)由本框架以 Swift 建出選單;順序 macOS -> GTK -> iOS -> Android,都在 Mac 上做，Windows 與
  WSL 留給 Windows 端;基準要實測(真正的 SwiftUI app 傾印選單列);預設行為不變，GTK/WinUI 不出現選單列、手機上不顯示
  任何東西，除非 app 呼叫 enableMenu 或把變數設為 true;預設項目(Undo、Copy、Paste 等)同樣由這個開關控制並以 Swift 實作;
  二十個位置全部要，第一支示範 app 在 macOS 上就要包含全部。`CommandMenu("File")` 依標題合併的行為:2026-10-13 決定
  「follow SwiftUI」,不再合併;SwiftUI 對同名選單的實際做法以參考 app 為準。
  Was: **`CommandGroup`** -- placing menu commands relative to the system's own groups
  (`CommandGroup(replacing:)`, `before:`, `after:`). Menus go through
  `.commands { }` (`Scenes/Modifiers/CommandsModifier.swift`) with `CommandMenu`
  only; there is no `CommandGroup` type. Wanted on the same five backends; on iOS
  and Android, where there is no menu bar, the first thing to settle is what a
  command group maps to (P19, P20 and P71 are where menus and shortcuts are shown).
  **`CommandGroup`**——把選單指令放在系統自有群組的相對位置(`CommandGroup(replacing:)`、`before:`、`after:`)。
  選單目前經由 `.commands { }`(`Scenes/Modifiers/CommandsModifier.swift`),只有 `CommandMenu`;沒有
  `CommandGroup` 這個型別。同樣五個 backend 都要;iOS 與 Android 沒有選單列，第一件要定的是指令群組對應到什麼
  (選單與快捷鍵目前顯示在 P19、P20 與 P71)。

## 2026-10-12 open after the origin rule (a5ccf75d, c1431f14) -- iOS and Android

A layout larger than the screen now starts at its root view's frame instead of
at the blank the centring left (user, 2026-10-11, from P50). It moved far more
than P50: most apps ask for a layout taller than a phone and sat vertically
centred in it. Measured by comparing each app's capture before and after.

比螢幕大的版面現在從根 view 的外框開始，而不是從置中留下的空白開始(使用者,2026-10-11,起因是 P50)。
受影響的遠不只 P50:多數 app 要求的版面比手機高，原本垂直置中在裡面。以下是比較每個 app 前後擷取圖量出來的。

- [x] **Action files re-aimed** -- iOS on 2026-10-12 (87c61a0e, 9f733bbc: 86 + 7 iPhone files), Android on
  2026-10-13 (d50a2a15, 529ad4ed, 56a37654), the iPad files on 2026-10-13. `testapp/reaim_android.zsh` keeps
  the Android procedure. iOS 於 2026-10-12、Android 與 iPad 檔案於 2026-10-13 重新瞄準完成。
  Was: **iOS and Android action files measured before 2026-10-12 are stale wherever the
  content moved.** About 60 apps moved on at least one platform: up by 60-290 pt
  (P0, P1, P4, P5, P7-P12, P52-P83, P85), left by 6-150 pt (P13, P15, P17-P20,
  P28-P30, P34, P37-P43, P47, P50, P86, P89). Unmoved on both: P14, P16, P21-P26,
  P31-P33, P35, P36, P44-P46, P48, P51. Each moved app's `actions/ios` and
  `actions/android` files need their coordinates re-measured and a replay; a click
  made at rest moves by the same amount as the content, one made after a scroll
  does not, because the scroll range changed too.
  凡是內容移動過的 app,2026-10-12 之前量的 iOS 與 Android 動作檔座標都過期了。約 60 個 app 至少在一個平台上移動：
  上移 60-290 pt、左移 6-150 pt(清單見上)。兩邊都沒動的：P14、P16、P21-P26、P31-P33、P35、P36、P44-P46、P48、P51。
  每個移動過的 app 的 `actions/ios` 與 `actions/android` 檔案都要重量座標並重播；靜止時的點擊與內容移動同樣的量，
  捲動之後的點擊則不然，因為可捲範圍也變了。
- [x] **The mode button covers the start of the first line** on both platforms now
  that content starts at the top-left; the centring blank used to clear it. Waiting
  on the user. 內容貼到左上角後，模式按鈕在兩個平台上都蓋住第一行開頭；以前是置中的空白讓開它。等使用者決定。
- [x] **P89 leads by 40 pt on iOS and 16 dp on Android**: its 440-wide layout fits
  the iPhone and not the 411 dp emulator. Waiting on the user.
  P89 在 iOS 左邊 40 pt、Android 16 dp:它 440 寬的版面塞得進 iPhone、塞不進 411 dp 的模擬器。等使用者決定。
- [x] P74: the wheel is about 50 dp wide on Android and about 220 pt on iOS.
  P74:滾輪在 Android 約 50 dp 寬，iOS 約 220 pt。
- [x] P53: Android's toolbar is a row of text buttons; iOS shows symbols in the bar.
  P53:Android 的工具列是一列文字按鈕;iOS 在導覽列顯示圖示。
- [x] P57: `rows built / held` reads 0 / 0 on Android at launch and 4 / 4 on iOS.
  P57:`rows built / held` 啟動時在 Android 是 0 / 0,iOS 是 4 / 4。

Closed 2026-10-12, verified on both by capture (P89, P53, P57, P74, P50, P14, P0): content that
would start under the mode button starts below it, and on iOS the button follows the host
under a navigation bar; a root that fits the screen is centred on it when the layout does
not (the user's rule for P89 -- 24 pt a side on iOS, 9.5 dp on Android); the Android wheel
asks for 320 x 216 dp; the Android toolbar shows symbols, leading left and the rest right;
P57 re-reads its counters once after the first frame. The action files are still stale, and
the button clearance moved content down again wherever it applied.
2026-10-12 結案，兩邊都以擷圖驗證(P89、P53、P57、P74、P50、P14、P0):會從模式按鈕底下開始的內容改從按鈕下方開始，
iOS 的按鈕在有導覽列時跟著 host 下移；版面塞不下但根塞得下時，根置中在螢幕上(使用者為 P89 定的規則——iOS 每邊 24 pt、
Android 9.5 dp);Android 滾輪改要 320 x 216 dp;Android 工具列顯示符號，前導靠左、其餘靠右；P57 在第一個畫面後重讀一次計數。
動作檔仍然過期，而且凡是套用了讓開按鈕的地方，內容又往下移了一次。

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
  `P76-projection.actions`; `Mesh3DTests` added.
- [x] **iOS builds without Swift Bundler by default.** `compile.zsh -ios` runs -> completed.md (archived 2026-10-18)
- [x] **Android: the GLES path for the same options.** DONE 2026-10-05, built with -> completed.md (archived 2026-10-18)
- [x] **Render time in microseconds, off by default.** `Mesh3DScene.measuresRenderTime... -> completed.md (archived 2026-10-18)
- [x] **`P72-stop-and-check.actions` on Android missed every target since the api36b
  AVD.** That AVD's renderer string is three lines, not five, so the controls sit
  about 62 pt higher; "Stop" landed on Snapshot and the readout stayed at
  "frames at the stop: -1" with nothing failing. Re-measured: stop 190, check 193.
- [x] **GTK and WinUI: no `Mesh3DViews` at all yet** -- Windows side. (Box ticked 2026-10-20: both conformances exist, as the DONE notes below say; the title had not been updated.)
  GTK DONE 2026-10-06: a GtkGLArea (`Gtk.Mesh3DGLView`) drawing with core GL 3.3
  through libepoxy (GtkCHelpers/gtk_mesh3d_gl.c, the NV12 renderer's footing),
  AndroidBackend's shaders and packing with 32-bit indices; snapshots read the
  framebuffer back in device pixels. Run on GtkBackend on macOS (Apple M4 /
  4.1 Metal): P72 cube lit and spinning, Snapshot 680x480 5 colours and the
  PNG upright; P76 all six claims (lines, 9x9 points, unlit vs shaded, overlay
  through the left cube only, ortho ticks, cyan helix); P77 1,002,001 vertices
  as one smooth gradient. Not yet run on Linux or Windows GTK. NOTE for an
  incremental build elsewhere: the new header in GtkCHelpers/include was not
  seen until the stale GtkCHelpers-*.pcm module cache was deleted
  ("cannot find scui_mesh3d_renderer_new in scope"). WinUI remains.
  **WinUI DONE 2026-10-07** (WinUIBackend+Mesh3DView.swift): Direct3D 11 into a
  SwapChainPanel (the existing `RawSwapChainPanel` / `RawD3D11Device`), HLSL
  compiled at run time with `D3DCompile` (the GL shaders, same packing and
  lighting), depth 0...1, points as geometry-shader quads (D3D11 has no point
  size), per-mesh lit/depthTested, geometry re-uploaded only when the arrays
  change, snapshot from the back buffer through a staging texture, render time
  to GPU completion with an event query. This session has no GPU (the renderer
  reads "Microsoft Basic Render Driver", i.e. WARP), and on it: P72 cube lit and
  spinning, frames counting, Snapshot 340x240 4 colours, PNG upright; P76 all six
  claims (three ticks 30/30/30 px in orthographic, unequal in perspective); P77
  1,002,001 vertices as one smooth gradient, render time 76,680 us on WARP.
  **Windows GTK: a crash found and fixed, drawing NOT verified.** P72-gtk4 died
  at realize (rc 139; lldb: `g_type_check_instance_is_fundamentally_a(0x200000003)`
  under `create-context`): the generated GLArea binding connected a VOID
  handler to that pointer-returning signal, so GTK took the return register's
  leftovers as the GL context -- on macOS by luck it survived. GtkCodeGen now
  excludes `create-context`, and GLArea.swift no longer connects it. After the
  fix P72 runs, but the GL area shows "No GL implementation is available": WGL
  here gives only "GDI Generic" OpenGL 1.1 (probed directly), so a GL 3.3 mesh
  cannot draw in this session. Rerun P72/P76/P77 -gtk4 at a session with a real
  GPU. WSL GTK: not run yet.
  **Later the same evening -- why WARP and GDI Generic, and both mostly fixed.**
  Not a session problem: the tests run in session 2 "Console" beside
  explorer.exe. The registry lists two adapters with drivers, NVIDIA GeForce RTX
  4060 Laptop (32.0.16.1742) and AMD Radeon (32.0.11038.3), but DXGI lists
  "Microsoft Basic Render Driver" first with the only output (\\.\DISPLAY1,
  "Microsoft Basic Display Driver"), the RTX 4060 second with none, and no AMD
  adapter at all -- the integrated adapter that drives the panel has dropped to
  the basic display driver. The default D3D adapter is therefore WARP, and WGL on
  that display is GDI Generic. (Probe: scratch adapters.c, EnumAdapters1 +
  EnumDisplayDevices.)
  - WinUI now picks a hardware adapter when the default one is software
    (`-GPU 0` keeps WARP): P72 reads "NVIDIA GeForce RTX 4060 Laptop GPU /
    Direct3D 11", cube drawn, frames counting; the swap chain on the RTX still
    composes on the basic display. P77 render time 30,107 us (WARP: 76,680).
  - **WSL GTK DONE:** under WSLg GTK makes an OpenGL ES 3.0 context (Mesa
    d3d12 on the RTX 4060), which rejected the "#version 330 core" shaders, so
    the view was blank with nothing reported. The version line is now chosen per
    context (330 core / 300 es), and a shader failure is reported once on stderr.
    P72 "D3D12 (NVIDIA GeForce RTX 4060 Laptop GPU) / OpenGL ES 3.1", cube lit
    and spinning; P76 all six claims; P77 one smooth gradient.
  - Windows GTK drawing stays unverified: WGL follows the display adapter, and
    that is the basic display driver until the AMD adapter works again.
  - Found on the way: twice tonight `test.zsh --wsl` printed a WSL build error
    and still returned 0 and ran the previous binary. FIXED 9cd24054 (run_build),
    verified on --macos, --windows and --wsl.
  傍晚稍後：WARP 與 GDI Generic 的原因已查明——內顯 AMD 退回 Basic Display Driver,預設 D3D 介面卡因此是 WARP。WinUI 現改用
  硬體介面卡(RTX 4060);WSL GTK 修正 GLES shader 後 P72/P76/P77 全部成立;Windows GTK 須等 AMD 介面卡恢復。
  WinUI 於 2026-10-07 完成(D3D11 + SwapChainPanel,在 WARP 上 P72/P76/P77 全部成立)。Windows GTK:修好一個崩潰(產生的
  GLArea binding 把 void 處理常式接到回傳指標的 create-context),但本工作階段只有 GDI Generic OpenGL 1.1,繪製未能驗證。
- [x] **Skip the per-commit geometry comparison.** Not needed, measured -> completed.md (archived 2026-10-18)

## 2026-10-01 open after the UIScene change (8272b7a2) -- in this order

1-4 first, in the order 4, 1, 2, 3 (the user's choice); the iPad plan after all four.

- [x] **4. Why the iOS executable says `sdk 15.0`.** DONE 2026-10-01. The Swift -> completed.md (archived 2026-10-18)
- [x] **1. Re-aim every iOS action file.** DONE 2026-10-01. Apps now run at -> completed.md (archived 2026-10-18)
- [x] **2. Write the missing action files.** iOS 14: P47 P48 P49 P51 P52 P58
  P59 P61 P62 P63 P64 P66 P68 P70 (captured 2026-09-30, but at the zoomed size
  -- re-measure). Android 20: P15-DARK P17-DOE P47 P48 P49 P51 P52 P59 P60 P61
  P62 P63 P64 P66 P67 P68 P69 P70 P73 (+ P6-v2, GTK-only, never).
  - [x] iOS: 16 files written 2026-10-01, measured from the native-size tree and -> completed.md (archived 2026-10-18)
  - [x] Android: all 20 written 2026-10-01/02, measured from uiautomator dumps and -> completed.md (archived 2026-10-18)
  - [x] **Re-aim the Android action files.** DONE 2026-10-02. Every file's taps -> completed.md (archived 2026-10-18)
  - [x] **Android per-frame update cost.** Re-measured 2026-10-04 on the new AVD -> completed.md (archived 2026-10-18)
  - [x] **Android: the first updates after launch.** Over 58 apps the Android -> completed.md (archived 2026-10-18)
  - [x] **Android: updates that create views are slow** (found 2026-10-05, -> completed.md (archived 2026-10-18)
  - [x] **Android vs iOS UI gaps (side-by-side of every app's latest capture,
    2026-10-04).** Fix order agreed: 1, 3, 2, then investigate 4 and 5.
    2026-10-05: ticked -- every item under it was already [x].
    - [x] 1. FIXED 2026-10-04 (CustomPopupWindow.showBeside + resolveEdge; new
      P50-arrow-edge-leading.actions). P50 `arrowEdge(.trailing)`: the panel is pushed up above the button
      and the arrow does not point at it. presentPopover places leading/trailing
      top-aligned with the anchor; Android shifts a panel that does not fit, and
      the arrow is computed for the unshifted position. Leading shares the code;
      Android has no leading file.
    - [x] 3. FIXED 2026-10-04 (CustomRadioGroup dims disabled options to 0.4). P74 disable... -> completed.md (archived 2026-10-18)
    - [x] 2. FIXED 2026-10-04 (TableContainer clips to its own frame). P23 table: a long c... -> completed.md (archived 2026-10-18)
    - [x] 4. NOT A DEFECT (measured 2026-10-04). Text in narrow places breaking -> completed.md (archived 2026-10-18)
    - [x] 5. NOT A DEFECT (measured 2026-10-04). P41 date pickers "clipped" on -> completed.md (archived 2026-10-18)
    - [x] iOS, the other way: P57's 500-row List built 29,718 rows on iOS against -> completed.md (archived 2026-10-18)
    - [x] Harness: P75-close-the-window's capture shows P17-DOE left behind by an -> completed.md (archived 2026-10-18)
    - [x] Android aim after the AVD change (2026-10-05). SoftPCB-mac found P72 -> completed.md (archived 2026-10-18)
  - [x] **Emulator GPU.** DONE 2026-10-04. AVD config pinned to -> completed.md (archived 2026-10-18)
  - [x] **Disk cleanup: testapp/cleanup.zsh** (2026-10-04). Report by default, -> completed.md (archived 2026-10-18)
  - [-] **CANCELLED 2026-10-04. Kotlin -> pure JNI rewrite (CustomSegmentedGroup etc.): ... -> completed.md (archived 2026-10-18)
  - [-] **CANCELLED 2026-10-04. swift-java method-ID cache (fork): deferred** -- not nee... -> completed.md (archived 2026-10-18)
  - [x] **Per-Pn performance table.** Only P52/P64/P66 report numbers. Proposed: -> completed.md (archived 2026-10-18)
  - [x] **Stack ideal width undercounts (P51).** FIXED 2026-10-01: commit-time -> completed.md (archived 2026-10-18)
- [x] **3. P5 on iPad: alerts on two windows at the same time.** DONE 2026-10-02.
  `actions/ios/P5-alerts-on-two-windows-ipad.actions`: the main window is asked for
  an alert in 3 s (P5's new button), the second window opens over it and shows
  its own, and the dumptree lists 'Alert A (Secondary)' and 'Alert A (Main)'
  together. Verified twice, and the control (no delayed press) lists only one.
  Windows are not moved or sized: the iPad Simulator's backboardd aborts in
  Metal ("invalid pixelFormat (0)") during window drags and scene restores, and
  no API sizes an iPad window. `# fresh-install` in an iOS action file now
  uninstalls first, so last run's windows are not restored. Runner: `screen`
  origin, `windowframes`, held slow drags, `taplabel` falls back to a
  non-hittable match (alert buttons report isHittable false).
  - [x] Android P5 re-aimed (2026-10-04, verified: Alert C on top). The AVD -> completed.md (archived 2026-10-18)

### Then: iPad testing (after 1-4)

How to run it is in `testapp/README.md` > Devices > iPad (and README_zhTW.md).

- [x] **Windowed mode.** DONE 2026-10-02: `test_support/ipad-windowed-apps.csv`. -> completed.md (archived 2026-10-18)
- [x] **P59 / P62 on iPad** (2026-10-03): `P59-two-windows-ipad.actions`,
  `P62-two-documents-ipad.actions`, read from the dumptree. P59 found a core bug:
  `Publisher.observeAsUIUpdater` kept ONE merge slot per publisher, so when two
  windows observed the same @AppStorage the second window's update was dropped
  as "merged" (window A stayed AA, B showed AAB). Now one slot per observer;
  verified twice, and full macOS (97/97) and iOS (103/103) sweeps compared
  capture by capture. `-ipad` files are skipped by the iPhone sweep.
- [x] **Mac input source.** Since 2026-10-03 the active input source is Zhuyin -> completed.md (archived 2026-10-18)
- [x] **P14 rotation on iPad** (2026-10-03): `P14-rotate-ipad.actions` -- proposed
  width 802 portrait, 1178 landscape, 802 again, read from the tree.
- [x] **P72 cursor on iPad** -- DONE 2026-10-13 on the iPad simulator, not "physical iPad only": the runner
  rests a synthesized pointer and captures during the rest. One crosshair request over the mesh view, none over
  the text; the captures show a drawn cross and the system pointer. Only `crosshair` was seen; a physical iPad
  with a trackpad is still untried. 2026-10-13 在 iPad 模擬器上完成:十字游標拍到了;實體 iPad 仍未試。
  Was: **P72 cursor on iPad: physical iPad only.** `P72-cursor-ipad.actions` and the
  runner's `hover` verb are ready, and UIKitBackend prints the pointer style the
  system asks for under --debug; but the Simulator delivers no hover to apps --
  neither the style request nor a UIHoverGestureRecognizer fired across two
  hovers the runner logged. Run it on an iPad with a trackpad.
- [ ] **(Low priority, user 2026-10-20) iPad action files**, named `<Pn>-<what>-ipad.actions`, measured on an iPad -- 14 exist (2026-10-20: P16 columns, P50 popover and P71 shortcuts added, pressed by label; all three pass). Earlier: six exist and all six
  were replayed on 2026-10-13 (P5, P14, P59, P62, P72-cursor, P75); the other apps have none.
  Was: measured on an iPad
  capture (834x1210 points, @2x: points = pixels / 2). One exists:
  `P75-close-the-window-ipad.actions` (verified).
- [x] **What to test on iPad** -- run 2026-10-13 on the iPad Pro 11-inch (M5) simulator: multi-window P5, P59
  and P62 pass; closing a window P75 passes (pressed by label; its point was stale); rotation P14 passes once the
  file switches to rwdView first (802 -> 1178 -> 802; in actualView the width is the default size both ways);
  pointer hover P88 and the cursor P72 pass (see above). Not on a physical iPad.
  2026-10-13 在 iPad 模擬器上跑過:P5、P59、P62、P75、P14、P88、P72 都通過;實體 iPad 沒有。
  Was: **What to test on iPad:** multi-window P5, P59, P62; closing a window
  P75 (done); pointer hover and cursors P72 (iPhone has neither); rotation P14.

## 2026-09-27 found while driving iOS

- [x] **Re-measure the iOS action files: most of them no longer aim at their -> completed.md (archived 2026-10-05)

- [x] **FIXED 2026-09-28 (the lost model; the over-eager re-creation remains).** -> completed.md (archived 2026-10-05)
- [x] **FIXED 2026-09-29: a re-layout reuses each node's kept body.** A node keeps -> completed.md (archived 2026-10-06)
- [x] **Core: a view's own @State change re-creates it from its parent, and an inline -> completed.md (archived 2026-10-05)

- [x] **Read every macOS capture against its file's assertion, as was done for iOS.** -> completed.md (archived 2026-10-05)

- [x] **WITHDRAWN 2026-09-28 -- not a defect.** Pop to root sets pushCount = 0 -> completed.md (archived 2026-10-05)

- [x] **Core crash, ViewGraphNode.swift:13 (`_widget!`): a publish that arrives -> completed.md (archived 2026-10-05)

- [x] **WITHDRAWN 2026-09-27 -- there is no defect; the entry below was wrong.** -> completed.md (archived 2026-10-05)

- [x] **CLOSED 2026-09-29 -- does not reproduce.** A long press held with the menu -> completed.md (archived 2026-10-06)

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
  **Narrator on WinUI DONE 2026-10-08 (Windows), heard by a person.** One step
  at a time, then replayed by `testapp/actions/win/P69-narrator-walk.actions`:
  Tab -> "Close, button" (not "X"); Tab -> "Delete, button", "Removes the file
  permanently"; Tab -> "Volume, button"; Caps Lock+0 -> "40 percent"; Caps
  Lock+Right -> "Half past twelve" (not "12:30"); Caps Lock+Right -> the
  Expected paragraph, the hidden "decorative" skipped. One gap: the value is
  UIA ItemStatus, which Narrator speaks only on Caps Lock+0, while VoiceOver
  says "Volume, 40 percent, button" unasked -- whether to expose it another way
  is open. Found on the way: the Win32 replay sent `0` inside a Caps Lock chord
  as a Unicode character (Narrator: "not a Narrator command"); it now tracks the
  keys it holds and sends a chord's keys as virtual keys. `# narrator: on` in an
  action file makes test.zsh start Narrator before the app, and the file turns
  it off at the end. Orca (WSLg) speech is still unheard.
  **WinUI 上的 Narrator 於 2026-10-08 完成，由人實際聽過。**逐步確認後由上述動作檔重放:X 唸成 Close、Delete 帶 hint、
  12:30 唸成 Half past twelve、decorative 被跳過。缺口:Volume 的值是 UIA ItemStatus,Narrator 只在 Caps Lock+0 時才唸，
  VoiceOver 則會主動唸——是否改用別的方式提供仍未定。途中修正：重放在 Caps Lock 組合鍵中把 `0` 送成 Unicode 字元，
  現在會追蹤自己按住的鍵。動作檔的 `# narrator: on` 讓 test.zsh 先開 Narrator,動作檔最後再關掉。Orca(WSLg)仍未聽過。

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
- [x] **M1. #32 手勢 — 三份實作完成,拖曳已驅動驗證** — 新增三個協定(`DragGestures`/`MagnifyGestures`/`Rotat... -> completed.md (archived 2026-10-18)
- [x] **M2. #125 Table 的 `selection` 與 `sortOrder` — 兩項都已完成於五個 backend(2026-09-16)** —... -> completed.md (archived 2026-10-05)

- [x] **M4. #121 在 iPhone 上已補上 — `UIResponder.keyCommands`(2026-09-16 完成並驅動驗證)** — UIK... -> completed.md (archived 2026-10-05)

- [x] **M5. `LazyListRowLifetimes` — 三個 backend 都已實作,而且三個都已驅動驗證(2026-09-16)** -> completed.md (archived 2026-10-05)


- [x] **M6. 已修,而且它從來不是 AppKit 的缺陷 — 是測試合成器裡的兩個缺陷(2026-09-17)** -> completed.md (archived 2026-10-05)

- [x] **M7. P4 與 P8 在 macOS 上一啟動就崩潰 — 都已修(2026-09-17)** -> completed.md (archived 2026-10-05)

- [x] **M8. `.inspect` 的同一個缺陷 — UIKit 已修並驗證;WinUI 與 GTK 於 2026-09-17 由 Windows 修好並驗證**... -> completed.md (archived 2026-10-05)
- [x] **M3b. #109 popover `arrowEdge` — 兩個 Windows backend 已完成並成對驗收(2026-09-16)** — 決定... -> completed.md (archived 2026-10-18)
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
- [x] **11. #117 phase 3(依需求建列)— AppKit 已落地,靜止時的問題解決了** — 新增 `BackendFeatures.LazyList... -> completed.md (archived 2026-10-18)
- [x] **12. #113 n^1.5 版面成本 — 已跑,結論是「不是 n^1.5,它是線性的」** — P52 四條 arm、12→192 五個尺寸,每格成本是*... -> completed.md (archived 2026-10-05)
- [x] **13. #120 Grid — 已完成:共用欄 + `gridCellColumns`** — 成因不是「需要新的 backend 能力」,而是**父層看不... -> completed.md (archived 2026-10-05)
- [x] **14. #127 `GeometryProxy.frame(in:)` — 已完成(GTK/WinUI 待對方編一次)** — Windows 答覆後路線確... -> completed.md (archived 2026-10-05)
- [x] **15. #28 Animation — 完成(時鐘 + 引擎)** — 引擎接在**狀態**那一端而不是版面那一端:`StateImpl` 的 setter... -> completed.md (archived 2026-10-05)
- [x] **16. #118 LazyHGrid — 已完成** — 先把 `GridLayoutPlan` 的詞彙從 column/row 改成 lane/line ... -> completed.md (archived 2026-10-05)

- [x] **17. #128 `EdgeInsets` — 已完成,這條協調請求已無須回覆(2026-09-17 查證)** — 原本是 Windows 端的一個**協... -> completed.md (archived 2026-10-05)

- [x] **M9. magnify / rotate — 完成(2026-09-17):格式、iOS、Android 都已驅動;AppKit 與 X11 以寫明的理由拒... -> completed.md (archived 2026-10-05)

- [x] **CLOSED 2026-09-29 -- TalkBack's actual speech verified, no human listening.** -> completed.md (archived 2026-10-06)

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
    - 動作檔 **`actions/mac/P72-stop-and-check.actions`** 與 **`actions/ios/P72-stop-and-check.actions`**
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
  - **[!] 開著的問題:`actions/ios/P72-stop-and-check.actions` 在 iOS 上跑不完。** 啟動後只有**第一個**
    互動會落地,其後每一列都毫無作用。以三種方式查證過:座標在 `--dump-tree` 與擷圖之間一致;
    app 之後仍持續算繪(沒有卡住);調換順序會改變「哪一個動作觸發」。同一段序列在 11:21、於捲動與
    快照加入之前是跑得完的。**它不是捲動的缺陷**——`actions/ios/P72-scroll.actions`(只有捲動)通過,
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
    - **證據(`actions/mac/P72-cursor.actions`,需搭配 `screencapture -C`)**:指標在 mesh view 上 → **十字**;
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
    - **斷言的是「項目有執行」,不是「選單有出現」**(`actions/mac/P72-context-menu.actions`):
      右鍵 → 下鍵 → Return → log 出現 `CONTEXT MENU reset the camera: dist 3.40 high 1.30`。
      **已證明會失敗**:把右鍵點擊移到純文字上(y 140),CONTEXT MENU 行數為**零**——那個選單屬於
      那個 view,不屬於那個視窗。
  - **UIKit 的 `Cursors` 與 `ContextMenus` 已落地(2026-09-20):**
    - **`ContextMenus` 已驗證**:`UIContextMenuInteraction`,長按叫出選單,**而且項目會執行**
      (`actions/ios/P72-context-menu.actions` → `CONTEXT MENU reset the camera: dist 3.40 high 1.30`)。
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
      **證據**:`testapp/actions/android/P72-context-menu.actions`(新的 `longpress` 動作)長按 mesh view,
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
    修好之後已重跑 macOS 的 `actions/mac/P72-stop-and-check.actions`:十項斷言全數重現,
    `.glb` 仍通過 three.js 的 `GLTFLoader`(2356 bytes,node euler z 1.0829 rad)。
  - **Android 的 `ScrollGestures`、`KeyEvents`、`WidgetSnapshots` 已落地並驅動過(2026-09-22):**
    - **`ScrollGestures` 已驗證。** 一個屬於本 modifier 自己的 `ViewGroup`,同時覆寫 `onTouchEvent`
      (單指,與 UIKit 同樣的選擇,因為 runner 用一根手指拖曳)與 `onGenericMotionEvent`
      (真正的 `ACTION_SCROLL` 滾輪,因此 `isPrecise` 在此處**真的**分得出兩種裝置——AppKit 可以,
      UIKit 不行)。不用 listener 的理由是算術:一個 `View` 只有一個 `OnTouchListener` 插槽,
      而 `ButtonPressState` 與 `.onTapGesture(.secondary)` 已經在搶它。
      **證據**:`actions/android/P72-scroll-and-keys.actions` —— 16 次各 10 點的 `onChange`,
      把相機距離帶到 3.400 → 2.600 → 3.400,與 macOS 兩次各 80 點的端點完全相同。
      **已證明會失敗**:同樣幾列移到標題文字上,SCROLL 行數為零。
    - **[x] 已修(2026-09-23):Android 的 `DragGestureValue` 原本回報像素,而協定寫的是點。**
      `ContinuousGestureContainer` 把 `event.x` 原樣交出去,而 AndroidBackend 的排版是「點乘上
      density」(P72 的 340×240 點量到 892×630 像素)。在 density 2.625 的裝置上,一次拖曳回報的距離
      大了 2.625 倍;換一台裝置就是另一個錯數字。新的 scroll 容器有做除法,舊的三個手勢沒有。
      已在 `ContinuousGestureContainer` 裡除以 density,並以新的 `actions/android/P65-drag.actions` **雙向證明**:有換算時 `translation (80, 0)`,把換算拿掉重建 APK 之後是 `translation (210, 0)`——也就是 80 × 2.625。縮放與旋轉不需要動:一個是兩個 span 的比值、一個是角度,單位都約掉了。同時掃過其餘 Kotlin:`CustomSlider` 比的是像素對像素的 touch slop(正確),`HoverContainer` 不回報座標,`ScrollGestureContainer` 從第一行就有換算。
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
      **證據**:`actions/android/P72-snapshot.actions` —— `SNAPSHOT 892x630 px`(340×240 點 × 2.625)、
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
      **證據**:`actions/android/P72-stop-and-check.actions` —— `STOPPED at frame 6`、
      `CHECK at frame 9, 3 since the stop`。一個自走的 view 在那 1.5 秒裡會畫約九十幀;三幀是 UIKit
      給出的同一個數字。`renderer` 讀作 `Android Emulator OpenGL ES Translator (ANGLE ... SwiftShader)`,
      `drawable 892 x 630 px`。
    - **矩陣不再是逐 backend 各寫一份。** `Mesh3DMatrix4`(`SwiftCrossUI/Views/Mesh3DMatrix.swift`)
      現在帶著 model / rotation / lookAt / perspective,而**兩個** renderer 都用它;深度範圍是一個
      參數(Metal 用 `.zeroToOne`、GL 用 `.minusOneToOne`),因為那是兩個 API 真正不同的唯一一件事。
      原本那四個函式是 `Mesh3DMetalView` 的私有函式,各自帶著一段「它選了哪個慣例」的註解——再寫一組,
      就是多四次選錯的機會。已重驗:macOS 的 `P72-stop-and-check.actions` 十項斷言全數重現,
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
    - **`actions/android/P72-snapshot.actions` 已刪除。** 它是在 renderer 落地**之前**寫的:座標是舊版面的
      (renderer 字串會折成五行,把下方控制項推下約 100 點),而它期待的結果是「1 種顏色的空盒子」。
      兩者都已不成立,而 `P72-stop-and-check.actions` 對真正的 GL 表面斷言同一顆按鈕,嚴格更強。
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
    `actions/ios/P72-keys.actions` **完全沒有座標**:backend 自己會取得 first responder,因此經由模擬器
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
  - **2026-10-05 結案——其實 2026-09-27 就已完成(`1fea7901` "The macOS cursor works"),我拆出這一項時依據的是 M10 裡 9/23、9/25 的舊段落,沒有查最新紀錄。** 真正的兩個原因當時已找到並修好：座標是照「相對於父 view」的 frame 量的，以及 `hover` 等待時沒有把排隊的事件交給 `sendEvent`。今天重跑 `actions/mac/P72-cursor.actions`,用不依賴 hover 讀數的證據確認:`NSCursorTarget` 自己的 `-cursor:` 行顯示指標在 340x240 的 mesh view 內時 `cursorUpdate ... -> set`(34 次),移出時 `mouseExited`;讀數也一致——(239,284) crosshair、(239,124) arrow。
- [x] **Windows 與 Linux 的 `hover` 動作(由 M10 拆出,2026-10-05)。** 目前是具名拒絕,各自該用的 API 寫在拒絕訊息裡;要在那兩台機器上實作並驅動。
  **DONE 2026-10-07, both.** Win32: ten stepped SendInput moves (a SetCursorPos
  jump left WinUI's cursor at arrow), then GetCursorInfo against the shared
  IDC_* cursors; actions/win/P80-cursor.actions -> pointingHand, crosshair, text,
  resizeHorizontal, resizeVertical, notAllowed, and arrow outside every target.
  xdotool: mousemove, then the XFixes cursor NAME read through python3 ctypes
  (no X11 link in InputEvent); actions/wsl/P80-cursor.actions under WSLg gives the
  same six and "arrow (unnamed default)" for the control -- XWayland reports the
  inherited default cursor with no name, and the line says so. Both wait for
  the reading to change (2 s limit) and print AppKitSynthesiser's format.
  Run with the default showtime: one `--no-showtime` run closed P80 after five
  of the seven rows.
  **2026-10-07 兩者皆完成。** Win32 與 xdotool 的 `hover` 都已實作並以 P80 驅動，六個游標與對照列皆正確。
- [x] **WinUI:`frameClockToken?.dispose()` 真的取消訂閱了嗎(由背景段落拆出,2026-10-05)。** 設計上對,但從沒量過:... -> completed.md (archived 2026-10-18)
- [x] **T4. #121 step 2 — 與 Windows 撞了同一個功能,採用他們的設計** — 合併時才發現兩邊都實作了 `.keyboardShortcut(_:modifiers:)`:**檔案不同,所以 git 沒報衝突,是編譯器報的**(`invalid redeclaration`)。他們走 **environment**(`environment(\.keyboardShortcut, …)`),而且**已在 GTK 與 WinUI 兩個 backend 上驗過**;我走的是「在 `ResolvedMenu.Item.button` 上加第三個 associated value」,只在 AppKit 驗過。**留他們的**——一個功能兩套機制比其中任何一套都糟,而他們那套已經有兩個 backend 在讀。我的 `ResolvedMenu`/`MenuItem`/`Menu.resolve` 改動與那個 modifier 全部還原,AppKit 與 Android 改讀 `environment.keyboardShortcut`。**AppKit 以 actionfile 重新驗過**(`actions/mac/P71-shortcuts.actions`,選單全程關著):`plain 1、shifted 1、disabled 0`。Android **已驗證(2026-09-23)**,三項斷言全中、含那個已停用的項目:Ctrl-S 觸發 PLAIN、Ctrl-Shift-E 觸發 SHIFTED、Ctrl-D 在已停用項目上什麼也沒觸發。**是 Ctrl 不是 Command**,而那正是 `EventModifiers.command` 那條慣例從驅動端看過去的樣子。**但它驅動不了**——`AndroidSynthesiser` 經由 `Activity.dispatchKeyEvent` 投遞,那抵達得了 view 階層(P72 的 `.onKeyPress` 就是這樣被驅動的),而 app 選單快捷鍵住在 `View.OnUnhandledKeyEventListener`,由 `ViewRootImpl` 在任何 app 投遞得到的層級**之上**執行。成對的證據才是這項發現:動作檔把 21 個動作全部重放完成而計數器停在 0/0/0,同一個 Ctrl-S 改用 `adb shell input keycombination -t 120 113 47` 就觸發了。與觸控側的 `PopupMenu` 限制同族。**[x] 2026-09-25 已解決:動作檔現在驅動得了它。** 見下方。原文保留:**繞過去的辦法試過了,被拒絕。** `Instrumentation.sendKeySync` 是公開 API、經由 `InputManager` 注入,會像鍵盤一樣從 `ViewRootImpl` 進入;而 `InputDispatcher` 的權限檢查對「uid 持有聚焦視窗」的注入者是豁免的,一次重放正是如此。建好、接在 activity 路徑之前、實際執行:**七次全數被拒**,`SecurityException: Injecting input events requires the caller ... INJECT_EVENTS permission`。那個權限在豁免被觸及之前就檢查了——因此這個限制是「一個應用程式持有不了的權限」,不是「少想到一個辦法」。那段程式碼已移除(一條在每個受支援組態下都被拒的路徑,只會在每一列按鍵上輸出日誌);移除後已重驗 P72 的按鍵列,結果不變。**解法(2026-09-25)**:要找到的是**兩**件事,而第二件才是關鍵。(1) 那些快捷鍵住在 decor view 的 `OnUnhandledKeyEventListener` 上,而 `ViewRootImpl` 在任何 app 投遞得到的層級之上執行它。(2) **一個按鍵事件跟著焦點鏈走**——`ViewGroup.dispatchKeyEvent` 只派給 `mFocused` 或自己,否則直接回傳 false;它**不會**走訪子節點。P71 沒有聚焦任何東西,所以 decor 的 `mFocused` 是 null,它底下沒有任何 view 看到過那個按鍵。第二件是靠「對 `ShortcutHostLayout` 加儀器、而它在 21 個重放動作之間一行都沒印」量出來的——在那之前我改了兩次都是猜的。現在 `ShortcutHostLayout` 就是視窗的 content view:它在 `super.dispatchKeyEvent` 拒絕之後查同一張表(與「unhandled」是同一個時刻,只是低一層),並以 `FOCUS_AFTER_DESCENDANTS` 取得焦點,因此只在沒有別的東西要焦點時才持有它。**結果**:`PLAIN 1、SHIFTED 1、DISABLED 0`。**兩項回歸都查過**:不會觸發兩次(本檔跑完 PLAIN=1 後,再送一次系統層級 Ctrl-S 變成 2、不是 3);焦點仍然正常(同版本的 P70 回報 `focused field: name`、`focus changes heard: 1`,文字欄位贏過根節點)。P72 的按鍵列不變。**UIKit 是缺口**,並在原地寫明理由:`UIAction` 收 closure 帶不了按鍵,`UIKeyCommand` 帶得了按鍵卻收 selector、經 responder chain 派送。**測試 app 是新的 P71**,它斷言計數器而非選單外觀——每個 backend 都畫得出「⌘S」,而那樣的截圖與能用的一模一樣。
  - **2026-10-05 由 [~] 改為 [x]:** 上文已寫明 2026-09-25 解決:`ShortcutHostLayout` 成為 content view,動作檔驅動得了 Android 的選單快捷鍵;AppKit 與 Android 都讀 `environment.keyboardShortcut`。沒有剩下的部分。
- [x] **4. #121 鍵盤快捷鍵 — 五個 backend 全數完成(2026-09-16 傍晚由原始碼查得)** — UIKit 那一格已由 Mac 補上(`U... -> completed.md (archived 2026-10-05)
- [x] **5. focus / accessibility(#122 / #123)— 五個 backend 全數完成** — GTK 與 WinUI 於 2026-... -> completed.md (archived 2026-10-05)
- [x] **6. #74 `-GPU` on macOS — 已實作(AppKit + UIKit)** — 那個「設計問題」其實已被協定的形狀回答了:`Graphic... -> completed.md (archived 2026-10-05)
- [x] **7. #28 動畫 / #32 手勢** — 五個 backend 全部 conform(`DragGestures`/`MagnifyGestures`/... -> completed.md (archived 2026-10-05)
- [x] **8. #117 phase 3 — 五個 backend 都有 `LazyListRows`;缺的換成 `LazyListRowLifetimes`,而且是在你們那三個** — **GTK 的 `LazyListRows` 早就完成**(`5739d453`):它是由 `LazyListRowLifetimes` **繼承**而來的,因此任何「找具名 extension」的掃描都會說它沒有——那正是這一條原本寫錯的原因。**[!] 這一句在 2026-09-23 之前一直是錯的,而我差點照它再做一次。** 它原本寫著「`LazyListRowLifetimes` 只有 GTK 與 WinUI 有,AppKit / UIKit / Android 沒有」。那在 `24319bd6` 之後就不成立了——那個 commit 的標題就是「LazyListRowLifetimes on the three backends that only had LazyListRows」,而三個 conformance 都在:`AppKitBackend+LazyListRows.swift:49`、`UIKitBackend+LazyListRows.swift:40`、`AndroidBackend+LazyListRows.swift:158`。我根據這一句把它推薦為「下一件最大的事」,而接住它的是 `grep`,不是這份文件——**mistakes 第 13 條的第二次發生**。**真正還缺的是驅動,不是實作**:macOS 已驅動且通過(`actions/mac/P57-scroll-the-whole-list.actions`,讀數 19 而不是 ~500);iOS **2026-09-27 已驅動且通過**(`actions/ios/P57-walk-the-list.actions`,建過/持有 1734 / 8,啟動時 1 / 1;先前每一次拖曳都從視窗中心、也就是清單上方的文字開始,什麼都沒推動——在重放當下拍照證實——加了一列 `move 200,810` 到清單上才解決;原本寫的「三十列 scroll 完全沒有移動那個清單」是真的,但成因不是一格的大小);Android **建了、且在小尺度上觀察到釋放**(兩列,而那個模擬器上大約只放得下兩列)。iOS 與 Android 的共同阻礙都是「清單沒有被捲動」。**2026-09-27 更正:**那**不是**與 `actions/ios/P72-stop-and-check.actions` 同一族的問題——那一個是 `RootScrollHost` 在第一次觸控時移動版面(已修),這一個在 iOS 上是拖曳沒有落在清單上(已修)。Android 那一半仍待查,而不應假設它是這兩者之一。WinUI 那份以對照組量過:掃 5000 列,有釋放 146/150 MB、扣住回呼 221/222 MB。原文保留:WinUI / AppKit / UIKit / Android 都 conform `LazyListRows` 並量過(AppKit 423→104 MB、UIKit 449→170、Android 385→92)。**GTK 目前只 conform `LazyListRowLifetimes`**(回收那一半),`LazyListRows` 尚未;Windows 標為 active。那句「400 列 114 MB、10,000 列 423 MB」是**修好之前**的數字,留在此處會讀成現況。
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
