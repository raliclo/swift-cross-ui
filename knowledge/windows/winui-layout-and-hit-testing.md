# WinUIBackend: layout, measurement and hit testing

Written 2026-10-24 from Sources/WinUIBackend (WinUIBackend.swift,
ContinuousGestures.swift, LazyListRows.swift), commits d34be28f, 83196598,
17bf5ad5, b76c6818, 7bec9284, and results.csv2 (windows, winui: P47, P63, P43
2026-10-19; P17-DOE, P95 2026-10-20; P50, P65 2026-09-17).

## Hit testing: only a null brush lets clicks through

XAML hit-tests any brush, **including a transparent one**; only `nil` is
skipped. Two bugs had this cause:

- A stroked shape swallowed every click inside its outline, so a `.border`
  (an overlay of `Rectangle().stroke`) made the button under it dead (P50,
  d34be28f, 2026-09-17).
- `Color.clear` over a button swallowed its clicks (83196598, 2026-10-22).

Fix in both: set the brush to `nil` when its opacity is 0. Any new code that
paints "invisible" must do the same.

## Layout and measurement

- **Text gets one extra DIP.** Layout rounding at 125% left a TextBlock a
  fraction of a DIP short of its measured width, and `.characterEllipsis` cut
  the last word ("unkno..."). Rounding up alone did not cure it; rounding up
  plus 1 DIP did (17bf5ad5, P47).
- **Parent links before load.** `parent`, `VisualTreeHelper` and `xamlRoot`
  are nil until an element loads, which is after the commits that ask, so
  `frame(in: .global)` read 0,0. The backend keeps its own parent links from
  insert (P63, 2026-10-19).
- **Late row layout.** XAML lays list rows out after the first settle;
  `ScrollTrackingModifier` retries every 50 ms for up to 2 s (b76c6818, P101).
- **Measuring a ComboBox measures its whole item list**: a 60-item seconds
  picker made a window 2757 px tall. It has a fixed size now.
- A Canvas reports DesiredSize 0, so a Canvas-rooted representable must
  implement `sizeThatFits` itself.
- `clipped()`: the clip was set only on `SizeChanged`, which never arrived;
  `setSize` sets it too (P17-DOE, 7bec9284).
- Stroke outside the frame: `renderPath` grows the Path by the stroke width with
  a negative margin, so XAML's layout clip keeps the outer half of a stroke
  (P43, 2026-10-19).
- `WM_GETMINMAXINFO` overflowed Double -> Int32 on an infinite max size; it is
  clamped (P95).
- Lazy rows: a generated container's `ContentTemplate` swallowed the element
  (`contentTemplate = nil`, LazyListRows.swift). 10,000 rows: 328 MB -> 143 MB.

## Gestures

- Handlers used to be added on every update and never removed: one drag ended
  12 times. `ManipulationTarget` (a Grid) subscribes once in init; update swaps
  closures (P65, 2026-09-17).
- Drag targets take the mouse through pointer events: manipulations reach a
  mouse late and in batches every 42-78 ms, which broke release velocity (P108,
  2026-10-19).
- Touch-hold hover: a finger resting 0.5 s within 10 DIPs starts hovering until
  the lift (WinUIBackend+InputTargets.swift, a422c0b3, 2026-10-23).

---

# WinUIBackend:版面、量測與點擊判定

2026-10-24 依 Sources/WinUIBackend(WinUIBackend.swift、ContinuousGestures.swift、LazyListRows.swift)、d34be28f、
83196598、17bf5ad5、b76c6818、7bec9284,以及 results.csv2(windows、winui:P47、P63、P43 於 2026-10-19;P17-DOE、
P95 於 2026-10-20;P50、P65 於 2026-09-17)寫成。

## 點擊判定：只有 null 筆刷會讓點擊穿過

XAML 對任何筆刷做點擊判定，**包括透明的**;只有 `nil` 會被略過。有兩個錯誤出自這個原因:

- 有描邊的形狀吞掉輪廓內所有點擊，所以 `.border`(`Rectangle().stroke` 疊加層)讓底下的按鈕失效(P50,
  d34be28f,2026-09-17)。
- 蓋在按鈕上的 `Color.clear` 吞掉它的點擊(83196598,2026-10-22)。

兩者的修正：不透明度為 0 時把筆刷設為 `nil`。任何新寫的「看不見」繪製都必須照做。

## 版面與量測

- **文字多給一個 DIP。** 在 125% 時版面取整讓 TextBlock 比量測寬度少了不到一個 DIP,`.characterEllipsis` 截掉最後
  一個字(「unkno...」)。只無條件進位沒用；進位再加 1 DIP 才行(17bf5ad5,P47)。
- **載入前的父連結。** 元素載入前 `parent`、`VisualTreeHelper` 與 `xamlRoot` 都是 nil,而載入發生在發問的 commit
  之後，所以 `frame(in: .global)` 讀到 0,0。backend 自 insert 起自己保存父連結(P63,2026-10-19)。
- **列表列較晚排版。** XAML 在第一次穩定之後才排列表列;`ScrollTrackingModifier` 每 50 ms 重試，最多 2 秒
  (b76c6818,P101)。
- **量測 ComboBox 會量到整份項目清單**:60 項的秒數選擇器讓視窗高達 2757 px。現在改為固定大小。
- Canvas 回報的 DesiredSize 是 0,所以以 Canvas 為根的 representable 必須自己實作 `sizeThatFits`。
- `clipped()`:原本只在 `SizeChanged` 時設定裁切，而它從未到達;現在 `setSize` 也會設定(P17-DOE,7bec9284)。
- 畫框外的描邊:`renderPath` 以負 margin 把 Path 加大一個描邊寬度，讓 XAML 的版面裁切保留描邊外側那一半
  (P43,2026-10-19)。
- `WM_GETMINMAXINFO` 在最大尺寸為無限時 Double -> Int32 溢位；已夾限(P95)。
- Lazy 列：產生的容器的 `ContentTemplate` 吞掉了元素(`contentTemplate = nil`,LazyListRows.swift)。10,000 列:
  328 MB -> 143 MB。

## 手勢

- handler 原本每次更新都加、從不移除：一次拖曳結束 12 次。`ManipulationTarget`(一個 Grid)在 init 只訂閱一次;
  update 只換 closure(P65,2026-09-17)。
- 拖曳目標以 pointer 事件接收滑鼠:manipulation 對滑鼠來得晚且成批，每 42–78 ms 一次，弄壞了放開時的速度
  (P108,2026-10-19)。
- 觸控按住 hover:手指在 10 DIP 內停留 0.5 秒後開始 hover,直到放開(WinUIBackend+InputTargets.swift,a422c0b3,
  2026-10-23)。
