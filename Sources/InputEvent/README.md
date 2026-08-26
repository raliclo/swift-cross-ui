# InputEvent

Synthesised input, driven from a CSV file, with one format for every platform.

An app built with SwiftCrossUI can be handed `-actionfile <path>` and will
replay the actions in that file against its own window: move the pointer, click,
hold a key, release it, wait. The point is a UI test that runs the same way on
Windows, Linux and macOS, written once.

## Why this exists

`xdotool` drives GTK apps on Linux and cannot drive anything on Windows. It is
an X11 client and speaks XTEST; a SwiftCrossUI app on Windows is a Win32 HWND
and is not an X client. Installing an X server does not bridge that — measured:
the gvsbuild GTK 4 for Windows has no x11 backend compiled in, and
`GDK_BACKEND=x11` answers `No such backend: x11`.

So Windows needs `SendInput`, which is a Win32 function in `user32.dll` rather
than anything to install, and the platforms need a shared vocabulary above them.
That vocabulary is this file format.

macOS came third and took a different route. It has the system-wide equivalent
-- `CGEvent.post` -- and it is unusable in practice, because it silently
delivers nothing until somebody grants the process Accessibility permission in
System Settings. Measured on macOS 27 with the terminal untrusted: `CGEvent.post`
and `CGEvent.postToPid(getpid())` both delivered zero events, with no error;
`NSApp.postEvent` delivered, and a real `NSButton` fired. So `AppKitSynthesiser`
posts into the app's own event queue instead. It needs no permission, addresses
its window by number rather than by whoever is in front, and works while the app
is in the background.

## The app drives itself

`-actionfile` is a flag on the application, not a separate tool. The app already
knows where its window is, so coordinates need no window search and no guessing
about decorations — the mistake that made an earlier external driver click on
nothing until it was switched to window-relative positions.

Action files are platform-specific. The repository folders are the first visual
boundary (`actions/mac`, `actions/wsl`, `actions/win`, and so on), and the CSV
also records the verified backend in its final `platform` column. A file marked
`macos` is accepted by AppKit only; `gtk` covers both WSLg and native Linux;
`windows` is for WinUI; `ios` and `android` identify their native test runners.
Multiple verified platforms may be separated with `|`, such as `macos|gtk`.
If a platform needs a different coordinate sequence, keep it in that platform's
folder and give it a `-{platform}` filename suffix; the suffix is documentation,
while the CSV column is the enforced declaration.
The old eight-column format remains valid and means `any`, so existing files
fail neither parsing nor replay, but new files should always state their
platform.

動作檔是平台特定的。repository 資料夾是第一層明確界線（`actions/mac`、
`actions/wsl`、`actions/win` 等），CSV 最後的 `platform` 欄位也會記錄已驗證的
backend。標記為 `macos` 的檔案只接受 AppKit；`gtk` 同時涵蓋 WSLg 與原生 Linux；
`windows` 則代表 WinUI；`ios` 與 `android` 代表各自的原生測試執行器。若同一檔案已在多個平台驗證，
可用 `|` 分隔，例如 `macos|gtk`。若某平台需要不同的座標流程，應放在該平台資料夾並使用
`-{platform}` 檔名 suffix；suffix 只是文件說明，真正強制檢查的仍是 CSV 欄位。舊有八欄格式仍然有效
並視為 `any`，因此不會因 parser 或 replay 而失敗；但新檔案應一律填寫 platform。

Both injection paths are system-wide: `SendInput` posts to the foreground
window, and XTEST posts to the X server's focus. The app therefore presents its
window before replaying anything.

## File format

RFC 4180 CSV, one header row, LF line endings. Nine columns, always in this
order. Unused columns are left empty rather than omitted.

