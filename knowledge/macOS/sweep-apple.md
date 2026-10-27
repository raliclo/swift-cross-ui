# macOS: sweeping every action file (sweep_apple.zsh)

Written 2026-10-24 from testapp/sweep_apple.zsh, testapp/sweep-test/ and
matrix_coverage/results.csv2 (mac rows, 2026-09-27 to 2026-10-22).

## What

```sh
zsh testapp/sweep_apple.zsh --macos          # every file in actions/mac/, AppKitBackend
zsh testapp/sweep_apple.zsh --macos-gtk4     # the same files on GtkBackend (TEST_BACKEND=gtk4)
zsh testapp/sweep_apple.zsh --ios P57 P72    # iOS; app filter optional
```

One `test.zsh <app> --macos --showtime 2 --actionfile <file>` per action file,
one at a time, with a watchdog (`--timeout`, default 600 s; a hung run is
killed and recorded `timeout`). One row per file in
`output/<tag>-sweep.csv2` (`macos`, `macos-gtk4`, `ios`), written per file
through `test_support/csv2_rows.zsh`, with a `device` column (Mac model and chip
from sysctl). `SCUI_UPDATE_STATS=1` is exported and timings go to
`output/update-stats-<tag>.csv2`.

Action files: `testapp/actions/mac/`, 214 files on 2026-10-24, 82 of them
`-gtk4`. Extension `.actions` since 2026-10-14 (they were `.csv`).

## What a `pass` means

Replayed (`-actionfile: replayed <file>` in `output/<app>-actionfile.log`) AND a
`<app>-<tag>-final-*.png` newer than a marker touched before the run AND exit 0.
**It does not mean the file's assertions held**: a click on empty space is not
an error. A crash report `~/Library/Logs/DiagnosticReports/debugTarget-*.ips`
written during the run overrides everything and records `crash`.

## Rules built into it, each from a failure

- **App = longest prefix that names `testapp/<app>.swift`.** Cutting at the
  first dash replayed P15-DARK's and P17-DOE's files against P15 and P17 and
  counted them as passes (2026-09-27).
- **`-gtk4` files replace their base on the gtk4 sweep**, and are skipped on
  the AppKit sweep. GTK lays a window out taller, so AppKit coordinates miss.
- **Apps importing the WinUI products are skipped on gtk4** (P6; its GTK form
  is P6-v2). The 2026-10-16 sweep reported a failure for a build that cannot exist.
- **`# launch-args: ...`** in a file reaches the app through `TEST_APP_ARGS`,
  keeping `--debug` (P34 needs `-rows 500`; without it its buttons are no-ops).
- `-ipad` files are skipped on iOS (run by hand).
- test_common waits for the replay to end before the showtime, and stops
  waiting when the app has exited (GTK quits with its last window: P75 waited
  600 s on 2026-10-22).

## History worth keeping

- **A green sweep needs its captures read.** 2026-09-27: 81 of 81 pass. Reading
  every capture against its file on 2026-09-28 found many misses: y offsets of
  12-50 pt (P2, P3, P10, P11, P13, P16, P17, P30, P34, P49, P50), menus never
  reached (P19, P20), files ending on the launch state (P0, P4, P12, ...). All
  rewritten; second sweep 83 of 83 with captures read (results.csv2 mac, -,
  2026-09-28).
- 2026-10-14: 121 of 122. P6-transport-toggles fails capture because its stream
  folder `~/proj/LZFSE2/swift_tar/images` is absent on that Mac (queue item 16,
  open, handed to the M4).
- gtk4 sweep 2026-10-16: 112 files replayed, captured, exit 0 -- but checked
  against each file's stated end state only 50 had their effect; 39 clicks
  measured on AppKit landed beside the control on GTK's taller layout
  (`testapp/measurements/gtk4-aim-20261016.csv2`). With `-gtk4` files written,
  run 2: 98 ok, the rest re-aimed or fixed the same day
  (`gtk4-aim-20261016-run2.csv2`).

## Related scripts

