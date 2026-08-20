# GTK test plan findings

What the UI test plan reports when its steps are actually executed on
Linux/GtkBackend under XWayland, driven with `drive_xdotool.zsh`. Collected
2026-08-20.

Kept separate from the coverage matrix because the matrix answers "is this
covered" and this answers "what did it say". A row saying ✅ and a defect found
by step 5 of that same app are both true.

當 UI 測試計畫的步驟真正在 Linux/GtkBackend（XWayland，以 `drive_xdotool.zsh` 驅動）上被執行時，
它所回報的內容。蒐集於 2026-08-20。

與 coverage matrix 分開存放，因為 matrix 回答的是「是否已涵蓋」，本文件回答的是「它說了什麼」。
某一列標示 ✅，與該 app 第 5 步發現的缺陷，兩者可以同時為真。

## Why this document exists

Every app opens a window on both platforms. That was reported as "all 26 pass"
and it is worth being precise about what it meant: the plan carries about 190
numbered steps, roughly 25 have now been run, and those 25 found four defects.
Watching a window appear finds none of them.

本文件存在的理由：每一支 app 在兩個平台上都能開啟視窗。該結果曾被回報為「26 支全數通過」，而這
句話的確切含義值得說清楚：計畫共約 190 個編號步驟，目前已執行約 25 個，而這 25 個步驟找出了
四項缺陷。單看視窗是否出現，一項也找不到。

## Layout defects, and why they look like one problem

Three container types each mis-size their children, in three different apps.
They are listed separately because they were found separately, but they should
be investigated together: fixing them one at a time risks trading one for
another, and the shapes rhyme.

三種容器型別各自把子元件的尺寸算錯，分別出現在三支不同的 app 中。此處分列，是因為它們是分別被
發現的；但應合併調查：逐一修正有以彼換此的風險，而且它們的形態相似。

### ZStack does not overlap — #158, P13 step 5

The plan requires the children of a `Group` inside a `ZStack` to overlap on the
z axis. They stack vertically instead: the red, green and blue rectangles appear
one below another with no overlap at all.

Reproduces. This is the clearest of the three because the intended behaviour is
unambiguous.

計畫要求 `ZStack` 內 `Group` 的子元件在 z 軸上重疊。實際卻是垂直堆疊：紅、綠、藍三個矩形上下排列，
完全沒有任何重疊。

重現。三者中最明確的一項，因為其預期行為毫無歧義。

### VStack bands not equal width — #266b, P17 step 8

Three coloured bands of different natural widths, given a fixed height, are
required to end up the same width. They do not.

Reproduces.

三條自然寬度不同的色帶，在被賦予固定高度後，應最終等寬。實際並非如此。

重現。

### HStack squeezes its first child — P21 step 3

The `.switch` row renders its "Enabled" label as `...` and the `.checkbox` row
as `En...`, while the "Disabled" toggle beside each renders in full.

Two explanations are eliminated by measurement and should not be re-derived:

- Not a space shortage. The row occupies about 220px of an 820px window.
- Not the toggle spacer. `Toggle(.switch)` inserts a `Spacer()` only when
  `backend.requiresToggleSwitchSpacer` is true, and GtkBackend sets it false --
  only UIKitBackend sets it true.

What remains is width distribution across nested HStacks: `Toggle(.switch)` is
itself an `HStack` of `Text` plus `ToggleSwitch`, and P21 puts two of those
inside an outer `HStack`. The first inner stack's `Text` is the one squeezed.

`.switch` 那列的「Enabled」標籤顯示為 `...`，`.checkbox` 那列顯示為 `En...`，而其旁的「Disabled」
則完整呈現。

有兩種解釋已由量測排除，不應重新推導：非空間不足（該列僅佔 820px 視窗中的約 220px）；亦非 toggle
的 spacer（`Toggle(.switch)` 僅在 `backend.requiresToggleSwitchSpacer` 為真時插入 `Spacer()`，而
GtkBackend 設為 false，僅 UIKitBackend 為真）。

剩下的是巢狀 HStack 之間的寬度分配：`Toggle(.switch)` 本身即為 `Text` 加 `ToggleSwitch` 的
`HStack`，而 P21 又把兩個這樣的結構放進外層 `HStack`；被擠壓的正是第一個內層堆疊中的 `Text`。

## Instrumentation defect

### P22 reports two sizes per sample

Each of the eight font samples reports two different measurements, one sensible
and one not:

```
11 caption:  185 x 13     plausible for 11pt text
11 caption:   15 x 397     a vertical strip
17 body:     264 x 20     plausible
17 body:      23 x 555     the same wrong shape
```

The rendering is correct -- the size ladder, the wrapping and the three
alignment rows all look right. But P22 exists to compare reported widths rather
than appearance, and two contradictory numbers per sample leave nothing to
compare. The measuring overlay is being asked for a size under a second,
degenerate proposal and records both.

八個字型樣本各回報兩組不同的量測值，其一合理、其一不合理（如上）。

繪製本身是正確的——字級階梯、換行與三列對齊看起來都無誤。但 P22 的存在目的是比較「回報的寬度」
而非外觀，而每個樣本兩個互相矛盾的數字，等於沒有東西可比。量測用的 overlay 在第二次、退化的尺寸
提議下被詢問，並將兩者都記錄了下來。

## Checks that pass

Worth recording, because "no defect found" is only useful if it is written down
somewhere -- otherwise the same check gets run again.

值得記錄，因為「未發現缺陷」唯有被寫下來才有價值——否則同一項檢查會被反覆執行。

| check | app | result |
|---|---|---|
| #264 ideal width reaching `fixedSize` | P17 | does not reproduce; subject 160x16 against control 372x16 |
| #595 text clipping in a ScrollView | P13 | does not reproduce; plain and `.fixedSize()` both show all three lines |
| disabled button refuses input | P21 | `clicks` reads 1 after Enabled then Disabled |
| toggle styles flip, disabled twins do not | P21 | plain, `.switch` and `.button` all correct |
| flat menu opens, selects and closes | P19 | all four item kinds render, selection registers, menu closes |
| nested menu reaches level 2, level 3 available | P20 | GTK slides with a back chevron rather than cascading |
| navigation stack pushes | P24 | Level 0 to Level 2, button becomes Push level 3 |
| table renders | P23 | four columns, eight rows; long cell truncates rather than widening its column |
| text ladder, wrapping and alignment render | P22 | correct |

## Characterised, not a defect

### Picker sized from the selected item — #161, P17 step 4

The picker's width follows the selection: 42, 51, 154, 392 as longer items are
chosen. The plan asks which of the two rules a backend uses, because the issue
is that the backends differ -- so this is half of a comparison, and the WinUI
half is still needed before it means anything.

picker 的寬度會隨選取項目變動：選擇較長的項目時依序為 42、51、154、392。計畫詢問的是某個 backend
採用兩種規則中的哪一種，因為該 issue 的重點在於「兩個 backend 不同」——因此這只是比較的一半，
在取得 WinUI 的另一半之前，它還不具意義。

## Not yet run

P0 through P5, P7 through P12, P14 through P16, P18, and the remaining steps of
P13, P17, P21, P22, P23 and P24. Roughly 165 of the 190 steps.

尚未執行：P0 至 P5、P7 至 P12、P14 至 P16、P18，以及 P13、P17、P21、P22、P23、P24 的其餘步驟。
約當 190 步中的 165 步。
