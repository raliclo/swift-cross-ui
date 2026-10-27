# WSLg copy mode: every capture is black, test.zsh exits 7

Written 2026-10-24 from bugs/bug-WSLg.md #1 and
`testapp/test_support/test_common.zsh` (`wslg_keeper`, the end-of-run check).

## What

About two and a half minutes after the last WSLg window closes, WSLg restarts
itself: `/mnt/wslg/weston.log` starts over and Windows' `msrdc.exe` gets a new
PID, while the VM keeps running (`/proc/uptime` does not reset). Every window
after that restart has `[WARN:COPY MODE]` in its title, and a capture of it
through `testapp/helper/bin/wincap.exe` (Windows Graphics Capture or
PrintWindow) is 0.0% non-black whatever the app drew. It is not GPU-related:
`xclock`, a GTK window with `GSK_RENDERER=cairo`, and `-render sw` all show it.
It lasts until `wsl --shutdown`. Nothing is logged (dmesg,
`/mnt/wslg/stderr.log`, Windows System events).

## How the harness handles it

- `wslg_keeper`, first step of every `test.zsh --wsl` run: keeps an 80x80
  `xclock` (from x11-apps) open for as long as WSL runs, so WSLg never sees
  "no windows" and never restarts. With it, 200 s idle kept the same weston
  and `msrdc.exe` and P76 captured normally (rc=0); without it the same 200 s
  ended in copy mode (rc=7).
- Two attempts: keep a running `xclock`, then replace it. After the laptop
  slept, the old `xclock` was still running with no window on the Windows side
  (2026-10-19, 01cd00c3); a keeper with no window keeps nothing alive.
- The keeper's title is read with `winmin.exe --list` before anything is
  built. A copy-mode title stops the run with exit 7 and the advice to run
  `wsl --shutdown`.
- At the end of the run, if every screenshot failed, `test.zsh` exits 7 and
  names copy mode when wincap's output contained `WARN:COPY MODE`. Before this
  check, P76 under WSLg exited 0 four times with every screenshot black
  (2026-10-14).

## How to apply

- Exit 7 from a WSL run means nothing was verified. Look for copy mode first;
  a missing window (the app exited before the capture) gives the same exit.
- Recovery is only `wsl --shutdown`. It stops everything in WSL (multisshd
  too), so it is the machine owner's call. Ending `msrdc.exe` alone does not
  help: a new one starts and windows stay in copy mode.
- Leave the keeper `xclock` running; `winmin --clear` minimises it with the
  rest.
- The signal is the window title. `/mnt/wslg/weston.log` saying
  `enable_copy_warning_title = 1` is only the setting, not a report.

## Evidence

- P12 and P14 under WSLg: two runs each on 2026-10-21 and 2026-10-22, all
  exit 7 (gtk-pairs-wsl.csv2 on the Windows machine, 71ac0e0d). Those apps are
  out of scope there; the failed runs are recorded, not hidden.

## Limits

Measured 2026-10-14 on Windows 10.0.26300.9711, WSL 2.7.14.0, kernel
6.18.33.2-2, WSLg 1.0.73.2, MSRDC 1.2.7214. Re-check after any of those change;
`wsl --version` prints them. A related but separate effect: while the Windows
desktop is locked, Windows Graphics Capture of WSLg windows is unreliable, and
results.csv2 rows of 2026-10-20 use log lines as evidence for that reason.

---

# WSLg 的 copy mode:每張擷取都是黑的,test.zsh 以 7 結束

2026-10-24 依 bugs/bug-WSLg.md #1 與 `testapp/test_support/test_common.zsh`(`wslg_keeper`、執行結尾的檢查)寫成。

## 是什麼

最後一個 WSLg 視窗關閉約兩分半後,WSLg 會自行重啟:`/mnt/wslg/weston.log` 從頭開始,Windows 的 `msrdc.exe`
換了新的 PID,而虛擬機仍在執行(`/proc/uptime` 沒有歸零)。重啟後的每個視窗標題都帶 `[WARN:COPY MODE]`,
經由 `testapp/helper/bin/wincap.exe`(Windows Graphics Capture 或 PrintWindow)的擷取不論 app 畫了什麼都是 0.0%
非黑。與 GPU 無關:`xclock`、`GSK_RENDERER=cairo` 的 GTK 視窗、`-render sw` 都一樣。會持續到 `wsl --shutdown`。
任何地方都沒有紀錄(dmesg、`/mnt/wslg/stderr.log`、Windows 系統事件)。

## harness 怎麼處理

- `wslg_keeper` 是每次 `test.zsh --wsl` 的第一步：只要 WSL 在執行，就讓一個 80x80 的 `xclock`(來自 x11-apps)
  一直開著,WSLg 便不會碰到「沒有視窗」而重啟。有它時閒置 200 秒,weston 與 `msrdc.exe` 仍是同一份,P76 擷取
  正常(rc=0);沒有它時同樣 200 秒以 copy mode 收場(rc=7)。
- 兩次嘗試：先保留正在執行的 `xclock`,再換掉它。筆電睡眠喚醒後，舊的 `xclock` 仍在執行，但在 Windows 端沒有
  視窗(2026-10-19,01cd00c3);沒有視窗的 keeper 什麼都撐不住。
- 建置任何東西之前，先用 `winmin.exe --list` 讀 keeper 的標題。標題是 copy mode 就以 7 結束，並提示執行
  `wsl --shutdown`。
- 執行結尾若每張截圖都失敗,`test.zsh` 以 7 結束;wincap 輸出含 `WARN:COPY MODE` 時會點名 copy mode。加上這項
  檢查之前,P76 在 WSLg 下四次以 0 結束，而每張截圖都是黑的(2026-10-14)。

## 怎麼用

- WSL 執行以 7 結束，代表什麼都沒驗證到。先找 copy mode;沒有視窗(app 在擷取前就結束)也會得到同樣的結束碼。
- 唯一的恢復方式是 `wsl --shutdown`。它會停止 WSL 內的一切(包括 multisshd),由機器的主人決定。單獨結束
  `msrdc.exe` 沒用：會啟動新的一個，視窗仍是 copy mode。
- 讓 keeper 的 `xclock` 一直執行;`winmin --clear` 會連同其他視窗把它最小化。
- 訊號是視窗標題。`/mnt/wslg/weston.log` 裡的 `enable_copy_warning_title = 1` 只是設定，不是回報。

## 證據

- WSLg 下的 P12 與 P14:2026-10-21 與 2026-10-22 各兩次，全部以 7 結束(Windows 機器上的 gtk-pairs-wsl.csv2,
  71ac0e0d)。這兩支 app 在那裡不在範圍內；失敗的執行照實記下，沒有被掩蓋。

## 限制

2026-10-14 實測於 Windows 10.0.26300.9711、WSL 2.7.14.0、核心 6.18.33.2-2、WSLg 1.0.73.2、MSRDC 1.2.7214。任一
版本改變後要重新查證;`wsl --version` 會印出全部。另一個相關但不同的現象:Windows 桌面鎖定時,Windows Graphics
Capture 擷取 WSLg 視窗並不可靠,results.csv2 中 2026-10-20 的列因此以 log 行為證據。
