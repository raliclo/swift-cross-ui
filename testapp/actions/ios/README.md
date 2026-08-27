# ios

`test.zsh <Pn> --ios --actionfile` replays these CSV files through XCUITest. The
current runner supports `click`, `doubleclick`, `move`, `sleep`, and a
`mousedown`/`mouseup` drag pair. Keyboard and scroll rows are rejected because
XCUITest does not provide an equivalent operation with the same semantics.

The sample file is a smoke case only; its coordinates still need visual
verification on the intended Simulator device before it is used as a product
regression test.

`test.zsh <Pn> --ios --actionfile` 會透過 XCUITest 重放這裡的 CSV。現行 runner 支援
`click`、`doubleclick`、`move`、`sleep`，以及以 `mousedown`／`mouseup` 組成的拖曳。
鍵盤與 scroll 列會被拒絕，因為 XCUITest 沒有提供語意相同的等價操作。

目前的 sample 只用於 smoke test；在作為正式 regression test 前，仍須於指定的
Simulator 裝置上目視確認座標。
