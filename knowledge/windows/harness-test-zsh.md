# The harness on Windows: test.zsh

Written 2026-10-24 from testapp/test.zsh, testapp/test_support/test_common.zsh
(`run_windows`), testapp/ui-lock.zsh, testapp/enable_input.zsh, commits 6d1b7fab,
daaea4ae, b76c6818, 500a69ca, and results.csv2 (windows rows of 2026-10-19 to
2026-10-23).

## Shape of a run

- Windows is detected by `uname -s` matching `MINGW*|MSYS*|CYGWIN*`. On a Windows
  host the targets are `windows`, `wsl` and `both`. Most `test_Pn.zsh` declare
  `TEST_TARGET="both"`, so a plain `test.zsh Pn` runs WSL and then Windows;
  **pass `-win`** for Windows only.
- `TEST_BACKEND=gtk4` or `WinUI` picks the exe. When both `Pn-WinUI.exe` and
  `Pn-gtk4.exe` exist and it is unset, test.zsh refuses to guess.
- **Before b76c6818 (2026-10-21) test.zsh rebuilt only the WinUI exe**, so a
  `TEST_BACKEND=gtk4` run launched a stale `Pn-gtk4.exe`. P105 and P109
  "differences" in the Mac's deck review were that stale exe (7ac50f7a). A
  result from a gtk4 run before that date may be from an old binary.
- Typical: `TEST_BACKEND=gtk4 TEST_GPU=default zsh testapp/test.zsh P92 -win
  --no-build --showtime 10`.

## What happens, in order

1. `enable_input.zsh --check` (exit 0 clear, 3 blocker, 4 remote-desktop host).
   Known blockers are stopped (one UAC prompt through `enable_input.ps1`); if one
   survives the run stops with exit 5. A remote-desktop host only warns.
2. `ui-lock.zsh acquire test-<app>` (skip with `SCUI_NO_UI_LOCK=1`), released on
   EXIT, ZERR, INT and TERM.
3. Every `Pn.exe`, `Pn-WinUI.exe` and `Pn-gtk4.exe` is killed: a leftover window
   of the other backend with the same title was once captured instead.
4. Build through compile.zsh (`-gtk4` for gtk4). A failed build aborts.
5. `winmin.exe --clear` minimises every titled window, so nothing covers the app.
6. For `-gtk4` with `-render hw` (default) the exe gets `GpuPreference=2;` for
   the run; `TEST_GPU=default` leaves the GPU alone.
7. Launch detached; paths handed to the exe go through `cygpath -m`; output to
   `<app>-actionfile.log`.
8. Captures: `-1s`, the render marker, `--showtime`, then `-final`. After
   showtime it waits up to `TEST_REPLAY_GRACE_SECONDS` (120) for the log's
   `-actionfile: replayed|failed`. Teardown `taskkill /F /IM` and the GPU
   preference restored.

Exit codes: 6 replay unfinished or failed, 7 every capture failed (a locked or
blank desktop gives black captures and rc 7), 64 ambiguous action file, 66
missing action file.

## ui-lock

An mkdir lock in `testapp/.ui-lock` that one desktop user (person or script)
holds at a time. A killed `acquire` waiter used to leave the lock held by nobody;
since 2026-10-22 a dead holder is reclaimed at once. Scripts should use
`acquire <holder> --no-wait`. A "status 5" replay writes `.ui-lock-denied`, which
makes the next acquire wait (300 s).

## Open (2026-10-24)

- `test.zsh:326` tests `case " $* "` for `--wsl`/`--both` after the parse loop
  has shifted every argument away, so `check_wsl_host.zsh` never runs. It should
  test `forward_args` (added in 46b6d83e, not verified).
  **Fixed in a92edee1 and verified 2026-10-29**: with a throwaway
  `test_support/test_P999.zsh` and `TEST_WSL_DISTRO=NoSuch`, `--wsl` and
  `--both` printed the "no WSL distribution named NoSuch" warning and still ran
  the test; `--windows` did not run the check.
- `helper/bin/winmin.exe` has no build step; when missing, test.zsh only prints
  "NOT minimised". **Fixed 2026-10-29**: `clear_desktop_windows` in
  test_common.zsh builds it with `swiftc -O testapp/winmin.swift` (about 9 s)
  when it is missing or older than its source; helper/bin had no winmin.exe at all.

See also [harness-wincap.md](harness-wincap.md),
[harness-input-injection.md](harness-input-injection.md),
[action-files.md](action-files.md).

---

# Windows 上的測試工具:test.zsh

2026-10-24 依 testapp/test.zsh、testapp/test_support/test_common.zsh(`run_windows`)、testapp/ui-lock.zsh、
testapp/enable_input.zsh、6d1b7fab、daaea4ae、b76c6818、500a69ca,以及 results.csv2(2026-10-19 至 2026-10-23 的
windows 列)寫成。

