# Sweeping every iOS action file: sweep_apple.zsh --ios

How the whole iOS set is driven and what its `pass` means. Checked against
sweep_apple.zsh and results.csv2 on 2026-10-24.

## What it does

`zsh testapp/sweep_apple.zsh --ios [Pn ...] [--timeout s]` runs every
`actions/ios/*.actions` one at a time through
`TEST_APP_ARGS="--debug ..." test.zsh <app> --ios --showtime 2 --actionfile <f>`,
with `SCUI_UPDATE_STATS=1`, and writes one row per FILE (not per app) to
`output/ios-sweep.csv2` through csv2 (`test_support/csv2_rows.zsh`), plus
`output/update-stats-ios.csv2`. Each run has a watchdog (default 600 s,
recorded as `timeout`).

## What `pass` means

All three, each read from what the run produced:

- **replay**: the runner's `-actionfile: replayed <file>` line (or the
  sleep-only "still running" line, [self-running-apps.md](self-running-apps.md));
- **capture**: a `<app>-ios-final-*.png` newer than a marker touched before the
  run;
- **exit**: test.zsh's status.

A crash report `~/Library/Logs/DiagnosticReports/debugTarget-*.ips` newer than
the marker overrides everything as `crash`, because on iOS the runner reports
`replayed` and exit 0 even when the app died (P73, 2026-09-27).

It does NOT mean the file's assertions held; a person reads the capture and
the app's stdout against the file header.

## Details that matter

- **The app is the longest prefix naming an app**, not the text before the first
  dash: cutting at the dash replayed `P15-DARK-*` files against P15 and counted
  them as passes (2026-09-27).
- `*-ipad.actions` files are skipped: the sweep runs on the iPhone, which has one
  window (P59-two-windows-ipad failed there, 2026-10-03). They are run by hand
  with `--device`.
- Since 2026-10-22 each row records the device from `simctl list devices -j`,
  e.g. `swift-cross-ui (iPhone 17 Pro Max, iOS 27.0)`.
- Do not run a macOS sweep at the same time: the Simulator window can end up
  over a macOS test app.
- `output/ios-sweep.csv2` is rewritten by each invocation; the durable record is
  matrix_coverage/results.csv2.

## Latest full result

2026-10-22, after 87c61a0e: 127 files on the iPhone 17 Pro Max simulator, 109
replayed with a capture in the full sweep and the 18 sleep-only files passing
on re-run after 3f478ef4. Per-file time median 33 s, longest 192 s, about 67
minutes for the 109. Eight iPad files (P5, P14, P50, P59, P62, P71, P72, P75) were run by hand the same day, all
passing (P75 after a fix; see [ipad.md](ipad.md)).

## A third layer: did anything change?

`zsh testapp/verify_effect_ios.zsh [Pn ...]` replays each app twice through the
runner, once with `actions/ios/_control-no-actions.actions` (presses nothing)
and once with the real file, and compares the final captures into
`output/ios-effect.csv2`. The control is a no-op FILE, not a plain launch, so
both runs take the same launch path. A full pass rewrites the CSV; naming apps
appends (an Android verifier that truncated on every call once left 1 row of
46).

---

# 掃過每一份 iOS 動作檔:sweep_apple.zsh --ios

整組 iOS 檔案如何被驅動，以及它的 `pass` 代表什麼。2026-10-24 對照 sweep_apple.zsh 與 results.csv2 確認。

## 它做什麼

`zsh testapp/sweep_apple.zsh --ios [Pn ...] [--timeout 秒]` 逐一以
`TEST_APP_ARGS="--debug ..." test.zsh <app> --ios --showtime 2 --actionfile <檔案>` 執行每份
`actions/ios/*.actions`,設定 `SCUI_UPDATE_STATS=1`,並經 csv2(`test_support/csv2_rows.zsh`)以每份**檔案**
(不是每支 app)一列寫入 `output/ios-sweep.csv2`,另寫 `output/update-stats-ios.csv2`。每次執行都有看門狗
(預設 600 秒，記為 `timeout`)。

## `pass` 代表什麼

三者皆成立，每一項都讀自那次執行產出的東西:

- **replay**:runner 的 `-actionfile: replayed <檔案>` 那一行(或只有 sleep 的檔案「仍在執行」那一行，見
  [self-running-apps.md](self-running-apps.md));
- **capture**:比執行前 touch 的標記檔還新的 `<app>-ios-final-*.png`;
- **exit**:test.zsh 的結束碼。

比標記檔新的當機報告 `~/Library/Logs/DiagnosticReports/debugTarget-*.ips` 會蓋過一切，記為 `crash`,因為在 iOS 上
即使 app 已經結束,runner 仍回報 `replayed` 與結束碼 0(P73,2026-09-27)。

它**不**代表檔案的斷言成立;要由人對照檔案標頭去讀擷圖與 app 的 stdout。

## 重要細節

- **檔案所屬的 app 是能對應到某支 app 的最長前綴**,不是第一個破折號之前的文字：在破折號處切開會把
  `P15-DARK-*` 檔案拿去對 P15 重放並算成通過(2026-09-27)。
- `*-ipad.actions` 會被略過:sweep 在只有一個視窗的 iPhone 上跑(P59-two-windows-ipad 在那裡失敗,2026-10-03)。
  它們以 `--device` 手動執行。
- 自 2026-10-22 起每列都記錄取自 `simctl list devices -j` 的裝置，例如
  `swift-cross-ui (iPhone 17 Pro Max, iOS 27.0)`。
- 不要同時跑 macOS sweep:模擬器視窗可能蓋在 macOS 測試 app 上。
- 每次執行都會改寫 `output/ios-sweep.csv2`;長期紀錄在 matrix_coverage/results.csv2。

## 最近的完整結果

2026-10-22,87c61a0e 之後：在 iPhone 17 Pro Max 模擬器上 127 份檔案，完整 sweep 中 109 份重放並有擷圖，
18 份只有 sleep 的檔案在 3f478ef4 之後重跑通過。每份檔案時間中位數 33 秒、最長 192 秒,109 份約 67 分鐘。
八份 iPad 檔案(P5、P14、P50、P59、P62、P71、P72、P75)同日手動執行，全部通過(P75 在修正之後，見 [ipad.md](ipad.md))。

## 第三層：是否真的改變了什麼?

`zsh testapp/verify_effect_ios.zsh [Pn ...]` 讓每支 app 經 runner 重放兩次：一次用
`actions/ios/_control-no-actions.actions`(什麼都不按),一次用真正的檔案，比較兩張最後擷圖，寫入
`output/ios-effect.csv2`。對照組是不做事的**檔案**而不是一般啟動，讓兩次走同一條啟動路徑。完整執行會改寫 CSV;
指定 app 時則附加(曾有一個 Android 驗證器每次呼叫都清空檔案，結果 46 列只剩 1 列)。
