# Plan: synthesised input from a CSV file

## What we want

An app built with SwiftCrossUI, given `-actionfile <path>`, replays the actions
in that file against its own window. One file format, the same behaviour on
Windows and on Linux, so a UI test is written once.

## Why

`xdotool` drives GTK apps on Linux and cannot drive anything on Windows. Every
interaction check in this project has been Linux-only for that reason: P19's
menu has been opened and its item clicked, P21's disabled button has been proved
to refuse input, P24's stack has been pushed — all on Linux, none on Windows.
The comparison the Pn apps exist for is half missing, and it is the half that
motivated the whole GtkBackend-on-Windows effort.

Two things had to be established before this was worth planning, and both were
measured rather than assumed:

- An X server on Windows does not help. `xdotool` is an X11 client speaking
  XTEST, and a SwiftCrossUI app on Windows is a Win32 HWND, not an X client.
  The gvsbuild GTK 4 for Windows has no x11 backend compiled in either:
  `GDK_BACKEND=x11` answers `No such backend: x11`.
- `SendInput` is not something to obtain. It is a Win32 function in
  `user32.dll`, declared in `<windows.h>`, callable from Swift through
  `import WinSDK`.

So the work is a shared vocabulary and two thin adapters, not a port.

## Shape

```
Sources/InputEvent/
  README.md          the CSV specification
  plan/              this document
  InputAction.swift  the parsed form of one row
  ActionFile.swift   CSV to [InputAction]
  Synthesiser.swift  protocol: perform(_ action:in window:)
  Win32Synthesiser.swift    SendInput
  XTestSynthesiser.swift    XTEST through libxdo
```

`InputEvent` is a target that knows nothing about SwiftCrossUI. It takes a
window origin and a size, and posts events. That keeps it testable without a
running app and stops backend concepts leaking into it.

GtkBackend gains the entry point, because GtkBackend is what owns a window on
both platforms:

```swift
extension GtkBackend {
    public func replayActionFile(at url: URL, in window: Window) throws
}
```

The app side is one call, made from `onAppear` when the flag is present. That
belongs in each Pn rather than in the framework, so an app can decide when it is
ready to be driven — a file replayed before the first frame clicks on nothing.

## Decisions already taken, and why

**The app drives itself rather than an external tool driving it.** The app knows
where its window is, so window-relative coordinates need no window search and no
correction for decorations. An earlier external driver clicked on nothing until
it was changed from absolute to window-relative positions; removing the search
removes that whole class of failure.

**Window-relative coordinates, converted to screen coordinates at the last
moment.** Both `SendInput` and XTEST are system-wide — they post to whatever is
focused, not to a chosen window. The conversion is the adapter's job and the
file never mentions screen space.

**The window is presented before replay.** Both injection paths follow focus.
`GtkBackend.show(window:)` now calls `gtk_window_present`, which is what made
the window come to the front on Windows at all; without that this feature would
type into whatever was in front.

**Our own key names, not each platform's.** Linux wants keysyms, Windows wants
virtual-key codes, and they disagree. A file written against one would silently
do nothing on the other, which is the failure mode this project has spent the
most time on. One table, mapped twice.

**Modifiers are `keydown`/`key`/`keyup` triples, not `ctrl+a`.** A combined
token hides when the modifier went down and came up, and timing is what these
files exist to express.

**`micros` is microseconds and the resolution is not.** Both platforms schedule
on roughly millisecond timers. The unit states intent precisely; the README says
plainly that it is not a promise.

**No assertions in the format.** A file describes actions. Whether the result is
correct is decided by the app's diagnostics, a screenshot, or a person. Adding
assertions would make this a test framework, and `testapp/test_support/` already
is one.

## Steps

1. `InputAction` and the key-name table. → verify: a unit test parses every verb
   and rejects a row with an unknown key name, rather than skipping it silently.
2. `ActionFile`, parsing with the same RFC 4180 rules `csv2` uses. → verify:
   the example file in the README round-trips, and a malformed row reports its
   line number.
3. `XTestSynthesiser` against `libxdo`. → verify: replay P19's menu sequence and
   get the same `last action -> button item` that the manual `xdotool` run
   produced.
4. `Win32Synthesiser` against `SendInput`. → verify: the same file, the same
   result, on Windows.
5. `replayActionFile` on GtkBackend, and `-actionfile` in one Pn. → verify: P19
   on both platforms from one file.
6. The remaining Pn get the flag. → verify: an action file per app in
   `testapp/actions/`, matching the test plan's numbered steps.

Steps 3 and 4 are where this either works or does not, and they are worth doing
before step 5 rather than after: if XTEST and SendInput cannot be made to agree
on what a double click is, the format needs to change and everything above it
is rework.

## Risks

**Double click is a platform notion.** Windows has a system double-click time
and `SendInput` does not bundle clicks; XTEST does not either. Both adapters
must produce two press-release pairs inside that interval, and the interval
differs. `doubleclick` therefore has to read the platform's setting rather than
hard-code a gap, or an app will see two single clicks on one machine and a
double on another.

**libxdo may not be present.** `xdotool` the binary is installed in this WSL
image; `libxdo-dev` is a separate package. If linking is awkward, shelling out
to the `xdotool` binary is an acceptable first implementation — slower, but it
is what the existing driver already does and it works.

**Focus can be lost mid-file.** Anything that steals focus during a replay
sends the rest of the actions somewhere else. The synthesiser should check the
window is still focused before each action and stop with an error rather than
carry on typing into another application.

**Coordinates go stale.** An action file records pixel positions, so a layout
change silently invalidates it. This is inherent to coordinate-driven input and
is the reason the `note` column exists: a file that says what each step is
checking can be repaired, one that only says `click,60,181` cannot.
