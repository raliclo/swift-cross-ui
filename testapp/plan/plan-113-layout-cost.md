# #113:版面成本是 n^1.5 嗎?在 AppKit 上不是,它是線性的

**狀態:已量測。P52 四條 arm,五個尺寸,每個數字都是 n=50 取最小值。**

**Status: measured. Four arms, five sizes, every number a min of n=50.**

Windows 端訂下的判準,原話:*「給 P52 加一條純 `Text` 的 arm,同樣形狀、同樣交錯、同樣取最小
值。曲線相同 → 成本在 stack 版面,按鈕只是附帶;曲線不同 → 在 `Button`」*,參考點是
*「48 顆按鈕時一次按壓約 **0.3 秒** 花在版面上」*。

那條 arm 已經加好(`P52Bench.text`,格子形狀與另外兩條完全相同,只是 `Text` 取代
`Button { Text }`),而尺寸從 12 掃到 192。

---

## 一、量測結果 / What was measured

單次按壓(狀態改變後的重排),已扣掉 control arm(0 格)的固定成本:

| 每 arm 格數 | 12 | 24 | 48 | 96 | 192 | 指數 (24→192) |
| --- | --- | --- | --- | --- | --- | --- |
| `primitive` 總計 µs | 3931 | 5769 | 10445 | 21020 | 42355 | **n^0.96** |
| — 每格 µs | 327.6 | 240.4 | 217.6 | 219.0 | 220.6 | |
| `custom` 總計 µs | 2929 | 4304 | 7825 | 14815 | 31868 | **n^0.96** |
| — 每格 µs | 244.1 | 179.3 | 163.0 | 154.3 | 166.0 | |
| `text` 總計 µs | 1309 | 1696 | 3165 | 6136 | 12159 | **n^0.95** |
| — 每格 µs | 109.1 | 70.7 | 65.9 | 63.9 | 63.3 | |

首次渲染(mount)同樣:`primitive` n^0.99、`custom` n^0.96、`text` n^0.91。

---

## 二、三個結論,依把握程度排序 / Three findings, most-certain first

### 1. 成本是線性的,不是 n^1.5 —— 在 AppKit 上、直到 192 格為止

**每格成本在五個尺寸間是平的**(220 / 165 / 64 µs),而那正是線性的樣子。若真是 n^1.5,
12 → 192 這 16 倍會讓每格成本變成 4 倍;實際上它沒有動。

指數 0.95–0.99 三條全部落在 1.0 附近,而不是 1.5。**這一項不需要靠比較兩條 arm,單獨一條就
足以推翻它**——這也是為什麼它排在最前面。

The per-cell cost is FLAT across a 16x range of n. That is what linear looks
like; n^1.5 would have quadrupled it. Not reproduced on AppKit up to 192 cells.

### 2. 曲線相同 —— 因此**成長**在 stack 版面

三條 arm 的指數在 0.95 至 0.96 之間,彼此無法區分。依 Windows 訂下的判準,這就是
「曲線相同」那一支:**隨格數成長的那一部分來自 stack 版面,而不是來自 `Button`**。

### 3. 但常數不是「附帶的」:`Button` 讓每格貴 3.5 倍

判準的後半句是「按鈕只是附帶」,而這一句**量測不支持**:

- `text` 每格 63.3 µs
- `primitive` 每格 220.6 µs — **3.48 倍**
- `custom` 每格 166.0 µs — **2.62 倍**

也就是說,一個 `Button` 每格比同形狀的 `Text` 多花約 **157 µs**,而那不隨 n 改變。
成長在版面,**但一個 192 格的畫面裡有 3/4 的時間花在按鈕本身**。要讓大量按鈕變快,兩邊都得動:
版面決定它怎麼隨 n 走,`Button` 決定那條直線有多陡。

The curves match, so the growth is in the stack layout. The constant does not:
a `Button` costs 3.5x a `Text` of the same shape, a fixed ~157 µs per cell that
does not move with n. Three quarters of the time in a 192-cell screen is the
button itself.

---

## 三、0.3 秒那個參考點在這裡沒有重現 / The 0.3 s reference does not reproduce here

48 顆按鈕時,`primitive` 一次按壓是 **min 10.5 ms、median 20.7 ms、max 41.0 ms**——比
0.3 秒少了一個數量級以上。

這不是說那個數字錯了,而是說**它不是 AppKit 上的數字**。若它量自 GTK 或 WinUI,那本身就是一
項發現:同一份版面程式碼在不同 backend 上差了 30 倍,而那會把「該優化版面」變成「該去看那個
backend 的 widget 建立成本」。**這是需要 Windows 端回答的一個問題,而不是我能從這台機器回答的。**

Measured at 48 on AppKit: 10.5 ms min, 20.7 ms median -- more than an order of
magnitude below the 0.3 s reference. If that figure came from GTK or WinUI then
the same layout code differs 30x between backends, which is itself the finding.
That is a question for the machine that produced the reference.

---

## 四、怎麼重跑 / How to re-derive

```sh
zsh testapp/compile.zsh P52
for n in 12 24 48 96 192; do
    ( SCUI_DEBUG_EVENTS_DIR=$PWD/testapp/debug-events ./testapp/output/P52 --debug --buttons=$n & )
    # 等日誌出現 "P52 results",約 20 至 30 秒
done
```

**不要用 `testapp/test.zsh` 跑這一支**:harness 會依 `--showtime` 把視窗留著,而 benchmark
本身只要 21 秒;先前一次 24 格的量測因此花了超過十分鐘,而那十分鐘全部是等待。

---

## 五、一個順帶修掉的缺陷 / A defect found on the way

`P52Bench` 有四個以 arm 索引的陣列寫死 `count: 3`(`lastSentinel`、`pressCPU`、`mountCPU`、
`misses`),而 `models` 上方的註解只說了 `models` 必須與 `armCount` 一致。第四條 arm 讓
`lastSentinel[3]` 在第一步跑起來之前就終結了行程。

**它的症狀不是崩潰訊息,是日誌停在 `CONFIG` 之後不再前進**——看起來與「benchmark 卡住了」
一模一樣,而我最初也是那樣讀它的,還去找了「視窗在背景被節流」這個並不存在的原因。四個陣列
現在都是 `count: armCount`,並在該處寫下這段症狀。

The symptom was not a crash message but a log that stopped after `CONFIG`,
indistinguishable from a stalled benchmark -- which is how I first read it.
