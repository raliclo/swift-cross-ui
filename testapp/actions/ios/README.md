# ios

`test.zsh <Pn> --ios --actionfile` replays these CSV files through XCUITest. The
current runner supports `click`, `doubleclick`, `move`, `sleep`, `scroll`, and a
`mousedown`/`mouseup` drag pair. Keyboard rows are still rejected, because
XCUITest does not provide an equivalent operation with the same semantics.

`scroll` arrived on 2026-09-02 and this paragraph said it was rejected for four
days after that. A notch is a drag of 40 points and the sign inverts -- scrolling
down means dragging up -- and **the drag has to stay inside the window**: a
gesture that would leave the 393 x 852 frame silently does nothing, so a file
that scrolls right starts its `move` near the right edge. `P8-nested-scroll-views.csv`
records how the behaviour was pinned down; `P27-scroll-to-the-angular-gradients.csv`
and `P25-reach-the-refusing-drop-area.csv` are the horizontal cases.

The sample file is a smoke case only; its coordinates still need visual
verification on the intended Simulator device before it is used as a product
regression test.

`test.zsh <Pn> --ios --actionfile` 會透過 XCUITest 重放這裡的 CSV。現行 runner 支援
`click`、`doubleclick`、`move`、`sleep`、`scroll`，以及以 `mousedown`／`mouseup` 組成的拖曳。
鍵盤列仍會被拒絕，因為 XCUITest 沒有提供語意相同的等價操作。

`scroll` 於 2026-09-02 抵達，而本段的中文半邊在其後四天仍寫著它會被拒絕——英文半邊已更新，中文半邊
沒有。一格等於 40 點的拖曳，且符號相反（向下捲動意味著向上拖曳），而**該拖曳必須留在視窗內**：
一個會離開 393 x 852 框架的手勢會靜默地什麼都不做，因此向右捲動的檔案要把 `move` 起點放在靠近右緣處。
`P8-nested-scroll-views.csv` 記載了該行為是如何被釘下來的；`P27-scroll-to-the-angular-gradients.csv`
與 `P25-reach-the-refusing-drop-area.csv` 是水平捲動的案例。

目前的 sample 只用於 smoke test；在作為正式 regression test 前，仍須於指定的
Simulator 裝置上目視確認座標。
