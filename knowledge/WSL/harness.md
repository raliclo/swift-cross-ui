# WSL harness: test.zsh --wsl from the Windows checkout

Written 2026-10-24 from `testapp/test.zsh`, `testapp/test_support/test_common.zsh`
(`run_wsl` and helpers), `testapp/sweep-test/sweep_drive_wsl.zsh` and
`testapp/test_support/measure/measure_wsl.zsh`.

## What

WSL runs are driven from Windows, not from inside WSL. `test.zsh` runs in the
Windows checkout's MSYS2/Git Bash shell; `--wsl` and `--both` are offered only
on a Windows host (`host_platform` MINGW/MSYS/CYGWIN) because every step goes
through `wsl.exe -d Ubuntu`. `--both` runs WSL first, then Windows.

```sh
zsh testapp/test.zsh P76 --wsl                     # build, launch, capture
zsh testapp/test.zsh P76 --wsl -n --showtime 3     # no build
zsh testapp/test.zsh P76 --wsl -render sw          # llvmpipe
zsh testapp/test.zsh P10 --wsl --actionfile testapp/actions/wsl/P10-taplabel.actions
```

## One run, in order

1. `check_wsl_host.zsh --quiet`: Windows-side disk and memory warnings
   ([host-disk-and-memory.md](host-disk-and-memory.md)).
2. `wslg_keeper`: keeper window, copy-mode check, exit 7
   ([copy-mode.md](copy-mode.md)).
3. `wslg_portal_display`: display variables for the portal
   ([file-dialog-portal.md](file-dialog-portal.md)).
4. `wsl_renderer_preflight`: `eglinfo` must match `-render`
   ([gpu-and-renderer.md](gpu-and-renderer.md)).
5. Unless `-n`: `rsync_WSL.zsh`, then `compile.zsh Pn` inside
   `/home/<user>/proj/swift-cross-ui` ([wsl-checkout.md](wsl-checkout.md)).
   `SCUI_DEBUG=1` is set when an action file is given; without it the
   `-actionfile` flag is not compiled in. A failed build exits 1 and prints
   the log tail (`run_build`); before 9cd24054 it launched the previous binary
   and returned 0.
6. Launch from `testapp/output` in the WSL checkout with
   `SCUI_DEBUG_EVENTS_DIR=/home/<user>/proj/swift-cross-ui/testapp/debug-events
   GDK_BACKEND=x11 GTK_CSD=1`, the render environment, `SCUI_GTK_COLOR_SCHEME=dark`
   and `TEST_APP_ENV`; stdout and stderr go to a log
   in the WSL `testapp/output`.
7. Capture at 1 s with `wincap.exe` on the Windows side, wait for the app's
   marker in its Linux event log (`wait_for_marker_wsl`), keep the window up for
   the showtime (30 s default), capture again, `pkill` the app, print the
   renderer and summary lines read back through `wsl.exe`.

## Rules learned crossing wsl.exe

- `$var` inside the command string is eaten crossing from Windows to WSL, even
  inside single quotes. Every path is expanded on the Windows side first, so
  only literal text crosses. Conditionals are built on the Windows side too.
- `MSYS2_ARG_CONV_EXCL='*'` on every `wsl.exe` call, or MSYS rewrites POSIX
  paths on the way out.
- App arguments travel as one string to `zsh -lc`: no `(q)` (the inner shell
  sees one word) and no `(z)` (`-lc` takes only the first word as the
  command). Quote a value with a space inside `TEST_APP_ARGS` itself.
- An action file is re-rooted onto the WSL checkout
  (`/home/<user>/proj/swift-cross-ui/testapp/<relative>`), never `/mnt/c/...`,
  which would replay whatever the Windows copy holds; a path outside
  `testapp/` is refused (exit 64).

## Exit codes

| code | meaning |
|---|---|
| 1 | build failed; nothing launched |
| 6 | an action file did not replay ("replayed" line missing, or "failed") |
| 7 | WSLg in copy mode before the run, or every capture failed |
| 64 | usage: target not drivable on this host, `-render` without WSL, action file outside `testapp/` |

## Related tools

- `sweep-test/sweep_drive_wsl.zsh`: one row per `actions/wsl` file (134 files
  as of 2026-10-22) into `matrix_coverage/results.csv2` as `wsl,gtk4`; the
  showtime is the file's sleeps plus 5 s (at least 10), and `# expect:` lines
  are judged met / UNMET / UNCHECKED.
- `test_support/measure/measure_wsl.zsh`: AT-SPI element centres in window
  coordinates, which are the numbers a WSL action-file row takes. It runs
  without `GTK_CSD`; the replay adds the header-bar offset itself. It closes a
  running instance first: a second GTK instance hands over and exits 0.

## Limits

- The distribution name `Ubuntu` and the path `/home/<user>/...` are written
  into the scripts.
- With the Windows desktop locked, input still replays over X11 but Windows
  Graphics Capture of WSLg windows is unreliable; use log lines as evidence or
  rerun unlocked (results.csv2, 2026-10-20 rows).
- Running a per-app script that itself calls `wsl.exe` from inside WSL goes
  out through interop and back; test_P26.zsh now detects being inside WSL
  (fixed 2026-10-22).

---

# WSL harness:從 Windows checkout 執行 test.zsh --wsl

