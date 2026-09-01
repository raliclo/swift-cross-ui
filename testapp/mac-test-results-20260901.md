# macOS answers — three split-view numbers

Measured 2026-09-01 on macOS 27.0, AppKitBackend, in reply to
`macrequestsplitview20260901.md`. Raw lines, as asked.

Pulled first: `1617b327` and `9691a499` are both in the tree
(`git merge-base --is-ancestor` on each).

## Read this before re-running any of it

**Clear the saved window frames first, or Q1 measures the wrong thing.**
`AppKitBackend.createWindow` calls `setFrameAutosaveName(id)` and reads back
`"NSWindow Frame \(id)"` from `UserDefaults.standard`, and `id` is derived from
the root view's type — so the key for most test apps is

    "NSWindow Frame TupleView1<HotReloadableView>-0"

which they share. A window then opens at whatever size the last app to use that
key was left at, and `.defaultSize` never gets a look in. On this machine that
key held `620 65 1076 907` before it was cleared, and P28 opened at 680x448 as a
bare executable and 1076x907 from a bundle — same binary, same commit.

The numbers below were taken after deleting that key from every domain the two
apps could reach:

```sh
for d in dev.swiftcrossui.testapp.debugTarget dev.swiftcrossui.testapp.p16 \
         dev.swiftcrossui.testapp.p7 P16 P7; do
  defaults delete "$d" "NSWindow Frame TupleView1<HotReloadableView>-0" 2>/dev/null
done
```

The bare executable was used, as the request specified. It has no bundle
identifier of its own, which is a second reason it is the right thing to measure
`.defaultSize` with.

---

## Q1 — `.defaultSize` gives 900x600 of **content** on AppKit

Measured, not confirmed.

```
frame 900x628 at 510,120
-actionfile: geometry frame=(510.0, 120.0) client=(510.0, 148.0) scale=1.0
```

The two lines are independent: the first is `CGWindowListCopyWindowInfo`, the
second is the InputEvent replay reporting the window's frame and client origins
from AppKit itself. Their y values differ by 28, so the title bar is **28 points**
and it is **outside** the content rect.

    frame   900 x 628
    content 900 x 600      (628 - 28)

**So AppKit behaves like WinUI, not like GTK.** The request asked for content and
that is content: `.defaultSize(width: 900, height: 600)` produced exactly
900x600 of it, with the title bar additional. GTK's 39px header bar eating into
the requested 600 is the odd one out of the three.

For the record, WinUI's frame is 916x639 against AppKit's 900x628 — both give
900x600 of content, and the frames differ only in how much furniture each
platform puts around it.

## Q2 — the `[SplitView]` lines

### P16

Three lines, all identical:

```
[SplitView] total=880.0 minLeading=86.0 minTrailing=20.0 -> bounds min=86 max=860 currentSidebar=200 leadingContent=200.0x497.0 trailingContent=680.0x497.0
[SplitView] total=880.0 minLeading=86.0 minTrailing=20.0 -> bounds min=86 max=860 currentSidebar=200 leadingContent=200.0x497.0 trailingContent=680.0x497.0
[SplitView] total=880.0 minLeading=86.0 minTrailing=20.0 -> bounds min=86 max=860 currentSidebar=200 leadingContent=200.0x497.0 trailingContent=680.0x497.0
```

Against the two you already have:

| | lines | leadingContent | trailingContent |
|---|---|---|---|
| WinUI | 1 | 200x486 | 680x486 |
| GTK | 3 | 200x485 → 200x446 → 200x446 | 680x… |
| **AppKit** | **3** | **200x497** | **680x497** |

Two things that may matter to you and that I am reporting rather than
interpreting:

- AppKit commits **three times**, like GTK, not once like WinUI. Unlike GTK the
  three are byte-identical — the height does not move at all, where GTK's goes
  485 → 446 → 446. So "three commits" and "the height settling" are separable:
  AppKit does the first without the second.
- The widths are 200 / 680 on all three backends. Only the heights differ, and
  they differ by exactly the furniture each platform puts above the content:
  497 (AppKit) vs 486 (WinUI) vs 446 (GTK, after its header bar).

### P7

Three lines, all identical:

```
[SplitView] total=420.0 minLeading=16.0 minTrailing=20.0 -> bounds min=16 max=400 currentSidebar=200 leadingContent=200.0x140.0 trailingContent=215.0x78.0
[SplitView] total=420.0 minLeading=16.0 minTrailing=20.0 -> bounds min=16 max=400 currentSidebar=200 leadingContent=200.0x140.0 trailingContent=215.0x78.0
[SplitView] total=420.0 minLeading=16.0 minTrailing=20.0 -> bounds min=16 max=400 currentSidebar=200 leadingContent=200.0x140.0 trailingContent=215.0x78.0
```

Beside GTK's:

```
GTK:    total=420.0 minLeading=31.0 minTrailing=36.0 -> bounds min=31 max=384 currentSidebar=200 leadingContent=200.0x140.0 trailingContent=207.0x77.0
AppKit: total=420.0 minLeading=16.0 minTrailing=20.0 -> bounds min=16 max=400 currentSidebar=200 leadingContent=200.0x140.0 trailingContent=215.0x78.0
```

`total`, `currentSidebar` and `leadingContent` agree exactly. The minimums
differ (31/36 vs 16/20), and `trailingContent` differs with them (207x77 vs
215x78) — which is what you would expect if the minimums are the only input
that changed, since `max` moves 384 → 400 by the same 16.

