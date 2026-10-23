# AndroidBackend: the display density is cached

Written 2026-10-24 from the P96 investigation (matrix_coverage/results.csv2:
android, P96, 2026-10-24).

## What changed

`AndroidBackend.density { view.getResources().getDisplayMetrics().density }`
(Sources/AndroidBackend/AndroidBackend+Density.swift) runs the closure once and
returns the stored value after that. `configurationDidChange` clears it, so the
next read after a configuration change goes back to JNI. Twenty call sites in
AndroidBackend read the density this way: widget position, size, natural size,
corner radius, geometric and visual effects, paths, lists, tables, sheets, text
fields, scroll offsets, and the window scale factor.

## Why

Each read was three JNI calls: `getResources`, `getDisplayMetrics` and the
`density` field. swift-java looks every method up by name (`GetMethodID`) on
every call, and the debuggable APKs the tests install also run each call
through CheckJNI. `setPosition` and `setSize` read the density for every
widget on every layout, so a first layout of many widgets read it hundreds of
times.

## How it was found

On the api36b emulator, P96 (33 curve tiles) read `back.out peak 0.0000
distinct 1` for its first two driven tweens when captured at rest. The checks:

- Reordering the tweens: the first two failed whichever they were, so the
  curves were not at fault.
- `Sources/SwiftCrossUI` and `Sources/AndroidBackend` at db561114 failed the
  same way, and so did 46791ed9's animation files reverted. It is not a
  regression.
- logcat: after RENDER COMPLETE, Choreographer "Skipped 128 frames" then 36,
  Displayed +4.9 s. P96's own 0.5 s check logged 2.7 s late, after one tick.
  The tweens start at `onAppear`, so their first 1.1 s windows passed with no
  frame.

simpleperf (`record -a -e cpu-clock -g --duration 5` from launch, report
`--tids <main thread>`): the main thread's time was in libart 31%,
libswiftCore 24%, libP96 10%, libhwui 0.4%. The time was JNI and Swift, not
drawing. `GetMethodID` was 6.2%, and `View.getResources()` was high in the
call tree.

## Measured effect

Same emulator, same 5 s window from launch:

| | before | after |
|---|---|---|
| main-thread CPU | 1.44 s | 1.27 s |
| `GetMethodID` share | 6.2% | 3.1% |
| at-rest runs with a Choreographer skip | 2 of 5 (32-45 frames) | 0 of 4 |
| `back.out` distinct values | 24 | 31-35 |

P12 and P23 lay out at rest exactly as the iOS and Android Pairs deck
captures.

## Limits

- One density for the whole process. A window on a second display with a
  different density would read the first display's value until the next
  configuration change. Nothing here opens one.
- The 2.7 s stall of 2026-10-23 23:46-00:01 did not come back on a fresh
  emulator, nor with 19 apps in the background. With or without the cache,
  only the 0.5-0.7 s first-frame cost was seen afterwards.
- The larger cost is still in swift-java: the by-name lookup on every call.
  That is why swift-java now comes from raliclo/swift-java, branch develop
  (76c8029a).

---

# AndroidBackend:顯示密度改為快取

2026-10-24 依 P96 的調查寫成(matrix_coverage/results.csv2:android、P96、2026-10-24)。

## 改了什麼

`AndroidBackend.density { view.getResources().getDisplayMetrics().density }`
(Sources/AndroidBackend/AndroidBackend+Density.swift)只執行一次閉包，之後回傳保留的值。`configurationDidChange`
會清掉它，所以設定變更後的下一次讀取會再走 JNI。AndroidBackend 有 20 處用這種方式讀取密度：widget 的位置、
大小、自然大小、圓角、幾何與視覺效果、路徑、清單、表格、sheet、文字欄位、捲動位移，以及視窗縮放比例。

## 為什麼

每次讀取原本是三個 JNI 呼叫:`getResources`、`getDisplayMetrics` 與 `density` 欄位。swift-java 每次呼叫都以名稱
查找方法(`GetMethodID`),而測試安裝的可除錯 APK 還要讓每個呼叫經過 CheckJNI。`setPosition` 與 `setSize`
每次排版都會為每個 widget 讀取密度，所以許多 widget 的第一次排版要讀上數百次。

## 怎麼找到的

在 api36b 模擬器上靜止擷取時,P96(33 張曲線圖)前兩個 driven 補間讀到 `back.out peak 0.0000 distinct 1`。
檢查過程:

- 對調補間順序：失敗的總是排在前面的兩個，所以不是曲線的問題。
- `Sources/SwiftCrossUI` 與 `Sources/AndroidBackend` 換回 db561114 一樣失敗，換回 46791ed9 之前的動畫檔案也一樣。
  不是退化。
- logcat:RENDER COMPLETE 之後，Choreographer 先跳過 128 幀、再跳過 36 幀，畫面在 +4.9 秒才顯示。P96 自己的
  0.5 秒檢查晚了 2.7 秒才記錄，那時只收到 1 次 tick。補間從 `onAppear` 開始，所以最初的 1.1 秒計時窗沒有任何一幀。

simpleperf(從啟動起 `record -a -e cpu-clock -g --duration 5`,以 `--tids <主執行緒>` 出報告):主執行緒的時間花在
libart 31%、libswiftCore 24%、libP96 10%、libhwui 0.4%。時間是花在 JNI 與 Swift,不是畫圖。`GetMethodID` 佔
6.2%,`View.getResources()` 在呼叫樹裡排得很高。

## 量到的效果

同一台模擬器，同樣從啟動起的 5 秒:

| | 之前 | 之後 |
|---|---|---|
| 主執行緒 CPU | 1.44 秒 | 1.27 秒 |
| `GetMethodID` 比例 | 6.2% | 3.1% |
| 有跳幀的靜止執行 | 5 次中 2 次(32–45 幀) | 4 次中 0 次 |
| `back.out` 相異值 | 24 | 31–35 |

P12 與 P23 的靜止版面與 iOS and Android Pairs 簡報的擷圖完全一致。

## 限制

- 整個程序只有一個密度。若有視窗開在密度不同的第二個螢幕上，在下一次設定變更前會讀到第一個螢幕的值。
  這裡沒有任何東西會開這種視窗。
- 2026-10-23 23:46–00:01 那段 2.7 秒的卡頓，在重開的模擬器上、在背景有 19 個 app 時都沒有再出現。之後不論
  有沒有快取，都只見到 0.5–0.7 秒的第一幀成本。
- 較大的成本仍在 swift-java:每次呼叫都以名稱查找。這正是 swift-java 現在改從 raliclo/swift-java 的 develop
  分支取得的原因(76c8029a)。
