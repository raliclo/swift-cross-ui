# todo

Work that is known, sized and not done. Written 2026-08-27 from a working
session's task list, which otherwise lives nowhere.

Each entry says what was measured rather than what was assumed, because several
items here exist only because a confident guess was checked and turned out to be
wrong. Where a number appears, the command that produced it is beside it or in
the file it points at.

已知、已估過規模、尚未完成的工作。於 2026-08-27 自某次工作階段的任務清單寫成——否則那份清單不會
留在任何地方。

每一項記錄的是「量到什麼」而非「假設什麼」，因為此處有數項之所以存在，正是因為某個看似有把握的猜測
被查證後證實是錯的。凡出現數字之處，產生它的指令就在旁邊，或在它所指向的檔案裡。

---

## Now / 現在

### Swift 6 language mode, module by module

`Package.swift` declares `swift-tools-version:6.0`, so an older toolchain is
refused — that half is done. Every target is then pinned back to `.v5` by the
sweep at the bottom of that file. Lifting a target means adding its name to
`migratedToSwift6` and fixing what the compiler then says.

**That instruction changed on 2026-08-27, and the old one never worked.** It
used to say "delete it from `stillOnSwift5`", but `stillOnSwift5` was
`Set(package.targets.map(\.name))` — a derived set with no entries to delete. So
nobody could have followed it. The list is now the *migrated* targets rather
than the remaining ones, which also means a target added later defaults to v5
instead of silently landing on v6 and breaking the build for whoever added it. A
name in the list that matches no target now fails the manifest, because a typo
there is otherwise silent: the target stays on v5 and reads as done.

Measured 2026-08-27 with the mode actually on:

| target | errors |
|---|---|
| SwiftCrossUI | 1 site |
| GtkBackend | 98 |
| WinUIBackend | 1274 |
| AppKitBackend | 5 |
| UIKitBackend | still unmeasured |

AppKitBackend measured 2026-08-27 on the Mac, by lifting it alone and building
it. Five diagnostics, and they are one shape and a
half rather than five problems:

- three are the same conformance-isolation error, `AppKitBackend.swift:22:35`,
  once each for `AngularGradients`, `LinearGradients` and `RadialGradients` --
  the plain `public final class` conforming to `@MainActor` protocols, exactly
  the shape GtkBackend's 98 and WinUI's 1274 mostly are;
- two are `sendability of function types ... does not match requirement in
  protocol 'Core'`, on `runMainLoop` and `runInMainThread(action:)`.

So AppKitBackend is small, and it is small in the same way the others are large.
It is a candidate for going first: whatever fixes those three conformances is
the pattern the other two backends need hundreds of times.

UIKitBackend is still unmeasured, and not for want of a Mac. A host build cannot
resolve `import UIKit`, and `SCUI_HOST_BACKENDS_ONLY=1` -- which is what makes
this package configure on macOS at all -- deletes the target outright. Measuring
it needs an iOS-SDK build through xcodebuild with the target present, which is a
different setup rather than a longer wait.

**A second measurement trap, in the same family as the one below.** The first
attempt at the number above used `swift build --target AppKitBackend -Xswiftc
-swift-version -Xswiftc 6` and reported 8. That number was from `ImageFormats`,
a dependency: `-Xswiftc` is global, so it flipped every target and the build
failed before it reached AppKitBackend. Lifting the one target in the manifest
is the mechanism that measures that target. Counting is its own
trap -- grepping `error:` over the raw output gave 12, because the compiler's
caret rows and the build system's two summary lines match too. Five is the
count of lines naming a file in `Sources/AppKitBackend/`, and it equals the
number of distinct diagnostics.


The one SwiftCrossUI site is the hard one. `BaseStubsTest` in
`Sources/SwiftCrossUI/Backend/BackendFeatures/BaseStubs.swift` is a DEBUG-only
empty struct that exists to prove `BaseStubs` supplies a default for every
backend requirement. Both of the compiler's fix-its fail: an isolated
conformance is rejected because the protocols inherit `SendableMetatype`, and
marking the requirements `nonisolated` would be a false claim about the whole
backend protocol. That one needs a decision about the protocols, not a local
edit — do not read "1 error" as "1 minute".

