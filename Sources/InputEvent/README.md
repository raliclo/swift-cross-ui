# InputEvent

Synthesised input, driven from a CSV file, with one format for every platform.

An app built with SwiftCrossUI can be handed `-actionfile <path>` and will
replay the actions in that file against its own window: move the pointer, click,
hold a key, release it, wait. The point is a UI test that runs the same way on
Windows and on Linux, written once.

## Why this exists

`xdotool` drives GTK apps on Linux and cannot drive anything on Windows. It is
an X11 client and speaks XTEST; a SwiftCrossUI app on Windows is a Win32 HWND
and is not an X client. Installing an X server does not bridge that — measured:
the gvsbuild GTK 4 for Windows has no x11 backend compiled in, and
`GDK_BACKEND=x11` answers `No such backend: x11`.

So Windows needs `SendInput`, which is a Win32 function in `user32.dll` rather
than anything to install, and the two platforms need a shared vocabulary above
them. That vocabulary is this file format.

## The app drives itself

`-actionfile` is a flag on the application, not a separate tool. The app already
knows where its window is, so coordinates need no window search and no guessing
about decorations — the mistake that made an earlier external driver click on
nothing until it was switched to window-relative positions.

Both injection paths are system-wide: `SendInput` posts to the foreground
window, and XTEST posts to the X server's focus. The app therefore presents its
window before replaying anything.

## File format

RFC 4180 CSV, one header row, LF line endings. Eight columns, always in this
order. Unused columns are left empty rather than omitted.

```
action,x,y,origin,button,key,micros,note
```

| column | meaning |
|---|---|
| `action` | one of the verbs below |
| `x`, `y` | window-relative; see Coordinates |
| `origin` | `client` (default, may be left empty) or `frame` |
| `button` | `left`, `right` or `middle` |
| `key` | a key name from the table below |
| `micros` | microseconds |
| `note` | free text, ignored; write down what the step is checking |

### Verbs

| action | uses | meaning |
|---|---|---|
| `move` | `x`, `y` | move the pointer, no button change |
| `click` | `button`, optional `x`, `y` | press and release once; moves first if a position is given |
| `doubleclick` | `button`, optional `x`, `y` | two press-release pairs inside the platform's double-click time |
| `mousedown` | `button`, optional `x`, `y` | press and hold |
| `mouseup` | `button`, optional `x`, `y` | release |
| `keydown` | `key` | press and hold |
| `keyup` | `key` | release |
| `key` | `key` | press and release once |
| `sleep` | `micros` | wait |

`mousedown` and `mouseup` exist so a drag can be written. `click` is a press and
a release with nothing between them, which cannot move a window by its title bar
or drag a slider — both need the button held down across a `move`.

### Dragging is not drag and drop

Holding a button across a move gets you a drag: moving a window by its title
bar, moving a slider's thumb, sweeping a text selection. That is what these
verbs are for and it is all they promise.

Drag and drop is a different thing. At the operating system level it is a
negotiation — XDND on X11, OLE on Windows — in which a source announces the
types it can provide, a target accepts or refuses, and data is transferred. It
is not "the button was down while the pointer moved". Synthesised mouse events
may set it off if an application implements the protocol, and may not; the
format does not promise either.

The question does not arise for this project yet in any case. SwiftCrossUI has
no drag-and-drop API — the only gesture a backend is asked for is a tap, through
`createTapGestureTarget` — so there is nothing above these verbs to exercise.

A `#` in the first column marks a comment row. Blank rows are skipped.

### Coordinates

Two origins, chosen per row by the `origin` column.

**`client`** — the default. `0,0` is the top-left of the client area, below the
title bar and inside the border. Use it for everything the app draws.

**`frame`** — `0,0` is the top-left of the window frame, including the title bar
and border. Use it only for the decorations: dragging the window by its title
bar, or pressing close, minimise and maximise.

The default is `client` because getting this wrong is what made an earlier
external driver click on nothing. It computed absolute positions from
`xdotool getwindowgeometry`, which under a reparenting window manager reports
the true position **plus** the frame offset that position already includes — so
every click missed by exactly the decoration. An app driving itself against
client coordinates never has to measure them.

`frame` is deliberately the opt-in, and it is less portable than `client` in a
way worth knowing before writing a file that uses it. Title bar height is not a
constant: it varies with the platform, the theme, and the display scale, and
under client-side decorations the title bar is drawn by the app itself rather
than by the window manager — so the frame and client origins coincide on one
machine and differ on another. Measured under WSLg's window manager, which
decorates server-side, the offset is 38 across and 59 down. A `frame` row
records a position on the machine it was written on. Prefer `client` wherever
the target is something the app drew.

Values are in **logical points**, the same unit the app's own layout uses — not
physical pixels.

On a display at 100% these are the same number and the distinction is invisible.
On a scaled display they are not, and a screenshot is in physical pixels: a
button read off a capture at 150% is at 1.5× the coordinate the file should
carry. Divide by the scale factor when reading positions from a screenshot.

Points rather than pixels because a file is meant to survive being run
somewhere else. A file in physical pixels is correct only on the display scale
it was written at, and fails by clicking somewhere plausible rather than by
saying so.

