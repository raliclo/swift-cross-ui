# queue

由 `heartbeats/heartbeat.zsh` 讀取。**未完成寫 `- [ ]`,完成改成 `- [x]`。**
順序即優先序:第一個未完成項就是下一件事。

Read by `heartbeats/heartbeat.zsh`. Order is priority: the first unchecked
item is the next thing. This file exists because the queue used to live in the
conversation, where it faded with compaction and its absence looked exactly like
an empty queue -- mistakes.md entry 1.

- [ ] Q8/Q10 `Settings` scene, `SceneStorage`, `DocumentGroup` — design first, see the note below
- [ ] Q12 #28 animation / #30 focus accessibility / #32 gestures
- [ ] #74 `-GPU` on macOS — design, waiting on Windows input
- [ ] #117 phase 3: on-demand row creation — criterion is now "RSS stops growing", 114 MB at 400 rows vs 423 MB at 10,000
- [x] #117 phase 2: AppKit list viewport (`1ff4f3cf`)
- [x] #117 phase 4a: UIKit and Android list viewport (`c88e3994`)
- [x] Review 4: two ScrollViewReaders driven on AppKit and Android (P58, `6c417aaf`)
- [x] Review 6: parity survey #33 summary row reconciled with its detail row
- [x] Remote session ping: WSL works and was driven end to end from the Mac (tmux 3.6 there, `config2WSL` port 16889); the Windows-native side (MSYS2) has neither tmux nor screen, and WSL's tmux cannot reach a session that is not inside WSL
- [ ] #117 phase 5: GTK and WinUI list viewport — sent to Windows 2026-09-09, theirs to verify

## Q8 note — what was measured before writing any code

`Settings` cannot simply be a second window. Measured 2026-09-09:

| backend | `supportsMultipleWindows` | what a second window does |
| --- | --- | --- |
| AppKit | true | a real window |
| Gtk | true | a real window |
| WinUI | true | a real window |
| UIKit | **false** | `createWindow` builds a second `UIWindow` |
| Android | **false** | `createWindow` returns a fresh `Window()` value with a `TODO` beside it — **nothing appears** |

So a window-based `Settings` would be silently invisible on Android, which is
the shape CLAUDE.md forbids. `AlertScene` takes `window: nil` and lets the
backend choose; `presentSheet` needs a concrete `Window`. The single-window path
is the design question, and it is the whole of the work — not the scene struct.