## 一次執行的樣貌

- 以 `uname -s` 符合 `MINGW*|MSYS*|CYGWIN*` 判定 Windows。在 Windows 主機上，目標有 `windows`、`wsl` 與 `both`。
  多數 `test_Pn.zsh` 宣告 `TEST_TARGET="both"`,所以單純的 `test.zsh Pn` 會先跑 WSL 再跑 Windows;**只跑 Windows
  請加 `-win`**。
- `TEST_BACKEND=gtk4` 或 `WinUI` 決定用哪個 exe。`Pn-WinUI.exe` 與 `Pn-gtk4.exe` 都存在而未設定時,test.zsh 拒絕
  猜測。
- **b76c6818(2026-10-21)之前,test.zsh 只重建 WinUI 的 exe**,所以 `TEST_BACKEND=gtk4` 的執行跑的是過期的
  `Pn-gtk4.exe`。Mac 端簡報審查中 P105 與 P109 的「差異」就是這個過期 exe(7ac50f7a)。該日期之前的 gtk4 結果可能
  出自舊 binary。
- 典型用法:`TEST_BACKEND=gtk4 TEST_GPU=default zsh testapp/test.zsh P92 -win --no-build --showtime 10`。

## 依序發生的事

1. `enable_input.zsh --check`(0 正常、3 有阻擋程式、4 有遠端桌面主機)。已知的阻擋程式會被停止(透過
   `enable_input.ps1` 一次 UAC 提示);仍有存活時以 exit 5 停止。遠端桌面主機只警告。
2. `ui-lock.zsh acquire test-<app>`(`SCUI_NO_UI_LOCK=1` 略過),在 EXIT、ZERR、INT 與 TERM 時釋放。
3. kill 所有 `Pn.exe`、`Pn-WinUI.exe` 與 `Pn-gtk4.exe`:曾有另一個 backend 留下、標題相同的視窗被誤擷取。
4. 經 compile.zsh 建置(gtk4 加 `-gtk4`)。建置失敗即中止。
5. `winmin.exe --clear` 把所有有標題的視窗最小化，讓沒有東西蓋住 app。
6. `-gtk4` 在 `-render hw`(預設)下，執行期間 exe 拿到 `GpuPreference=2;`;`TEST_GPU=default` 不動 GPU。
7. 分離啟動；交給 exe 的路徑經 `cygpath -m`;輸出寫到 `<app>-actionfile.log`。
8. 擷取:`-1s`、算繪標記、`--showtime`,然後 `-final`。showtime 之後最多等 `TEST_REPLAY_GRACE_SECONDS`(120)
   直到 log 出現 `-actionfile: replayed|failed`。收尾為 `taskkill /F /IM` 並還原 GPU 偏好。

結束碼:6 重放未完成或失敗,7 所有擷取都失敗(鎖定或黑屏的桌面得到全黑擷取與 rc 7),64 動作檔不明確,66 找不到
動作檔。

## ui-lock

`testapp/.ui-lock` 的 mkdir 鎖，同一時間只讓一個桌面使用者(人或腳本)持有。被中止的 `acquire` 等待者曾留下無人
持有的鎖；自 2026-10-22 起已死的持有者會立即被回收。腳本應使用 `acquire <holder> --no-wait`。出現「status 5」的
重放會寫入 `.ui-lock-denied`,讓下一次 acquire 等待(300 秒)。

## 未解決(2026-10-24)

- `test.zsh:326` 在解析迴圈已把所有引數 shift 掉之後，才以 `case " $* "` 檢查 `--wsl`/`--both`,所以
  `check_wsl_host.zsh` 從未執行。應改查 `forward_args`(46b6d83e 加入，未驗證)。
  **a92edee1 已修正，2026-10-29 驗證**:以暫時的 `test_support/test_P999.zsh` 加 `TEST_WSL_DISTRO=NoSuch`,`--wsl`
  與 `--both` 都印出「no WSL distribution named NoSuch」警告且照常執行測試;`--windows` 不執行此檢查。
- `helper/bin/winmin.exe` 沒有建置步驟；不存在時 test.zsh 只印出「NOT minimised」。**2026-10-29 已修正**:test_common.zsh 的 `clear_desktop_windows` 在它不存在或比原始碼舊時，以 `swiftc -O testapp/winmin.swift` 建置(約 9 秒);當時 helper/bin 裡根本沒有 winmin.exe。

另見 [harness-wincap.md](harness-wincap.md)、[harness-input-injection.md](harness-input-injection.md)、
[action-files.md](action-files.md)。
