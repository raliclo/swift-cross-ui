# The 92.5% brightness of Android captures

Found 2026-10-09 (P85). Closed 2026-10-23 as the desired design (6b9dce45):
kept as it is, not a defect to fix. The record stays in queue.md.

## What was seen

Captured colours read about 0.9255 of their value: P85's SVG background
`#fffbe6` as (236,232,213), the decor view's white as (236,236,236) -- the
grey "Android background" in captures since at least 2026-10-05 -- and
Material3's colorBackground (255,251,254) as (236,232,235). The status bar and
the system Settings app show true white, so the device is not dimmed.

## Ruled out (2026-10-09 to 10-13)

The pixels the app hands over (Android receives 255,251,230,255); any view
with alpha below 1; a foreground or hardware layer (walked from the decor);
the window's LayoutParams (no alpha, no DIM_BEHIND); SurfaceFlinger
(dimmingRatio 1.0, its two Dim layers hidden); screencap (the emulator window
on the Mac shows the same 236). The cause was not found.

## How to apply

- Do not reopen it, and do not "fix" a colour difference against iOS by
  scaling Android colours.
- When reading absolute colours from an Android capture, check whether the
  surface is one of the dimmed ones before calling a colour wrong.

## Unsettled

Later pixel reads on the same emulator show full values: P95's swatch row read
204 77 64 for the colour (0.8, 0.3, 0.25) (2026-10-16), and P112's angular
gradient read 254 0 1 and 0 255 0 (2026-10-20). So the dimming may not apply
to everything an app draws. Not re-investigated since the item was closed.

---

# Android 擷圖的 92.5% 亮度

2026-10-09 發現(P85)。2026-10-23 以「預期的設計」結案(6b9dce45):維持現狀，不是要修的缺陷。紀錄保留在 queue.md。

## 看到了什麼

擷圖中的顏色約為原值的 0.9255:P85 的 SVG 背景 `#fffbe6` 讀到 (236,232,213),decor view 的白色讀到 (236,236,236)——也就是
至少自 2026-10-05 起擷圖裡那個灰色的「Android 背景」——Material3 的 colorBackground (255,251,254) 讀到 (236,232,235)。
狀態列與系統的「設定」app 是真正的白色，所以裝置本身沒有變暗。

## 已排除(2026-10-09 至 10-13)

app 交出的像素(Android 收到 255,251,230,255);任何 alpha 小於 1 的 view;foreground 或硬體 layer(從 decor 往下走過);視窗的
LayoutParams(沒有 alpha,沒有 DIM_BEHIND);SurfaceFlinger(dimmingRatio 1.0,兩個 Dim layer 都隱藏);screencap(Mac 上的模擬器
視窗也是 236)。原因沒有找到。

## 怎麼用

- 不要重開這個項目，也不要用縮放 Android 顏色的方式去「修」與 iOS 的顏色差異。
- 從 Android 擷圖讀取絕對顏色時，先確認那個表面是不是會變暗的那一種，再判定顏色有錯。

## 未定案

同一台模擬器上之後的像素讀值是完整的值:P95 的色塊列在顏色 (0.8, 0.3, 0.25) 讀到 204 77 64(2026-10-16),P112 的角度漸層讀到
254 0 1 與 0 255 0(2026-10-20)。所以變暗可能不適用於 app 畫的所有東西。結案後沒有再調查。
