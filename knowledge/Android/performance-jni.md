# Android performance: where the time goes

Measured on the emulator, 2026-10-04 to 2026-10-24. How to profile is in
profiling.md; the density cache in density-cache.md; the swift-java lookup in
swift-java-fork.md.

## What

The cost on Android is JNI and Swift, not drawing. Every swift-java call looks
its Java method up by name (`GetMethodID`), and the debuggable test APKs also
run each call through CheckJNI. So the rule in AndroidBackend is: **do not call
Java when nothing changes, and do not read back from Java what Swift already
knows.**

## Fixes in place, with their measured effect

| Change | Commit | Before -> after |
|---|---|---|
| Text measurement cached by (style, proposal, text); one kept TextView measures new keys (it needs layout params, or `setText` throws in `checkForRelayout`) | 6b3b7a08 | measurement was 50.5% of P66's main thread |
| Text styles (three class lookups and a Typeface per call) cached | 6b3b7a08 | 19.6% |
| `setPosition` / `setSize` that change nothing skipped (94% / 96% of calls) | 6b3b7a08 | P66 16-22 -> 24-28 samples; P64 54-56 -> 57-58 Hz |
| `LastSet`: last text+style, position and size per widget kept in Swift, keyed weakly by the widget; positions forgotten when a container's children change | f6d3d96d | P66 24-28 -> 29-31 samples (iOS 31); P64 57-58 -> 59.0-59.5 Hz, worst gap 67-100 -> 33-50 ms |
| A button's Java action (`SwiftAction`/`SwiftObject`) built once, its Swift closure swapped per update; `CustomButton` constants read once | 301d49f1 | P2 picker update 92-98 -> 63-83 ms (25.5 ms had been class-loader lookups) |
| Display density cached, cleared on configuration change | e6023a81 | see density-cache.md |

## What the remaining time is

- **Steady state is at parity with iOS** (full sweeps with
  `SCUI_UPDATE_STATS=1`, testapp/measurements/update-stats-20261005.md):
  Android vs iOS median/p95, P64 2.5/3.8 vs 3.6/5.1 ms, P66 2.3/5.3 vs 1.0/1.9,
  P72 7.4/10.0 vs 5.3/6.1.
- **Slow updates are the ones that create views**, not the first after launch
  (P1's sheet 43-103 ms, P2's picker 92-98 ms; first updates 15-23 ms). A
  start-up warm-up or baseline profile is not supported by the numbers.
- **The first sheet open is generic metadata**: P1's 104 ms update had a
  57.9 ms stretch inside `swift_getGenericMetadata`; later opens in the same run
  took at most 21 ms. Warming it at launch would move the cost, not remove it.
- **First frame**: 0.5-0.7 s on a warm emulator (2026-10-24). On 2026-10-24 the
  main thread's first 5 s were libart 31%, libswiftCore 24%, libP96 10%,
  libhwui 0.4%.

## How to measure

- `SCUI_UPDATE_STATS=1` reaches the app as an argument; the app prints one
  cumulative line ending `first_ms=` and `rest_median_ms=` once updates have
  been quiet 1.5 s.
- Profile with `-e cpu-clock` (no hardware counters) plus `--trace-offcpu`;
  symbolize against the unstripped library. Gaps with no sample at all can be
  the emulator not running the vCPU.
- Compare on the same, warm emulator; see emulator-avds.md for state effects.

## Open

- swift-java still looks methods up by name on every call; caching method IDs
  is the reason for the fork (swift-java-fork.md). Package.resolved still pins the fork at e04c0ed6, stackotter's 0.5.1, so no caching has landed (2026-10-24).
- Not checked after 301d49f1: a button whose enabled state changes while the
  app runs.

---

# Android 效能：時間花在哪裡

2026-10-04 至 2026-10-24 在模擬器上量測。如何分析見 profiling.md;密度快取見 density-cache.md;swift-java 的查找見
swift-java-fork.md。

## 內容

