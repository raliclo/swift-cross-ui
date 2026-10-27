# Running one app on the simulator: test_ios.zsh

What `zsh testapp/test.zsh <Pn> --ios` does (it `exec`s
`testapp/test_ios.zsh`). Checked against test_ios.zsh on 2026-10-24.

## Steps

1. Validates the target against the tree: any `testapp/<name>.swift` is a
   target, so P15-DARK, P17-DOE and P6-v2 work (a `P<->` glob once rejected them).
2. Takes the iOS platform lock (see [simulator-sharing.md](simulator-sharing.md)).
3. Unless `-n`, rebuilds with `SCUI_DEBUG=1 compile.zsh -ios <Pn>`.
4. Copies `output/<Pn>-ios.app/<Pn>` into the reusable
   `testapp/.bundledApp/debugTarget.app` as `debugTarget`, with the template's
   Info.plist (`dev.swiftcrossui.testapp.debugTarget`), and ad-hoc signs it.
5. Boots the device (`simctl boot`, then `simctl bootstatus -b`).
6. Starts `simctl spawn <dev> log stream --style compact --predicate
   'process == "debugTarget"'` into `output/ios-<Pn>-debugTarget.log`.
7. Installs and launches: plain `simctl launch` without an action file, or the
   XCUITest runner with one ([action-file-replay.md](action-file-replay.md)).
8. Captures `<pn>-ios-1s-<stamp>.png` (only without the runner) and
   `<pn>-ios-final-<stamp>.png` after `--showtime` (default 30 s).

## Two bundle identities

`test_ios.zsh` always installs `dev.swiftcrossui.testapp.debugTarget`, so
repeated runs stay comparable and the simulator holds one test app.
`compile.zsh -ios` alone produces `dev.swiftcrossui.testapp.<Pn>`. Both are
current; they are different paths. Crash reports are therefore
`~/Library/Logs/DiagnosticReports/debugTarget-*.ips`.

## Quirks the script works around

- **Screenshots go through a temp file.** CoreSimulator does not write as the
  calling process: `simctl io screenshot` into a checkout under `/Volumes`
  fails with "Operation not permitted" while `/private/tmp` works. The script
  captures to `mktemp`, moves the file and `chmod 644`s it. A failed capture is
  counted and reported, never fatal.
- **Not `screenshot.zsh`.** That captures the Mac's display; `simctl io` gives
  the device framebuffer and needs no Screen Recording permission.
- **App stdout through a pty.** `simctl launch --stdout=<file>` loses the app's
  `print` output: to a file Swift's stdout is fully buffered and the buffer dies
  with the app (a `--debug` run kept eight swift-log lines and none of the
  app's). `--console-pty` is line-buffered; it stays attached until the app
  exits, so it runs in the background. Output: `output/<pn>-ios-stdout.log`
  (with an action file, `--stdout`, or a sleep-only file).
- **zsh names.** `local path=...` empties `$PATH` inside the function
  ("command not found: rm"); `status`, `options` and `watch` are special too.
- `SCUI_UPDATE_STATS=1` adds `--update-stats` and prints the app's last
  `update-stats:` line (only when stdout is kept); otherwise the run says
  `update-stats: off` rather than printing nothing.

## How to apply

- `zsh testapp/test.zsh P14 --ios`, `... --ios -n --showtime 5`,
  `... --ios --device "iPad Pro 11-inch (M5)"`.
- App arguments: after `--` on test_ios.zsh, or `TEST_APP_ARGS` through test.zsh.
- Interactive install of the last bundle: `testapp/manual_ios.zsh`.

---

# 在模擬器上執行一支 app:test_ios.zsh

`zsh testapp/test.zsh <Pn> --ios` 做的事(它以 `exec` 交給 `testapp/test_ios.zsh`)。
2026-10-24 對照 test_ios.zsh 確認。

## 步驟

1. 以樹本身驗證目標：任何 `testapp/<名稱>.swift` 都是目標，所以 P15-DARK、P17-DOE 與 P6-v2 都可以
   (曾經有個 `P<->` glob 拒絕它們)。
2. 取得 iOS 平台鎖(見 [simulator-sharing.md](simulator-sharing.md))。
3. 除非加 `-n`,以 `SCUI_DEBUG=1 compile.zsh -ios <Pn>` 重建。
4. 把 `output/<Pn>-ios.app/<Pn>` 以 `debugTarget` 之名複製進可重複使用的
   `testapp/.bundledApp/debugTarget.app`,配上範本的 Info.plist(`dev.swiftcrossui.testapp.debugTarget`),
   並以 ad-hoc 簽署。
5. 開機(`simctl boot`,再 `simctl bootstatus -b`)。
6. 啟動 `simctl spawn <裝置> log stream --style compact --predicate 'process == "debugTarget"'`,
   寫入 `output/ios-<Pn>-debugTarget.log`。
7. 安裝並啟動：沒有動作檔時用一般的 `simctl launch`,有動作檔時用 XCUITest runner
   ([action-file-replay.md](action-file-replay.md))。
8. 擷取 `<pn>-ios-1s-<時間戳>.png`(只在不用 runner 時)與 `--showtime`(預設 30 秒)之後的
   `<pn>-ios-final-<時間戳>.png`。

## 兩種 bundle 身分

`test_ios.zsh` 一律安裝 `dev.swiftcrossui.testapp.debugTarget`,讓重複執行保持可比較，模擬器中也只留
一支測試 app。單獨執行 `compile.zsh -ios` 產出的是 `dev.swiftcrossui.testapp.<Pn>`。兩者都是現行做法，
只是路徑不同。因此當機報告是 `~/Library/Logs/DiagnosticReports/debugTarget-*.ips`。

## 腳本繞過的怪癖

- **截圖經過暫存檔。** CoreSimulator 不是以呼叫者的身分寫檔:`simctl io screenshot` 寫進位於
  `/Volumes` 的 checkout 會以「Operation not permitted」失敗，寫到 `/private/tmp` 則可以。腳本先擷取到
  `mktemp`,再搬移並 `chmod 644`。擷取失敗會被計數與回報，但不會中止執行。
- **不用 `screenshot.zsh`。** 那擷取的是 Mac 的螢幕;`simctl io` 給的是裝置的 framebuffer,而且不需要
  螢幕錄製權限。
- **app 的 stdout 經由 pty。** `simctl launch --stdout=<檔案>` 會遺失 app 的 `print` 輸出：寫到檔案時
  Swift 的 stdout 是全緩衝，緩衝區隨 app 一起消失(一次 `--debug` 執行只留下八行 swift-log,app 自己的
  一行都沒有)。`--console-pty` 是行緩衝;它會一直附著到 app 結束，所以放在背景執行。輸出:
  `output/<pn>-ios-stdout.log`(有動作檔、`--stdout` 或只有 sleep 的檔案時)。
- **zsh 名稱。** `local path=...` 會在函式內清空 `$PATH`(「command not found: rm」);`status`、
  `options` 與 `watch` 也是特殊參數。
- `SCUI_UPDATE_STATS=1` 會加上 `--update-stats`,並印出 app 最後一行 `update-stats:`(只在保留 stdout 時);
  否則執行會印 `update-stats: off`,而不是什麼都不印。

## 怎麼用

- `zsh testapp/test.zsh P14 --ios`、`... --ios -n --showtime 5`、
  `... --ios --device "iPad Pro 11-inch (M5)"`。
- app 參數:test_ios.zsh 用 `--` 之後，經 test.zsh 則用 `TEST_APP_ARGS`。
- 互動式安裝上一次的 bundle:`testapp/manual_ios.zsh`。