### Example

```csv
action,x,y,origin,button,key,micros,note
# P21 test plan steps 1 and 2
click,60,181,,left,,,press Enabled under Button
sleep,,,,,,500000,let the click register
click,157,181,,left,,,press Disabled; clicks must not rise
sleep,,,,,,500000,
key,,,,,tab,,move focus to the next control
keydown,,,,,shift,,hold shift
key,,,,,tab,,shift-tab moves focus back
keyup,,,,,shift,,release shift
```

Dragging the window by its title bar, which is what `frame` and the mouse
press/release pair are for:

```csv
action,x,y,origin,button,key,micros,note
mousedown,200,18,frame,left,,,grab the title bar
move,400,300,frame,,,,drag
sleep,,,,,,100000,let the window manager follow
move,600,400,frame,,,,keep dragging
mouseup,600,400,frame,left,,,let go
```

## Key names

Names follow macOS. They are Carbon's `kVK_*` constants from
`HIToolbox/Events.h` — the codes `NSEvent.keyCode` returns — with the `kVK_`
prefix and the `ANSI_` infix dropped, and the first letter lowercased.

macOS is used as the source rather than a set invented here, or either of the
two platforms this actually runs on, for three reasons. It is a real
specification with real documentation, so an argument about what a name means
has somewhere to go. It is complete, including the keypad and the right-hand
modifiers, which an invented list would have discovered it needed later. And it
belongs to the third backend, so neither Linux nor Windows spelling wins by
default and neither file reads as the native one.

| name | notes |
|---|---|
| `a`–`z` | from `kVK_ANSI_A`–`Z` |
| `0`–`9` | from `kVK_ANSI_0`–`9` |
| `return`, `tab`, `space`, `escape` | |
| `delete`, `forwardDelete` | **read the warning below** |
| `leftArrow`, `rightArrow`, `upArrow`, `downArrow` | |
| `home`, `end`, `pageUp`, `pageDown` | |
| `shift`, `control`, `option`, `command` | left-hand; `rightShift`, `rightControl`, `rightOption`, `rightCommand` exist too |
| `capsLock`, `function` | |
| `f1`–`f20` | |
| `keypad0`–`keypad9`, `keypadDecimal`, `keypadPlus`, `keypadMinus`, `keypadMultiply`, `keypadDivide`, `keypadEnter`, `keypadEquals`, `keypadClear` | from `kVK_ANSI_Keypad*` |

### `delete` is Backspace

This is Mac's meaning and adopting Mac names adopts it. `kVK_Delete` is the key
above Return that deletes backwards; `kVK_ForwardDelete` is the one usually
labelled Delete elsewhere. A file that says `delete` and means the forward one
will erase the wrong character, quietly, on every platform at once — the format
is consistent here, it is just consistently surprising if you learned the names
somewhere else.

### `command` is a physical key, not "the shortcut modifier"

`command` maps to the Windows key on Windows and to Super on Linux, because that
is the key in the same place. It does not mean "whatever this platform uses for
shortcuts".

That distinction matters and it is a real limit. A Mac shortcut is
Command-based where the same shortcut is Control-based elsewhere, so an action
file that exercises a shortcut cannot be identical across platforms even though
the key names are. Replaying input reproduces keystrokes, not intent. Where a
file needs the platform's shortcut modifier, write `control` and accept that the
Mac run differs — or keep shortcut checks out of action files and drive them
from the app's own key handling.

### Combinations

Expressed as `keydown` / `key` / `keyup` triples rather than as `command+a`, so
that a file records exactly what was pressed and when. A single token with a `+`
in it hides the timing, and timing is the thing these files are for.

## Timing

`micros` is microseconds, and the resolution is not. Both platforms schedule on
timers with roughly millisecond granularity, and a sleep of 500 microseconds
will usually take at least a millisecond. The column is microseconds so that a
file can state its intent precisely; do not read the unit as a promise about
what the operating system will deliver.

## Using it from an app

Three things, and the third is not optional:

```swift
DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
    let synthesiser = try XdotoolSynthesiser()   // Win32Synthesiser on Windows
    try synthesiser.replayFile(at: file)
}
```

1. **A flag** — `-actionfile <path>`, parsed from `CommandLine.arguments`.
2. **A delay** — both injection paths post to the focused window, and at
   `onAppear` the window has been created but not necessarily presented and
   focused. A file replayed then drives whatever was in front.
3. **A background queue** — never the main one. `Synthesiser` is deliberately
   not `@MainActor`. A replay is nearly all sleeping, and on the main thread
   that sleep is the UI's: posted events queue up unprocessed, so a menu never
   opens and the click meant for its item lands on the window behind. Measured,
   with the failure looking exactly like a product defect — the replay reported
   success and the screen had not changed.

## What this is not

It is not a recorder — there is nothing here that captures input to produce a
file. It replays what someone wrote.

It does not assert. A file describes actions; whether the result is correct is
decided by the app's own diagnostics, a screenshot, or a person. Mixing
assertions into the format would make it a test framework, and the project
already has one in `testapp/test_support/`.
