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

RFC 4180 CSV, one header row, LF line endings. Seven columns, always in this
order. Unused columns are left empty rather than omitted.

```
action,x,y,button,key,micros,note
```

| column | meaning |
|---|---|
| `action` | one of the verbs below |
| `x`, `y` | window-relative pixels, origin at the top-left of the client area |
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
| `keydown` | `key` | press and hold |
| `keyup` | `key` | release |
| `key` | `key` | press and release once |
| `sleep` | `micros` | wait |

A `#` in the first column marks a comment row. Blank rows are skipped.

### Example

```csv
action,x,y,button,key,micros,note
# P21 test plan steps 1 and 2
click,60,181,left,,,press Enabled under Button
sleep,,,,,500000,let the click register
click,157,181,left,,,press Disabled; clicks must not rise
sleep,,,,,500000,
key,,,,Tab,,move focus to the next control
keydown,,,,shift,,hold shift
key,,,,Tab,,shift-Tab moves focus back
keyup,,,,shift,,release shift
```

## Key names

One name per key, mapped to a keysym on Linux and a virtual-key code on Windows.
Neither platform's native spelling is used directly, because they disagree and a
file written against one would silently do nothing on the other.

| name | notes |
|---|---|
| `a`–`z`, `0`–`9` | unshifted characters |
| `space`, `tab`, `enter`, `escape`, `backspace`, `delete` | |
| `up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown` | |
| `shift`, `ctrl`, `alt`, `super` | modifiers, for use with `keydown`/`keyup` |
| `f1`–`f12` | |

Combinations are expressed as `keydown` / `key` / `keyup` triples rather than as
`ctrl+a`, so that a file records exactly what was pressed and when. A single
token with a `+` in it hides the timing, and timing is the thing these files are
for.

## Timing

`micros` is microseconds, and the resolution is not. Both platforms schedule on
timers with roughly millisecond granularity, and a sleep of 500 microseconds
will usually take at least a millisecond. The column is microseconds so that a
file can state its intent precisely; do not read the unit as a promise about
what the operating system will deliver.

## What this is not

It is not a recorder — there is nothing here that captures input to produce a
file. It replays what someone wrote.

It does not assert. A file describes actions; whether the result is correct is
decided by the app's own diagnostics, a screenshot, or a person. Mixing
assertions into the format would make it a test framework, and the project
already has one in `testapp/test_support/`.
