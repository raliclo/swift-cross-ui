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

**Two origins, `client` by default and `frame` on request.** Client coordinates
cover everything the app draws, and defaulting to them is what stops the mistake
the earlier external driver made — it computed absolute positions from window
geometry, which includes the decorations, so every click missed by the height of
the title bar.

`frame` exists because the decorations are a legitimate target: dragging a
window by its title bar, pressing close or minimise or maximise. It is opt-in
because it is less portable. Title bar height varies with platform, theme and
display scale, and under GTK's client-side decorations the title bar is drawn by
the app rather than the window manager, so the two origins can coincide on one
machine and differ by 37 pixels on another. A `frame` row records a position on
the machine it was written on.

**`mousedown` and `mouseup` are separate verbs, not just `click`.** A drag needs
the button held across a move, and `click` is a press and a release with nothing
between them. Without the pair there is no way to move a window by its title bar
or to drag a slider, which the `frame` origin would otherwise be useless for.

Units are logical points, not physical pixels, so a file survives being run at a
different display scale. This costs one division when reading coordinates off a
screenshot, which is in physical pixels; the alternative costs correctness on
any machine that is not at 100%, and fails by clicking somewhere plausible
rather than by reporting anything.

**Key names come from macOS.** Carbon's `kVK_*` constants, prefix dropped. A
real specification with documentation beats a set invented here, it is already
complete down to the keypad and the right-hand modifiers, and it belongs to the
third backend so neither of the two platforms this runs on wins by default.

It imports two Mac assumptions that have to be stated rather than discovered.
`delete` is Backspace and `forwardDelete` is the other one. And `command` is the
physical key in that position — the Windows key, or Super — not "the shortcut
modifier", which means an action file exercising a shortcut cannot be identical
across platforms even though its key names are. Replaying input reproduces
keystrokes, not intent.

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

1. `InputAction` and the key-name table. → verify: a unit test parses all nine
   verbs and both origins, and rejects an unknown key name rather than skipping
   the row silently.
2. `ActionFile`, parsing with the same RFC 4180 rules `csv2` uses. → verify:
   both README examples round-trip, and a malformed row reports its line number.
3. `XTestSynthesiser` against `libxdo`. → verify: replay P19's menu sequence and
   get the same `last action -> button item` the manual `xdotool` run produced.
4. `Win32Synthesiser` against `SendInput`. → verify: the same file, the same
   result, on Windows.
5. Agreement between the two on the three things they define differently:
   double-click interval, drag, and where the frame origin sits. → verify: one
   file that double-clicks, drags a window by its title bar and returns it,
   producing the same end state on both platforms.
6. `replayActionFile` on GtkBackend, and `-actionfile` in one Pn. → verify: P19
   on both platforms from one file.
7. The remaining Pn get the flag. → verify: an action file per app in
   `testapp/actions/`, matching the test plan's numbered steps.

Steps 3 to 5 are where this works or does not, and they come before anything is
wired into an app on purpose. If XTEST and SendInput cannot be made to agree on
what a double click is, or on where the frame origin sits, the format changes
and everything above it is rework. Step 5 is called out separately because
agreement is not implied by each adapter working on its own — each can be
correct against its own platform and still disagree with the other.

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