Android 上的成本在 JNI 與 Swift,不在繪圖。swift-java 每次呼叫都以名稱查找 Java 方法(`GetMethodID`),而測試用的可除錯
APK 還讓每次呼叫經過 CheckJNI。所以 AndroidBackend 的原則是：**沒有變化就不呼叫 Java,Swift 已經知道的值就不從 Java 讀回來。**

## 已有的修正與量到的效果

| 改動 | Commit | 之前 → 之後 |
|---|---|---|
| 文字量測以(樣式、提議尺寸、文字)快取；保留一個 TextView 量新的鍵(它需要 layout params,否則 `setText` 在 `checkForRelayout` 拋出例外) | 6b3b7a08 | 量測原佔 P66 主執行緒 50.5% |
| 文字樣式(每次呼叫三次類別查找加一個 Typeface)快取 | 6b3b7a08 | 19.6% |
| 略過沒有改變任何東西的 `setPosition` / `setSize`(佔呼叫的 94% / 96%) | 6b3b7a08 | P66 16–22 → 24–28 個樣本;P64 54–56 → 57–58 Hz |
| `LastSet`:在 Swift 端保存每個 widget 最後的文字與樣式、位置、大小，以 widget 為弱參照鍵；容器子節點變動時忘掉位置 | f6d3d96d | P66 24–28 → 29–31 個樣本(iOS 31);P64 57–58 → 59.0–59.5 Hz,最差間隔 67–100 → 33–50 ms |
| 按鈕的 Java action(`SwiftAction`/`SwiftObject`)只建一次，每次更新換掉 Swift closure;`CustomButton` 的常數只讀一次 | 301d49f1 | P2 picker 更新 92–98 → 63–83 ms(其中 25.5 ms 原是 class loader 查找) |
| 顯示密度快取，設定變更時清除 | e6023a81 | 見 density-cache.md |

## 剩下的時間是什麼

- **穩定狀態與 iOS 相當**(以 `SCUI_UPDATE_STATS=1` 全面掃描,testapp/measurements/update-stats-20261005.md):Android 對 iOS
  的中位數/p95,P64 2.5/3.8 對 3.6/5.1 ms,P66 2.3/5.3 對 1.0/1.9,P72 7.4/10.0 對 5.3/6.1。
- **慢的是會建立 view 的更新**,不是啟動後的第一次(P1 的 sheet 43–103 ms、P2 的 picker 92–98 ms;第一次更新 15–23 ms)。
  數字不支持啟動暖機或 baseline profile。
- **第一次開 sheet 是 generic metadata**:P1 那次 104 ms 的更新中，有 57.9 ms 落在 `swift_getGenericMetadata` 裡；同一次執行
  之後再開最多 21 ms。在啟動時預熱只是搬移成本，不是消除。
- **第一幀**:暖機的模擬器上 0.5–0.7 秒(2026-10-24)。2026-10-24 主執行緒最初 5 秒:libart 31%、libswiftCore 24%、libP96 10%、
  libhwui 0.4%。

## 如何量測

- `SCUI_UPDATE_STATS=1` 以參數送進 app;更新靜止 1.5 秒後,app 印出一行累計結果，結尾是 `first_ms=` 與 `rest_median_ms=`。
- 分析時用 `-e cpu-clock`(沒有硬體計數器)加 `--trace-offcpu`;以未去符號的函式庫解析位址。完全沒有取樣的區段可能是模擬器沒有
  執行 vCPU。
- 在同一台、暖機的模擬器上比較；模擬器狀態的影響見 emulator-avds.md。

## 未解決

- swift-java 每次呼叫仍以名稱查找方法；快取方法 ID 正是 fork 的理由(swift-java-fork.md)。Package.resolved 仍把 fork 釘在 e04c0ed6,即 stackotter 的 0.5.1,所以快取尚未落地(2026-10-24)。
- 301d49f1 之後未檢查：執行中 enabled 狀態會改變的按鈕。
