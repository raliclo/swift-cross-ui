# Performance numbers on the iOS simulator

Measured figures for UIKitBackend, all on the iPhone simulator unless stated.
Simulator numbers run on the Mac's CPU and GPU, not a phone's. Collected
2026-10-24 from completed.md, queue.md, results.csv2 and code comments.

## Frame clock

- `CADisplayLink` added in `.common` mode: in `.default` the clock stops while a
  scroll view tracks a finger.
- P64: 108 ticks in 1.78 s, 60.0 Hz, median gap 16.7 ms (2026-10-22). An earlier
  run read 58.9-59.8 Hz with a 22-43 ms worst gap.
- P96: 180 ticks in the first 3 s (2026-10-17). The first animation tick
  arrives about 0.1 s after the call.
- P72 stop-and-check: 3 frames drawn after the clock stops (AppKit 1, a
  free-running view about 90).

## View-graph updates (`SCUI_UPDATE_STATS=1`, 2026-10-05)

| | median | p95 | max |
|---|---|---|---|
| P66, iOS (n=231) | 1.1 ms | 4.0 ms | 16.2 ms |
| P66, macOS | 1.3 ms | 1.9 ms | 2.4 ms |
| P66, Android | 1.6 ms | 3.2 ms | 9.3 ms |

Median of per-app medians over 58 apps: iOS 10.8 ms, Android 17.0 ms. Table:
testapp/measurements/update-stats-20261005.md.

## The runner's cost

The XCUITest runner holds the app's main thread 0.8-0.9 s when it attaches; see
[self-running-apps.md](self-running-apps.md).

## Lists

- `setLazyRows` reloaded the whole table on every update: P57 built 29,718 rows.
  Refreshing rows in place when the count is unchanged brought it to 1,913
  (bca777db, 2026-10-04).
- Rows on demand (#117): 10,000 rows from 449 MB to 170 MB; 500 rows are also
  170 MB.
- On iOS the window is the screen, so "the window stops growing" proves nothing
  for a list viewport. Measure the table's frame against its content: with
  `-rows` 10/50/400/2000, frame.h 340/382/382/382 and content.h at 44 pt a row
  (2026-09-09).

## App size

A simulator `.app` is about 8.5-8.7 MB (47 apps); it has no Frameworks/ folder
and links the system `libswiftCore.dylib`. This is the simulator bundle, not an
`.ipa`. Source: testapp/todo/todo-mobile_app_size.md.

---

# iOS 模擬器上的效能數字

UIKitBackend 的實測數字，除另有說明外都在 iPhone 模擬器上量測。模擬器的數字跑在 Mac 的 CPU 與 GPU 上，不是手機的。
2026-10-24 從 completed.md、queue.md、results.csv2 與程式碼註解整理。

## Frame clock

- `CADisplayLink` 加在 `.common` 模式:在 `.default` 模式下，捲動 view 追蹤手指時 clock 會停止。
- P64:1.78 秒內 108 次 tick,60.0 Hz,間隔中位數 16.7 毫秒(2026-10-22)。較早的一次為 58.9–59.8 Hz,最差間隔 22–43 毫秒。
- P96:前 3 秒 180 次 tick(2026-10-17)。第一次動畫 tick 約在呼叫後 0.1 秒到達。
- P72 stop-and-check:clock 停止後畫了 3 幀(AppKit 1 幀，自行驅動的 view 約 90 幀)。

## view graph 更新(`SCUI_UPDATE_STATS=1`,2026-10-05)

| | 中位數 | p95 | 最大 |
|---|---|---|---|
| P66,iOS(n=231) | 1.1 毫秒 | 4.0 毫秒 | 16.2 毫秒 |
| P66,macOS | 1.3 毫秒 | 1.9 毫秒 | 2.4 毫秒 |
| P66,Android | 1.6 毫秒 | 3.2 毫秒 | 9.3 毫秒 |

58 支 app 各自中位數的中位數:iOS 10.8 毫秒,Android 17.0 毫秒。表格:testapp/measurements/update-stats-20261005.md。

## runner 的代價

XCUITest runner 附加時會佔住 app 主執行緒 0.8–0.9 秒;見 [self-running-apps.md](self-running-apps.md)。

## 清單

- `setLazyRows` 每次更新都重新載入整個表格:P57 建了 29,718 列。列數不變時就地更新列之後降到 1,913(bca777db,2026-10-04)。
- 隨需建列(#117):10,000 列從 449 MB 降到 170 MB;500 列也是 170 MB。
- iOS 上視窗就是螢幕，所以「視窗不再變大」對清單 viewport 什麼也證明不了。要量表格的框架與內容:`-rows` 為
  10/50/400/2000 時 frame.h 為 340/382/382/382,content.h 每列 44 點(2026-09-09)。

## app 大小

模擬器的 `.app` 約 8.5–8.7 MB(47 支 app);沒有 Frameworks/ 資料夾，連結的是系統的 `libswiftCore.dylib`。這是模擬器的
bundle,不是 `.ipa`。來源:testapp/todo/todo-mobile_app_size.md。
