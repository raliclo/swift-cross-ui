# Apps that run their own steps: the runner's cost and sleep-only files

The XCUITest runner disturbs timing measurements. Written 2026-10-24 from
test_ios.zsh and results.csv2 (ios, P104/P105, 2026-10-19; 18 files,
2026-10-22).

## What the runner costs

The runner attaches about 2 s after launch, and its accessibility snapshot
holds the app's main thread for most of a second (0.8-0.9 s, P104,
2026-10-19). An animation measured at that moment reads as lost frames:

| P105 removal (1 s animation) | frames | ends after the change |
|---|---|---|
| without the runner | 61 | 1.03 s |
| with the runner attached | 36-41 | 1.5-1.6 s |

P104's VALUE step read 4-22 pt of error with the default 0.6 s start, and
1.7-1.8 pt with `--steps-after 6`.

## How the harness handles it

- **Sleep-only files skip the runner.** An action file with only `sleep` rows
  (rows read through csv2) is run like `--stdout`: plain `simctl launch
  --console-pty`, stdout kept in `output/<pn>-ios-stdout.log`, showtime = the
  sum of its sleeps.
- **Its verdict is "still running".** With no runner there is no `replayed`
  line, and on 2026-10-22 all 18 sleep-only iOS files read as failures in a
  full sweep although each app had run its steps. Since 3f478ef4 test_ios.zsh
  asks the simulator's `launchctl list` for `UIKitApplication:<bundle id>[`:
  a PID means `-actionfile: replayed <file> (... sleep rows without the
  runner ...)`, `-` means `failed`.
- In that check, a `grep -q` in a pipeline under `pipefail` made the writer die
  of SIGPIPE and every running app read as gone; the output is stored in a
  variable first. `"$bundle_id["` also needs braces in zsh.
- Files that must press something and also measure take `# app-args:
  --steps-after 6`, so the app's own steps start after the runner has attached.
- `actions/ios/_watch-20s.actions` exists to keep stdout for 20 s without
  pressing anything.

## Limit

A run measured by the app itself is only trustworthy without the runner, or
after it has attached. The first run after a fresh build has been slower
(P106 PHASE skew 27.1 ms against 13.8-16.4 ms, 2026-10-19).

---

# 自行執行步驟的 app:runner 的代價與只有 sleep 的檔案

XCUITest runner 會干擾時間量測。2026-10-24 依 test_ios.zsh 與 results.csv2(ios,P104/P105,2026-10-19;
18 份檔案,2026-10-22)寫成。

## runner 的代價

runner 在啟動約 2 秒後附加，它擷取無障礙樹時會佔住 app 的主執行緒將近一秒(0.8–0.9 秒，P104,
2026-10-19)。當下量測的動畫會把它讀成掉幀:

| P105 移除(1 秒動畫) | 幀數 | 改變後結束於 |
|---|---|---|
| 沒有 runner | 61 | 1.03 秒 |
| runner 附加時 | 36–41 | 1.5–1.6 秒 |

P104 的 VALUE 步驟在預設 0.6 秒開始時誤差為 4–22 點，加上 `--steps-after 6` 後是 1.7–1.8 點。

## harness 如何處理

- **只有 sleep 的檔案不經 runner。** 只有 `sleep` 列的動作檔(各列以 csv2 讀取)以 `--stdout` 的方式執行:
  一般的 `simctl launch --console-pty`,stdout 保留在 `output/<pn>-ios-stdout.log`,showtime 為所有 sleep 的總和。
- **判定方式是「仍在執行」。** 沒有 runner 就沒有 `replayed` 那一行,2026-10-22 一次完整 sweep 中全部 18 份
  只有 sleep 的 iOS 檔案都被判為失敗，雖然每支 app 都跑完了自己的步驟。自 3f478ef4 起 test_ios.zsh 向模擬器的
  `launchctl list` 查詢 `UIKitApplication:<bundle id>[`:有 PID 就印 `-actionfile: replayed <檔案> (... sleep rows
  without the runner ...)`,是 `-` 就印 `failed`。
- 在這個檢查中,`pipefail` 之下管線裡的 `grep -q` 讓寫入端因 SIGPIPE 結束，每支執行中的 app 都被判為已結束;
  現在先把輸出存進變數。zsh 中 `"$bundle_id["` 也需要加大括號。
- 必須按東西又要量測的檔案加上 `# app-args: --steps-after 6`,讓 app 自己的步驟在 runner 附加之後才開始。
- `actions/ios/_watch-20s.actions` 用來在不按任何東西的情況下保留 20 秒的 stdout。

## 限制

由 app 自己量測的執行，只有在沒有 runner、或 runner 已附加之後才可信。全新建置後的第一次執行曾經較慢
(P106 PHASE 偏差 27.1 毫秒，其他為 13.8–16.4 毫秒,2026-10-19)。
