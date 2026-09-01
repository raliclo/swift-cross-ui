# Request to the macOS side — three split-view numbers

Written 2026-09-01 from the Windows/WSL side. Three questions were measured
on WinUIBackend and GtkBackend and could not be settled without AppKit. Each
one is a number, not a judgement, so answering costs a few minutes.

**Pull first.** The diagnostic these use was added in `1617b327` and renamed
in `9691a499`. Without them `SCUI_DEBUG_SPLIT` prints no pane figures.

Reply by appending to `testapp/mac-test-results-<date>.md` and pushing; no
need to interpret anything, the raw lines are the answer.

---

## Q1 — does `.defaultSize` give 900x600 of *content* on AppKit?

This is the one that matters most, because the two backends disagree and one
of them is wrong.

P16 asks for `.defaultSize(width: 900, height: 600)`.

- **WinUI** gives a 900x600 client area, with the title bar outside it in
  non-client space. The window frame measures 916x639.
- **GTK** gives a 900x600 *window*, with a 39px client-side-decoration header
  bar **inside** it. Content is 900x561 — 39px short of the request.

Expected on macOS: `.defaultSize` maps to the window's content rect and the
title bar is additional, so AppKit should behave like WinUI. **That is an
expectation, not a measurement — please measure it rather than confirm it.**

```sh
SCUI_DEBUG=1 zsh testapp/compile.zsh P16
SCUI_DEBUG_SPLIT=1 ./testapp/output/P16 --debug
```

Report: the window's frame size and its content size. If it is easier, a
screenshot of the window is enough — the frame-versus-content difference is
measurable from the image, which is how the GTK 39px was established.

## Q2 — the `[SplitView]` lines for P16 and P7

Same two commands as above, plus P7. Read `splitview-debug.log` in the
working directory; delete it first so the file holds one run only.

```sh
cd testapp/output && rm -f splitview-debug.log
SCUI_DEBUG_SPLIT=1 ./P16 --debug     # wait ~8s, quit
cat splitview-debug.log
rm -f splitview-debug.log
SCUI_DEBUG_SPLIT=1 ./P7 --debug      # wait ~8s, quit
cat splitview-debug.log
```

For comparison, what the other two backends produce:

| | P16, first render |
|---|---|
| WinUI | one line, `leadingContent=200x486 trailingContent=680x486` |
| GTK | three lines, height `485 -> 446 -> 446`, widths steady at 200 / 680 |

```
P7 on GTK, three identical lines:
[SplitView] total=420.0 minLeading=31.0 minTrailing=36.0 -> bounds min=31 max=384 \
  currentSidebar=200 leadingContent=200.0x140.0 trailingContent=207.0x77.0
```

What is interesting is the **number of lines** as much as the values: WinUI
commits P16's first render once, GTK three times.

## Q3 — is `List` greedy vertically?

Falls out of Q2's P7 line, so no extra run is needed — but it is the question
the number is being read for, so it is worth stating separately.

P7's `#556` split view is pinned to `.frame(width: 420, height: 180)`. Its
sidebar is a `List` of five rows. On GTK that `List` answers **200x140** — it
fills the 200 width but returns 140 for height, which is exactly five rows at
a 28px pitch, and the framework then centres it in the 180-tall pane.

SwiftUI's `List` is greedy on both axes and would be expected to answer 180.
If AppKit's `leadingContent` height is 180 rather than ~140, that is a real
divergence in the shared layout code and not a backend detail.

---

# 對 macOS 端的請求 — 三個 split view 的數字

2026-09-01 由 Windows/WSL 端寫下。以下三個問題已在 WinUIBackend 與 GtkBackend
上量測完畢，但少了 AppKit 就無法定案。每一個要的都是數字而非判斷，所以回答只需
幾分鐘。

**請先 pull。** 這些指令所用的診斷加於 `1617b327`，並於 `9691a499` 改名。沒有這
兩個 commit，`SCUI_DEBUG_SPLIT` 不會印出窗格數字。

回覆方式：附加到 `testapp/mac-test-results-<date>.md` 後推送即可；不需要做任何
詮釋，原始輸出行本身就是答案。

## Q1 — `.defaultSize` 在 AppKit 上給的是 900x600 的**內容**嗎？

這一題最重要，因為兩個 backend 的行為互相矛盾，其中一個是錯的。

P16 要求 `.defaultSize(width: 900, height: 600)`。

- **WinUI** 給出 900x600 的 client area，標題列位於其外的 non-client 區域，
  視窗外框量得 916x639。
- **GTK** 給出的是 900x600 的**視窗**，而一條 39px 的 CSD 標題列在那 600 **之
  內**，內容區只有 900x561——比要求少了 39px。

macOS 上的預期是：`.defaultSize` 對應視窗的 content rect、標題列另計，因此
AppKit 應與 WinUI 一致。**但那是預期而非量測，請去量它，不要去確認它。**

回報：視窗的外框尺寸與內容尺寸。若截圖較方便，一張視窗截圖就夠了——外框與內容
的差值可以從影像量出來，GTK 的那 39px 就是這樣得到的。

## Q2 — P16 與 P7 的 `[SplitView]` 輸出行

指令同上，另加 P7。讀取工作目錄下的 `splitview-debug.log`；請先刪除它，讓檔案
只含這一次執行的內容。

對照組——另外兩個 backend 的結果：

| | P16 首次算繪 |
|---|---|
| WinUI | 一行，`leadingContent=200x486 trailingContent=680x486` |
| GTK | 三行，高度 `485 → 446 → 446`，寬度穩定在 200 / 680 |

P7 在 GTK 上為三行相同的輸出：
`total=420.0 minLeading=31.0 minTrailing=36.0 -> bounds min=31 max=384`
`currentSidebar=200 leadingContent=200.0x140.0 trailingContent=207.0x77.0`

值得注意的不只是數值，還有**行數**：WinUI 對 P16 的首次算繪只 commit 一次，
GTK 則是三次。

## Q3 — `List` 在垂直方向是否貪婪？

這一題可由 Q2 的 P7 輸出直接得出，不需額外執行——但它正是那個數字要回答的問題，
因此獨立列出。

P7 的 `#556` split view 被固定在 `.frame(width: 420, height: 180)`，其側欄是一個
五列的 `List`。在 GTK 上該 `List` 回答 **200x140**——填滿了 200 的寬度，高度卻回
傳 140，正好是五列乘以 28px 的列距，框架隨後將它置中於 180 高的窗格中。

SwiftUI 的 `List` 兩個軸向都是貪婪的，預期會回答 180。若 AppKit 的
`leadingContent` 高度是 180 而非約 140，那就是共用版面程式碼中的真實分歧，而不是
某個 backend 的細節。