Most of GtkBackend's 98 and probably most of WinUI's 1274 come from one shape:
the backends are plain `public final class`es with no isolation annotation
conforming to `@MainActor` protocols.

**A measurement trap, recorded so it is not repeated.** `swift build -Xswiftc
-swift-version -Xswiftc 6` is *not* the language mode. It is global, so it
recompiles dependencies too — the first probe reported 17 errors, every one of
them inside `.build/checkouts/swift-image-formats` and none in our code. Size
this job with `swiftLanguageMode`, never with `-Xswiftc`.

### Action files are tied to the display scale — done 2026-08-27

`GtkBackend` now passes `gtk_widget_get_scale_factor` to the synthesiser, so a
coordinate is scaled by what the toolkit laid out with rather than by what
`GetDpiForWindow` reports. Kept here as the record of what was and was not
verified, because one half could not be.

Verified: no change at 100% on Windows (P21's counter reads 3, GTK reports 1.0),
and the *differing* case on Linux, where `GDK_SCALE=2` makes GTK report 2.0 and
lay out 820x720 → 1640x1080, and the same one-line file lands exactly 410,400
further into the window than at scale 1.

Not verified: Windows at any scale other than 100%. `GDK_SCALE` cannot stand in
for it — measured 2026-08-27, GTK 4 on Windows **ignores it entirely**, producing
a pixel-identical window and still reporting 1.0. WinUIBackend keeps
`GetDpiForWindow` on the reasoning that a DIP framework scales fractionally;
nothing has ever been driven against it at another scale, so that is reasoning
rather than a measurement.

The Linux path needed a fix of its own to make this safe, and it was one this
change introduced. `XdotoolSynthesiser` reported a *physical* window origin
while `screenPosition` multiplies the whole sum by the scale, so passing a scale
other than 1 doubled the origin along with the point. Invisible while the scale
was hard-coded to 1. Found by solving for the origin under both models and
seeing which reproduced the reparenting inset this file already documented:
`(origin + point) * scale` gave -38,-59 at both scales, `origin + point * scale`
gave -38,-59 at one and 154,-6 at the other.

---

## GtkBackend gaps / GtkBackend 的缺口

- **Follow the desktop's light/dark change while running.** The binding defects
  are fixed (`addNotificationSignal`, and `Settings.default` caching its
  wrapper). What remains is six changes in `GtkBackend.swift`, listed in the
  task history. **Cannot be verified in WSL at all**: measured, a
  `gsettings set` produces zero notifications across all 55 `GtkSettings`
  properties, because WSLg has no `xdg-desktop-portal`, no XSettings manager and
  no libadwaita. Needs a real GNOME desktop.
- **`windowScaleFactor` never propagates**, and `WinUIBackend` has the identical
  gap. `computeWindowEnvironment` never computes it and the Gtk module has no
  binding for it. Window *activation* already propagates correctly — the issue's
  original "window environment changes never propagate" was too broad.
- **DatePicker**: `.wheel` unsupported (GTK has no such widget). `.compact` and
  the calendar/timezone handling are done.
- **21 catalogued silent no-ops**, ranked by severity × cheapness in
  `testapp/gtk-silent-noops.md`, with a seven-entry appendix of things that look
  like no-ops and are not. The top three are ~5, 1 and 2 lines.
- **Diagnostics are compiled out of the builds this project tests.**
  `debugLogOnce` is `#if DEBUG` while `compile.zsh` builds release by default,
  so both of GtkBackend's diagnostic call sites print nothing in the one
  configuration everything is actually run in. `DatePickerStyleModifier`'s
  `assertionFailure` has the same shape. The project already has `SCUI_DEBUG`
  and `DebugFeatures` for exactly this. Check first whether any diagnostic is
  deliberately DEBUG-only before moving it.

---

## Test infrastructure / 測試基礎設施

- **Keyboard action files cannot run on Windows at all.** `prepareForReplay`
  refuses any file containing `key`/`keydown`/`keyup`, and correctly: a key
  event goes to whatever holds focus, and a background-launched process cannot
  take the foreground. But that removes P10's Ctrl-Q, P21's tab traversal and
  every text-entry check. Do not simply drop the refusal — typing into whatever
  happens to be in front is how two runs ate the user's editor state. Options,
  in order: `PostMessage` of `WM_KEYDOWN` straight to the window; retry
  `AttachThreadInput` now that the window is pinned topmost (it was tried before
  the pin existed); or make `run.zsh` say so up front rather than at the end.
- **`ui-lock.zsh`'s locked-desktop gate reads `LogonUI.exe`**, which does not
  track lock state — it has been seen running while input was being delivered.
  The direct signal is `SendInput` failing with `ERROR_ACCESS_DENIED` (5), which
  is the capability actually being gated. That would also be cheaper: `tasklist`
  costs ~195 ms and the gate runs it on every acquire. Seen again 2026-08-27:
  the workstation locked itself mid-session and a replay reported
  `SendInput exited with status 5`, with a desktop capture showing the PIN
  screen — so the proposed signal does fire, and it named the cause where a
  window capture did not. `screenshot.zsh -w` went on returning a correct
  picture of the window throughout, because BitBlt reads a window that is not
  on screen; only the desktop capture showed the lock.
- **P10 launches on Windows, registers a title, and shows no window.** Not
  diagnosed. Rule out a leftover GTK process and a locked workstation before
  forming any hypothesis — both produce exactly this appearance.
- **`swift test` does not run on Windows at all.** `SCUI_HOST_BACKENDS_ONLY=1
  swift test` fails with `missing required modules: 'CGtk', 'GtkCHelpers'` while
  emitting `DefaultBackend` — so the flag that deletes the unbuildable targets
  does not stop `DefaultBackend` from importing GtkBackend. Measured
  2026-08-27, with and without `PKG_CONFIG_PATH=/c/gtk4/lib/pkgconfig`, and
  **verified pre-existing**: the same failure appears on a stashed, unmodified
  tree, so it is not a consequence of any change made that day. The suite does
  run on WSL, which is presumably why this went unnoticed — "55 tests in 10
  suites pass" was true there and untested here.
- **`testapp/run.zsh` documents an action-file path that does not work.** Its
  own example says `actions/win/...`; the app resolves against the repo root, so
  it must be `testapp/actions/win/...`. Consider making the script resolve the
  short form rather than only correcting the comment.

---

## SwiftUI parity / 與 SwiftUI 的落差

Nine areas from a protocol-and-platform audit. Each is a category, not a task:
animation and transitions (no protocol at all); visual effects and transforms;
focus, accessibility and keyboard shortcuts; style protocols (`ButtonStyle`,
`LabelStyle`, `ShapeStyle`); gestures beyond tap and hover; missing common views
(`Form`, `Section`, `Label`, `Stepper`, lazy containers); API shapes that do not
compile from SwiftUI code; state wrappers and scene composition; presentation
and container modifiers.

The API-shape one is worth doing first and is the least visible: the types exist
and only the initialisers differ, so the gap never shows on a feature checklist.

---

## Needs another machine / 需要另一台機器

- **AppKitBackend and UIKitBackend conformances written but never compiled.**
  Clipping, DragAndDrop, WindowLevels and HitTesting were added against
  documented APIs on a Windows host. Review-ready, not verified.
  HitTesting has now been run on a Mac and does not work -- see below.

### AppKit hit testing: nothing but text fields can be clicked

Measured on macOS 2026-08-27, after `882b43f8 Implement AppKit hit testing and
add P28 coverage`. Handed over rather than fixed; the Mac side stopped here.

`AppKitHitTestingContainer.hitTest` returns nil for almost everything. Probed
directly on a live window, points at the exact centre of each control:

| window point | control there | hitTest |
|---|---|---|
| (140, 225) | NSButton "TOP" (114, 212, 52, 27) | nil |
| (140, 195) | NSButton "BOTTOM" (99, 182, 82, 27) | nil |
| (140, 165) | text field (40, 155, 200, 21) | NSTextView |
| (140, 105) | NSScrollView (117, 65, 46, 80) | nil |

Confirmed with the project's own test, not only a scratch app:
`test.zsh P28 --macos --actionfile` replays
`testapp/actions/mac/P28-hit-testing.csv`, whose single click is the one P28
exists to check, and `p28-debug-events.log` contains "clicked" zero times.

The coordinates are not the problem, which was checked before blaming the
container. The full chain measured on the same window: screen 1920x1080 at
backing 2.0, geometry frameOrigin (820, 193) and clientOrigin (820, 221) at
scale 1, client (140, 105) resolving to screenPosition (960, 326) -- 820+140 and
221+105 -- and then to windowPoint (140.0, 195.0), which is exactly right. The
click lands where the file says and there is nothing there to receive it.

Text still arrives, and that is the trap: key events go to the first responder
without a hit test, so a file that clicks a field and types reports a partial
success and looks like a coordinate problem.

One fix was tried and is not the answer. `child.hitTest(childPoint)` looks wrong
against Apple's contract -- `hitTest(_:)` takes a point in the receiver's
*superview* coordinates, and childPoint has been converted into the child's own
space -- but passing `point` instead makes it worse: the text field stops
hit-testing too. So the container is self-consistent with a non-standard
convention and breaks where it meets real AppKit views. The reverted experiment
is recorded so nobody spends the same hour on it.

**A fix is written and needs one command on a Mac to confirm or kill it.**
`9623ad6` on the Windows side. There were two frame-of-reference errors at once,
which is why the reverted experiment failed differently rather than worked:
`hitTest(_:)` takes its point in the receiver's *superview* space, so
`convert(point, to: child)` started from the wrong space, and
`child.hitTest(childPoint)` then passed a point in the child's own space where
the child's superview space was wanted. Passing `point` corrects the second and
leaves the first, so it is right only while the container sits at its
superview's origin.

The numbers in the table above are what make it a diagnosis. Button frame
(114, 212, 52, 27), point (140, 225): `childPoint` is (26, 13), genuinely inside
the button's bounds — so the containment check passed and hid the problem —
and then `button.hitTest((26, 13))` compared (26, 13) against x 114...166,
y 212...239 and correctly said nil.

Unverified from here: this is a Windows host and AppKitBackend does not compile
on it. The prediction is specific — `test.zsh P28 --macos --actionfile` should
put "clicked" into `p28-debug-events.log`, where it currently appears zero
times. If it does not, the remaining suspect is the flippedness of the
container relative to its children, which the measurements above cannot rule
out.

- **Benchmark Metal's feature set on macOS**, then implement the useful subset
  on GtkBackend through GSK render nodes and GLSL rather than Metal shaders.
  Two things to settle first: which parts are reachable from GSK's public API at
  all, and whether the numbers justify a GPU path at UI sizes.
- **`#27` above needs a real GNOME desktop**, for the reason given there.

---

## Needs a decision / 需要決定

- **WebKitGTK as a system dependency.** A real `WebView` on Linux and Windows
  needs `webkitgtk-6.0` in `Package.swift`, which changes the build requirements
  for everyone. The placeholder is in place until this is answered.
Only one open decision, then. The AppKit `HitTesting` item that was here has
already been answered: it was implemented on the Mac side, in
`AppKitBackend+HitTesting.swift`, with a container subclass and a weak
`NSHashTable` registry — and it corrects the design that was recorded here, which
had the container return `nil` after `super.hitTest`. That stops AppKit
searching, so a disabled overlay would swallow the click rather than pass it
through; the shipped version walks its own subviews front to back instead.

只剩一項待決。原本列於此處的 AppKit `HitTesting` 已有答案：它已在 Mac 端以
`AppKitBackend+HitTesting.swift` 實作完成，採用 container 子類別搭配弱引用的 `NSHashTable` 登錄表
——而且它修正了先前記錄於此的設計，該設計讓 container 在 `super.hitTest` 之後回傳 `nil`。那會使
AppKit 停止搜尋，於是被停用的 overlay 會吞掉點擊而非讓它穿透；實際落地的版本改為自行由前到後
走訪自己的 subviews。