## Q3 — `List` is **not** greedy vertically, and AppKit agrees with GTK

`leadingContent=200.0x140.0`, the same 140 GTK reports, in a pane 180 tall.

So this is not a backend detail. Both backends' `List` fills the 200 width and
answers 140 for height — five rows at a 28-point pitch — and the framework
centres it in the 180-tall pane. Your own note says SwiftUI's `List` is greedy
on both axes and would answer 180; two independent backends answering 140 puts
the divergence in the shared layout code, which is the conclusion you set up
this measurement to reach.

Worth adding, because it is the same 28 twice and I do not think it is a
coincidence worth hiding: the row pitch here is 28 points and the AppKit title
bar measured in Q1 is also 28 points. They are unrelated quantities that happen
to match on this machine, so do not read a relationship into a future run where
one of them moves.

---

# macOS 端的回答 — 三個 split view 的數字

2026-09-01 於 macOS 27.0、AppKitBackend 上量測，回覆
`macrequestsplitview20260901.md`。依要求提供原始輸出行。

已先 pull：`1617b327` 與 `9691a499` 皆在樹中。

## 重跑之前請先讀這一段

**先清除已存的視窗 frame，否則 Q1 量到的不是你要的東西。**
`AppKitBackend.createWindow` 會呼叫 `setFrameAutosaveName(id)`，並自
`UserDefaults.standard` 讀回 `"NSWindow Frame \(id)"`，而 `id` 是由 root view 的型別推得
——因此大多數測試 app 的鍵是同一個：

    "NSWindow Frame TupleView1<HotReloadableView>-0"

視窗於是會以「最後一個使用該鍵的 app 被留下的尺寸」開啟，`.defaultSize` 根本沒有機會作用。
在這台機器上，該鍵在被清除前的值是 `620 65 1076 907`；同一個 binary、同一個 commit，P28 以裸
執行檔啟動是 680x448，自 bundle 啟動則是 1076x907。

下列數字是在刪除該鍵（於這兩支 app 可能觸及的每一個 domain）之後取得的，指令見上方英文段落。

依請求所述使用裸執行檔。它本身沒有 bundle identifier，而那正是「用它來量 `.defaultSize` 才對」
的第二個理由。

## Q1 — `.defaultSize` 在 AppKit 上給的是 900x600 的**內容**

這是量出來的，不是確認來的。原始兩行見上方英文段落。

那兩行彼此獨立：第一行來自 `CGWindowListCopyWindowInfo`，第二行是 InputEvent 重放自 AppKit
本身回報的視窗 frame 與 client 原點。兩者的 y 值相差 28，因此標題列為 **28 點**，且位於內容矩形
**之外**。

    frame   900 x 628
    content 900 x 600      （628 - 28）

**因此 AppKit 的行為與 WinUI 一致，而非與 GTK 一致。** 請求要的是內容，而這就是內容：
`.defaultSize(width: 900, height: 600)` 確實產出 900x600 的內容，標題列另計。GTK 那條吃進所
要求的 600 之內的 39px 標題列，是三者中的異類。

附帶一提：WinUI 的外框是 916x639，AppKit 是 900x628——兩者都給出 900x600 的內容，外框的差異
只在於各平台在內容周圍放了多少裝飾。

## Q2 — `[SplitView]` 的輸出行

P16 為三行、完全相同；P7 亦為三行、完全相同（原始行見上方英文段落）。

兩件我只回報、不作詮釋的事：

- AppKit 會 commit **三次**，與 GTK 相同，而非如 WinUI 只有一次。但與 GTK 不同的是，這三行
  完全一致——高度全程不動，而 GTK 的是 485 → 446 → 446。因此「commit 三次」與「高度逐步收斂」
  是可以分開的兩件事：AppKit 有前者、沒有後者。
- 三個 backend 的寬度都是 200 / 680。只有高度不同，而其差異恰好等於各平台放在內容之上的裝飾：
  497（AppKit）、486（WinUI）、446（GTK，扣掉其標題列之後）。

P7 方面，`total`、`currentSidebar` 與 `leadingContent` 三者完全一致。最小值不同
（31/36 對 16/20），`trailingContent` 隨之不同（207x77 對 215x78）——若最小值是唯一改變的輸入，
這正是預期結果，因為 `max` 也同樣移動了 16（384 → 400）。

## Q3 — `List` 在垂直方向**不**貪婪，且 AppKit 與 GTK 一致

`leadingContent=200.0x140.0`，與 GTK 回報的 140 相同，而窗格高 180。

因此這不是某個 backend 的細節。兩個 backend 的 `List` 都填滿了 200 的寬度、高度卻回答 140
——五列乘以 28 點的列距——框架隨後將它置中於 180 高的窗格中。你自己的註記指出 SwiftUI 的 `List`
在兩個軸向皆為貪婪、應回答 180；兩個各自獨立的 backend 都回答 140，就把這個分歧定位在共用的
版面程式碼中，而那正是這次量測所要抵達的結論。

還有一點值得補充，因為同一個 28 出現了兩次，我認為不該把它藏起來：此處的列距是 28 點，而 Q1 量到
的 AppKit 標題列也是 28 點。這兩個量彼此無關，只是在這台機器上恰好相同——因此若日後某次執行中
其中一個變動了，請不要在兩者之間讀出任何關聯。