```
action,x,y,origin,button,key,micros,note,platform
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
| `platform` | `any`, `macos`, `windows`, `gtk`, `ios` or `android`; use `|` for multiple platforms; blank means `any` |

### Verbs

| action | uses | meaning |
|---|---|---|
| `move` | `x`, `y` | move the pointer, no button change |
| `click` | `button`, optional `x`, `y` | press and release once; moves first if a position is given |
| `doubleclick` | `button`, optional `x`, `y` | two press-release pairs inside the platform's double-click time |
| `mousedown` | `button`, optional `x`, `y` | press and hold |
| `mouseup` | `button`, optional `x`, `y` | release |
| `scroll` | `x`, `y` as **wheel notches** | turn the wheel where the pointer is |
| `keydown` | `key` | press and hold |
| `keyup` | `key` | release |
| `key` | `key` | press and release once |
| `sleep` | `micros` | wait |

### `scroll` reads `x` and `y` as a delta, not a position

`scroll,0,3` means three notches down. Positive `y` scrolls down, positive `x`
scrolls right.

It takes no position of its own, deliberately: a wheel event goes to whatever is
under the pointer, so a file that scrolls has to put the pointer somewhere first,
and `move` already does that. Giving `scroll` a position too would make it
possible to write a row that names one place and scrolls another.

```csv
move,400,300,,,,,put the pointer over the table
scroll,0,3,,,,,three notches down
```

The sign convention is GDK's, and Windows' horizontal wheel agrees with it.
Windows' *vertical* wheel does not — there a positive delta means rotation away
from the user, which scrolls up — and that inversion is handled inside the
synthesiser so the same file means the same thing on both platforms.

`origin` is meaningless on a scroll row. A `frame` there is a sign the writer
expected the verb to move the pointer.

`scroll,0,3` 代表向下三格。`y` 為正是向下，`x` 為正是向右。

它刻意不帶自己的位置：滾輪事件會送往指標下方的元件，因此會捲動的檔案必須先把指標移到某處，而
`move` 已能做到。若讓 `scroll` 也帶位置，就可能寫出「宣稱在某處、實際捲動另一處」的一列。

符號慣例採用 GDK 的定義，Windows 的水平滾輪與之一致。Windows 的**垂直**滾輪則不然——該處正的
delta 代表遠離使用者的轉動，亦即向上捲動——此項反轉在 synthesiser 內部處理，使同一個檔案在兩個
平台上意義相同。

`origin` 在 scroll 列上毫無意義。若該處出現 `frame`，即代表撰寫者誤以為此動作會移動指標。

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
action,x,y,origin,button,key,micros,note,platform
# P21 test plan steps 1 and 2
click,60,181,,left,,,press Enabled under Button,gtk
sleep,,,,,,500000,let the click register,gtk
click,157,181,,left,,,press Disabled; clicks must not rise,gtk
sleep,,,,,,500000,,gtk
key,,,,,tab,,move focus to the next control,gtk
keydown,,,,,shift,,hold shift,gtk
key,,,,,tab,,shift-tab moves focus back,gtk
keyup,,,,,shift,,release shift,gtk
```

Dragging the window by its title bar, which is what `frame` and the mouse
press/release pair are for:

```csv
action,x,y,origin,button,key,micros,note,platform
mousedown,200,18,frame,left,,,grab the title bar,macos
move,400,300,frame,,,,drag,macos
sleep,,,,,,100000,let the window manager follow,macos
move,600,400,frame,,,,keep dragging,macos
mouseup,600,400,frame,left,,,let go,macos
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

## Using it from a backend

One call, from wherever the backend shows a window:

```swift
#if SCUI_DEBUG
    ActionFileReplay.replayIfRequested()
#endif
```

That is the whole integration. `AppKitBackend`, `GtkBackend` and `WinUIBackend`
each contain exactly that and nothing else.

It used to be three things a backend had to get right for itself, and the three
are still worth knowing because `ActionFileReplay` is doing them on your behalf:

1. **A flag** — `-actionfile <path>`, parsed from `CommandLine.arguments`, and
   guarded so it replays once per process rather than once per window.
2. **A delay** — the Windows and Linux paths post to the focused window, and
   when a window has just been shown it is not necessarily presented and
   focused. A file replayed then drives whatever was in front. macOS addresses
   its own window by number and cannot make that mistake, but still needs the
   window laid out before a coordinate means anything.
3. **A background queue** — never the main one. `Synthesiser` is deliberately
   not `@MainActor`. A replay is nearly all sleeping, and on the main thread
   that sleep is the UI's: posted events queue up unprocessed, so a menu never
   opens and the click meant for its item lands on the window behind. Measured,
   with the failure looking exactly like a product defect — the replay reported
   success and the screen had not changed.

Two backends did reimplement all of it, and the copies had already started to
disagree in their documentation about a delay both of them set to one second.
That is why it lives here now.

`makeSynthesiser()` picks the implementation for the platform, and is the only
place that choice is written down. A platform without one throws rather than
returning something that quietly does nothing — iOS today, since `UIKitBackend`
has no synthesiser.

## What this is not

It is not a recorder — there is nothing here that captures input to produce a
file. It replays what someone wrote.

It does not assert. A file describes actions; whether the result is correct is
decided by the app's own diagnostics, a screenshot, or a person. Mixing
assertions into the format would make it a test framework, and the project
already has one in `testapp/test_support/`.