- `testapp/sweep-test/sweep_drive_macos.zsh`: every built Pn launched without
  an action file, a row appended to results.csv2. Platform key `mac`, not
  `macos` (coverage.zsh's column is `mac/appkit`); renderer `default`, never
  `unrecorded`.
- `testapp/sweep-test/measure_macos.zsh P21`: builds with SCUI_DEBUG, launches,
  wakes the display (`caffeinate -u`), captures the window by id, to read
  coordinates for a new action file.

## Limits

- macOS runs can move the real pointer and raise windows. Do not use the Mac,
  and do not run the iOS sweep at the same time.

---

# macOS:掃過每一份動作檔(sweep_apple.zsh)

2026-10-24 依 testapp/sweep_apple.zsh、testapp/sweep-test/ 與 matrix_coverage/results.csv2(mac 列,2026-09-27 至
2026-10-22)寫成。

## 內容

每份動作檔一次 `test.zsh <app> --macos --showtime 2 --actionfile <檔>`,一次一個，有看門狗(`--timeout`,預設 600 秒;
卡住的執行被結束並記為 `timeout`)。每份檔案一列寫進 `output/<tag>-sweep.csv2`(`macos`、`macos-gtk4`、`ios`),經
`test_support/csv2_rows.zsh` 逐檔寫入，含 `device` 欄(sysctl 取得的 Mac 機型與晶片)。會 export `SCUI_UPDATE_STATS=1`,
耗時寫到 `output/update-stats-<tag>.csv2`。

動作檔在 `testapp/actions/mac/`,2026-10-24 共 214 份，其中 82 份是 `-gtk4`。自 2026-10-14 起副檔名為 `.actions`(原為 `.csv`)。

## `pass` 的意思

有重放(`output/<app>-actionfile.log` 裡的 `-actionfile: replayed <檔>`)、有一張比執行前標記檔新的
`<app>-<tag>-final-*.png`、結束碼 0。**不代表檔案的斷言成立**:點到空白處不算錯誤。執行期間寫出的崩潰報告
`~/Library/Logs/DiagnosticReports/debugTarget-*.ips` 凌駕一切，記為 `crash`。

## 內建的規則，各來自一次失敗

- **app = 能對應到 `testapp/<app>.swift` 的最長前綴。** 在第一個破折號切開，會把 P15-DARK 與 P17-DOE 的檔案拿去對 P15、P17
  重放並算成通過(2026-09-27)。
- **gtk4 sweep 以 `-gtk4` 檔取代原檔**,AppKit sweep 不跑它。GTK 的視窗排得較高,AppKit 量的座標會落空。
- **匯入 WinUI product 的 app 在 gtk4 sweep 略過**(P6;GTK 版是 P6-v2)。2026-10-16 曾為不可能存在的建置回報失敗。
- 檔案裡的 **`# launch-args: ...`** 經 `TEST_APP_ARGS` 送到 app,並保留 `--debug`(P34 需要 `-rows 500`,否則按鈕都是 no-op)。
- iOS 上略過 `-ipad` 檔(手動跑)。
- test_common 等重放結束才開始 showtime,app 已結束就不再等(GTK 在最後一個視窗關閉時結束:P75 在 2026-10-22 等滿 600 秒)。

## 值得留下的歷史

- **綠色的 sweep 要把擷圖讀過。** 2026-09-27:81 份全過。2026-09-28 逐張對照檔案讀擷圖，找到許多落空：y 偏差 12–50 pt
  (P2、P3、P10、P11、P13、P16、P17、P30、P34、P49、P50)、選單沒點到(P19、P20)、檔案結束在啟動狀態(P0、P4、P12 等)。
  全部重寫後第二輪 83 份全過，擷圖都讀過(results.csv2 mac、-、2026-09-28)。
- 2026-10-14:122 份中 121 份過。P6-transport-toggles 擷圖失敗，因為那台 Mac 上沒有它的串流資料夾
  `~/proj/LZFSE2/swift_tar/images`(queue 第 16 項，未結，交給 M4)。
- 2026-10-16 的 gtk4 sweep:112 份都有重放、擷圖、結束碼 0——但對照各檔所寫的結束狀態只有 50 份達成效果;39 個在 AppKit 量的
  點擊落在 GTK 較高版面的控制項旁邊(`testapp/measurements/gtk4-aim-20261016.csv2`)。寫好 `-gtk4` 檔後的第二輪:98 份 ok,
  其餘當天重新瞄準或修正(`gtk4-aim-20261016-run2.csv2`)。

## 相關腳本

- `testapp/sweep-test/sweep_drive_macos.zsh`:不帶動作檔啟動每支已建置的 Pn,在 results.csv2 加一列。平台鍵是 `mac` 不是
  `macos`(coverage.zsh 的欄是 `mac/appkit`);renderer 寫 `default`,絕不寫 `unrecorded`。
- `testapp/sweep-test/measure_macos.zsh P21`:以 SCUI_DEBUG 建置、啟動、喚醒顯示器(`caffeinate -u`)、依 id 擷取視窗，用來量新動作檔的座標。

## 限制

- macOS 的執行可能移動真實指標並把視窗帶到前景。執行期間不要使用這台 Mac,也不要同時跑 iOS sweep。
