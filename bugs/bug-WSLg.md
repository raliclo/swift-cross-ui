# WSLg bugs and limitations / WSLg 的缺陷與限制

Defects that live in WSL / WSLg and Windows' `msrdc.exe`, not in this project.
As with `Gtk4-bugs.md`, the only decisions available to us are how to detect
each one and how to work around it, and every entry records the versions it was
measured on. **Re-check an entry before relying on it once any of those
versions has changed** -- `wsl --version` prints all of them.

本檔記錄的是存在於 WSL / WSLg 與 Windows 的 `msrdc.exe`、而非本專案的缺陷。與 `Gtk4-bugs.md` 相同，
我們能做的決定只有「如何偵測」與「如何繞過」,而每一條都記下實測所在的版本。**只要其中任何一個版本
變了，依賴某條之前請重新查證**——`wsl --version` 會印出全部版本。

---

## 1. After WSLg restarts itself, every window is in COPY MODE and captures black

**Measured 2026-10-14** on:

| component | version |
| --- | --- |
| Windows | 10.0.26300.9711 (Windows 11 Home) |
| WSL | 2.7.14.0 |
| WSL kernel | 6.18.33.2-2 |
| WSLg | 1.0.73.2 |
| MSRDC | 1.2.7214 |
| Direct3D | 1.611.1-81528511 |
| Machine | ASUS TUF A15 FA507NV, AMD Radeon iGPU + NVIDIA RTX 4060 Laptop, both "Started" |

**Symptom.** Every WSLg window's title gains `[WARN:COPY MODE]`, and a capture
of it (Windows Graphics Capture or PrintWindow, through `testapp/helper/bin/wincap.exe`)
is 0.0% non-black, whatever the app drew. It is not GPU-specific: `xclock`
(X11, no GL) and a GTK window forced to cairo (`GSK_RENDERER=cairo`) get the
same title, as does a D3D12-backed GL window, and `-render sw` (llvmpipe) does
not help. Once it happens it stays until WSL is shut down.

**Trigger.** About two and a half minutes after the **last WSLg window closes**,
WSLg restarts itself: `/mnt/wslg/weston.log` starts over and Windows'
`msrdc.exe` gets a new PID, while the VM keeps running (`/proc/uptime` does not
reset). Every window after that restart is in copy mode. No crash is logged
anywhere (dmesg, `/mnt/wslg/stderr.log`), and no Windows System event lines up
with it (no display reset, sleep or power event).

Ruled out, each by a run that stayed normal: closing every window and opening
another within seconds; an incremental WSL build; a rebuild of the whole `Gtk`
module (peak memory about 1.4 GB of 15.6 GB); syncing the source tree over
`/mnt/c`; Chrome Remote Desktop and display changes (none at the time).

**Reproduction.**

```sh
# after `wsl --shutdown`; nothing else WSLg open
zsh testapp/test.zsh P76 --wsl --no-build --showtime 3   # normal window, rc=0
# leave WSL idle for 200 s
zsh testapp/test.zsh P76 --wsl --no-build --showtime 3   # [WARN:COPY MODE], rc=7
```

**Recovery.** Only `wsl --shutdown` brings shared mode back; it stops everything
in WSL, so it is the user's to run. Ending `msrdc.exe` alone did not: a new one
started and the windows stayed in copy mode. A WSLg restart is the trigger
itself, so restarting WSLg cannot be the cure.

**Workaround, in `testapp/test_support/test_common.zsh` (`wslg_keeper`).** Keep
one WSLg window open for as long as WSL runs, so WSLg never sees "no windows"
and never restarts. With an 80x80 `xclock` left open, 200 s of idling kept the
same weston and `msrdc.exe`, and P76 captured normally (rc=0); without it the
same 200 s ended in copy mode (rc=7). `test.zsh --wsl` opens the keeper if none
is running and reads its title before building anything; a copy-mode title
there stops the run with exit 7 and the `wsl --shutdown` advice. A run in which
every capture failed also exits 7 and names copy mode when the title shows it.

**Detection, for anything else.** The window title is the signal. `test.zsh`
greps wincap's output for `WARN:COPY MODE`; `/mnt/wslg/weston.log` only says
`enable_copy_warning_title = 1`, which is the setting that adds the title, not a
report that it happened.

## 1. WSLg 自行重啟後，每個視窗都處於 COPY MODE,擷取全黑

**2026-10-14 實測**,版本如上表。

**症狀。**每個 WSLg 視窗的標題都多了 `[WARN:COPY MODE]`,而對它的擷取(經由 `testapp/helper/bin/wincap.exe`
的 Windows Graphics Capture 或 PrintWindow)不論 app 畫了什麼都是 0.0% 非黑。這與 GPU 無關:`xclock`
(X11、不用 GL)與強制 cairo 繪製的 GTK 視窗也得到同樣的標題，以 D3D12 繪製的 GL 視窗亦然,`-render sw`
(llvmpipe)也沒有幫助。一旦發生就會持續到 WSL 關閉為止。

**觸發條件。**最後一個 WSLg 視窗關閉約兩分半後,WSLg 會自己重啟:`/mnt/wslg/weston.log` 從頭開始，
Windows 的 `msrdc.exe` 換了新的 PID,而虛擬機仍在執行(`/proc/uptime` 沒有歸零)。重啟之後的每個視窗
都處於 copy mode。任何地方都沒有當掉的紀錄(dmesg、`/mnt/wslg/stderr.log`),也沒有對得上的 Windows
系統事件(沒有顯示重置、睡眠或電源事件)。

已排除，每一項都以一次維持正常的執行為證：關掉所有視窗並在數秒內開新的；WSL 內的增量建置；重編整個
`Gtk` 模組(記憶體高峰約 1.4 GB / 15.6 GB);經由 `/mnt/c` 同步原始碼樹;Chrome 遠端桌面與顯示設定變更
(當時都沒有)。

**重現。**見上方指令：`wsl --shutdown` 後第一次執行正常(rc=0),閒置 200 秒後第二次執行為 COPY MODE(rc=7)。

**恢復。**只有 `wsl --shutdown` 能恢復共享模式；它會停止 WSL 內的一切，因此由使用者執行。單獨結束
`msrdc.exe` 沒有用：會啟動新的一個，視窗仍是 copy mode。WSLg 重啟本身就是觸發條件，所以重啟 WSLg
不可能是解法。

**繞過方式，位於 `testapp/test_support/test_common.zsh`(`wslg_keeper`)。**只要 WSL 在執行，就讓一個
WSLg 視窗一直開著，WSLg 便永遠不會碰到「沒有視窗」,也就不會重啟。留著 80x80 的 `xclock` 時，閒置
200 秒後 weston 與 `msrdc.exe` 仍是同一份，P76 擷取正常(rc=0);沒有它時，同樣的 200 秒以 copy mode
收場(rc=7)。`test.zsh --wsl` 會在沒有 keeper 時開一個，並在建置任何東西之前讀它的標題；標題已是 copy
mode 時以結束碼 7 停止，並提示 `wsl --shutdown`。每張擷取都失敗的執行同樣以 7 結束，標題顯示 copy mode
時也會點名。

**偵測方式，供其他用途。**訊號是視窗標題。`test.zsh` 在 wincap 的輸出裡 grep `WARN:COPY MODE`;
`/mnt/wslg/weston.log` 只寫著 `enable_copy_warning_title = 1`,那是「加上標題」的設定，不是「發生了」的回報。
