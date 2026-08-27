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
sweep at the bottom of that file. Lifting a target means deleting it from
`stillOnSwift5` and fixing what the compiler then says.

Measured 2026-08-27 with the mode actually on:

| target | errors |
|---|---|
| SwiftCrossUI | 1 site |
| GtkBackend | 98 |
| WinUIBackend | 1274 |
| AppKitBackend, UIKitBackend | unmeasurable on a Windows host |

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

### Action files are tied to the display scale, and should not be

`Win32Synthesiser` reads `GetDpiForWindow` and converts, so the file format is
meant to be scale-independent logical points. It is not, because GTK 4 on
Windows uses an *integer* scale factor: at 125% Windows reports 1.25 and GTK
rounds to 1, so one GTK layout unit is one physical pixel and the two disagree.

The cost is already paid once. When this machine went from 125% to 100% every
file in `testapp/actions/win/` became wrong by a quarter and all 17 had to be
re-measured from fresh captures. `testapp/actions/win/README.md` currently
documents that as a rule to follow; it is really a symptom, and the note there
should point here once this is fixed.

Fixing it means the synthesiser using the scale the app's toolkit actually laid
out with, rather than the one Windows reports — which needs it to know which
backend it is driving.

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
  costs ~195 ms and the gate runs it on every acquire.
- **P10 launches on Windows, registers a title, and shows no window.** Not
  diagnosed. Rule out a leftover GTK process and a locked workstation before
  forming any hypothesis — both produce exactly this appearance.
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