2026-10-24 依 `testapp/test.zsh`、`testapp/test_support/test_common.zsh`(`run_wsl` 與其輔助函式)、
`testapp/sweep-test/sweep_drive_wsl.zsh` 與 `testapp/test_support/measure/measure_wsl.zsh` 寫成。

## 是什麼

WSL 測試由 Windows 端驅動，不是在 WSL 內執行。`test.zsh` 在 Windows checkout 的 MSYS2/Git Bash shell 中執行;
`--wsl` 與 `--both` 只在 Windows 主機上提供(`host_platform` 為 MINGW/MSYS/CYGWIN),因為每一步都經由
`wsl.exe -d Ubuntu`。`--both` 先跑 WSL,再跑 Windows。指令範例見上方英文段落。

## 一次執行的順序

1. `check_wsl_host.zsh --quiet`:Windows 端的磁碟與記憶體警告([host-disk-and-memory.md](host-disk-and-memory.md))。
2. `wslg_keeper`:keeper 視窗、copy mode 檢查、結束碼 7([copy-mode.md](copy-mode.md))。
3. `wslg_portal_display`:給 portal 顯示變數([file-dialog-portal.md](file-dialog-portal.md))。
4. `wsl_renderer_preflight`:`eglinfo` 必須符合 `-render`([gpu-and-renderer.md](gpu-and-renderer.md))。
5. 除非加 `-n`:先 `rsync_WSL.zsh`,再於 `/home/<user>/proj/swift-cross-ui` 內執行 `compile.zsh Pn`
   ([wsl-checkout.md](wsl-checkout.md))。給了動作檔時會設 `SCUI_DEBUG=1`;少了它 `-actionfile` 旗標根本不會被編入。
   建置失敗以 1 結束並印出記錄尾段(`run_build`);9cd24054 之前會啟動上一次的執行檔並回傳 0。
6. 在 WSL checkout 的 `testapp/output` 中啟動，環境為
   `SCUI_DEBUG_EVENTS_DIR=/home/<user>/proj/swift-cross-ui/testapp/debug-events GDK_BACKEND=x11 GTK_CSD=1`、算繪環境與
   `SCUI_GTK_COLOR_SCHEME=dark` 加上 `TEST_APP_ENV`;stdout 與 stderr 寫入 WSL 端 `testapp/output` 的記錄。
7. 1 秒時在 Windows 端以 `wincap.exe` 擷取，等待 app 在 Linux 端事件 log 中的標記(`wait_for_marker_wsl`),讓視窗
   停留 showtime(預設 30 秒),再擷取一次,`pkill` 該 app,經由 `wsl.exe` 讀回並印出 renderer 與摘要行。

## 穿越 wsl.exe 的規則

- 命令字串中的 `$var` 從 Windows 跨到 WSL 時會被吃掉，即使包在單引號中。每條路徑都先在 Windows 端展開，只讓字面
  文字通過。條件判斷也在 Windows 端組好。
- 每個 `wsl.exe` 呼叫都加 `MSYS2_ARG_CONV_EXCL='*'`,否則 MSYS 會在送出時改寫 POSIX 路徑。
- app 參數以單一字串交給 `zsh -lc`:不能用 `(q)`(內層 shell 只看到一個詞),也不能用 `(z)`(`-lc` 只把第一個詞當
  命令)。含空白的值要在 `TEST_APP_ARGS` 內自行加引號。
- 動作檔會重新指向 WSL checkout(`/home/<user>/proj/swift-cross-ui/testapp/<相對路徑>`),絕不用 `/mnt/c/...`——那會
  重放 Windows 那份當下恰好的版本;`testapp/` 以外的路徑一律拒絕(結束碼 64)。

## 結束碼

| 碼 | 意義 |
|---|---|
| 1 | 建置失敗；沒有啟動任何東西 |
| 6 | 動作檔沒有重放(缺少「replayed」行，或出現「failed」) |
| 7 | 執行前 WSLg 已在 copy mode,或每張擷取都失敗 |
| 64 | 用法錯誤：此主機無法驅動該目標、非 WSL 卻給 `-render`、動作檔在 `testapp/` 之外 |

## 相關工具

- `sweep-test/sweep_drive_wsl.zsh`:每個 `actions/wsl` 檔(至 2026-10-22 共 134 個)寫一列到
  `matrix_coverage/results.csv2`,為 `wsl,gtk4`;showtime 是檔案中的 sleep 總和加 5 秒(至少 10 秒),`# expect:` 行
  判定為 met / UNMET / UNCHECKED。
- `test_support/measure/measure_wsl.zsh`:以 AT-SPI 取得元素中心點的視窗座標，即 WSL 動作檔列要填的數字。它不加
  `GTK_CSD`;重放會自行加上 header bar 的位移。它會先關掉正在執行的實例：第二個 GTK 實例會把工作交給第一個並以 0 結束。

## 限制

- 發行版名稱 `Ubuntu` 與路徑 `/home/<user>/...` 寫死在腳本中。
- Windows 桌面鎖定時，輸入仍會經 X11 重放，但 Windows Graphics Capture 擷取 WSLg 視窗並不可靠；以 log 行為證據，
  或在解鎖後重跑(results.csv2,2026-10-20 的列)。
- 在 WSL 內執行一支自己會呼叫 `wsl.exe` 的個別測試腳本，會經 interop 繞出去再回來;test_P26.zsh 現在會偵測自己已在
  WSL 內(2026-10-22 修正)。
