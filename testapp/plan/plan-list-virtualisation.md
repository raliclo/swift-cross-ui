# plan: virtualising `List` (#117)

**狀態:設計,尚未實作。沒有任何程式碼因這份文件而改變。**

**Status: design only. No code has changed for this document.**

寫在動手之前,理由是 2026-09-09 量到的東西改變了這項工作的形狀——它不是「把一個慢的清單變快」,
而是「這個清單根本沒有視口」。

Written before starting, because what was measured on 2026-09-09 changed the shape
of the task: it is not "make a slow list fast", it is "this list has no viewport".

---

## 一、量到的基準線 / The measured baseline

`testapp/P57.swift`,同一個二進位檔、不同的 `-rows`:

| rows | 視窗尺寸 / window |
| --- | --- |
| 10 | 1280 × 1958 px |
| 50 | 1280 × 9306 px |
| 100 | 640 × 9253 px |
| 200 | 擷取失敗,退回抓整個螢幕 / capture failed, fell back to the screen |
| 400 | 擷取失敗 / capture failed |

`List` 自己不捲動。`AppKitBackend.createSelectableListView` 建立的是一個
`hasVerticalScroller = false` 的 `NSDisabledScrollView`,**而那是刻意的**;框架把 table 排版成它的
完整內容高度。因此 N 列會產出與 N 成正比的視窗,而超過約一百列之後它大過顯示器。

`List` does not scroll itself: `createSelectableListView` builds an
`NSDisabledScrollView` with `hasVerticalScroller = false`, deliberately, and the
framework lays the table out at full content height. N rows give a window
proportional to N.

**檢驗標準因此是一個數字:那個高度必須停止隨列數增長。** 不是計時。計時在此處會是單一路徑的單一
樣本,而那正是 `mistakes_prevention` 明說不可據以下結論的東西。

The acceptance test is therefore one number -- that height must stop growing with
the row count. Not a clock: a timing reading here is one sample of one path.

---

## 二、真正的障礙,不是 `setItems` / The real obstacle is not `setItems`

顯而易見的讀法是「`setItems(ofSelectableListView:to:withRowHeights:)` 收下全部的 widget,把它改成
依需求索取就好」。那是**症狀**。

The obvious reading is that `setItems` takes every widget and should pull instead.
That is the symptom.

成因在 `Views/List.swift:218`:

```swift
let height = childResults.map(\.size.height).map { rowHeight in
    max(rowHeight + Double(verticalBasePadding), Double(minimumRowSize.y))
}.reduce(0, +)
```

**這個清單的高度是每一列高度的總和。** 要算出它,每一列都必須先被建構、被排版。只要那一行還在,
再怎麼改 `setItems` 都不會少建任何一列。

**The list's height is the sum of every row's height.** Computing it requires every
row to exist and to have been laid out. While that line stands, no change to
`setItems` removes a single row's construction.

---

## 三、兩條出路,只有一條可行 / Two ways out, one of which works

### (a) 統一列高:量一列,乘上 N

只有在每一列都一樣高時才正確。`List` 的 `rowContent` 是任意的 view builder,一列可以是一行文字、
另一列可以是一張圖。SwiftUI 的 `List` 允許不等高的列。採用此法會讓「不等高的列」這件事從
「可行」變成「靜默錯位」——而錯位在截圖上看起來像是版面問題,不像一個被違反的假設。

Correct only if every row is the same height, and `rowContent` is an arbitrary view
builder. It turns unequal rows from "supported" into "silently misaligned".

### (b) 讓清單成為視口,由 backend 擁有高度 ✅

這是真正的虛擬化 widget 在做的事,而且五個平台都已經內建:

| backend | widget | 誰擁有高度 |
| --- | --- | --- |
| AppKit | `NSTableView` in a live `NSScrollView` | widget |
| UIKit | `UITableView` | widget |
| Android | `RecyclerView` | widget |
| WinUI | `ItemsRepeater` in a `ScrollViewer` | widget |
| Gtk | `GtkListView` | widget |

框架給它一個**視口大小的框**,widget 自己捲動、自己回收列。框架不再加總任何東西。

The framework gives it a viewport-sized frame; the widget scrolls and recycles.
The framework stops summing anything.

**這也解釋了為何 `NSDisabledScrollView` 存在。** 它不是疏漏,它是「框架擁有版面」這個決定的結果。
虛擬化要推翻的正是那個決定,而不是繞過它。

This is also why `NSDisabledScrollView` exists. It is not an oversight; it is the
consequence of the framework owning layout. Virtualising reverses that decision
rather than working around it.

---

## 四、真正困難的那一步 / The step that is actually hard

widget 要回收列,就必須能在**捲動途中**索取第 N 列——那不在任何一次版面計算之內。而此處建立一個
row 節點需要:

```swift
AnyViewGraphNode(for: rowView, backend: backend, environment: environment)
```

`environment` 是逐次版面計算傳下來的值,而不是節點自己持有的東西。因此「依需求造一列」需要框架
保留一份足以建構子節點的環境,並在其後每次更新時讓它保持有效。

A recycling widget must ask for row N mid-scroll, outside any layout pass, and
building a row node needs an `environment` that is passed down per layout rather
than held by the node. So on-demand row creation requires the framework to keep an
environment alive and valid between updates.

**那是這項工作的核心,而不是 protocol 的簽章。** 先解決它,requirement 的形狀才會是被推導出來的,
而不是被猜出來的。

That is the core of the work, not the protocol signature. Solve it first and the
requirement's shape is derived rather than guessed.

---

## 五、分階段,每一階段各自可驗 / Phased, each phase checkable on its own

1. **基準線** ✅ 已完成。P57 加上矩陣中的那一列。
2. **讓一個 backend 的清單擁有自己的高度。** 只做 AppKit:啟用那個 scroll view、給 table 一個
   視口大小的框、讓 `List` 不再加總。檢驗:P57 在 400 列時視窗高度不變。
   *此階段不加任何 protocol requirement,因此不會有建置空窗。*
3. **依需求建立列。** 上述第四節。檢驗:P57 在 10,000 列時仍然開得起來。
4. **推廣到其餘四個 backend**,requirement 與六個實作同一個 commit。
5. **GTK 與 WinUI 由 Windows 端驗證**,檔頭寫明該先查什麼。

Phase 2 是刻意排在第一位的:它把「框架擁有版面」這個決定在**一個** backend 上推翻,而那是整件事
裡唯一還沒有人做過的部分。若它在 AppKit 上行不通,後面四個都不必寫。

Phase 2 comes first deliberately: it reverses the "framework owns layout" decision
on ONE backend, which is the only part nobody has done yet. If it does not work on
AppKit, the other four need not be written.

---

## 六、已經知道會被打到的東西 / Known collateral

- **動作檔。** 清單一旦捲動,列在畫面上的位置就取決於捲動位置。任何點某一列的動作檔都會需要
  重新量測。目前有幾份不確定;`grep -l "List" testapp/actions/*/*.csv` 是起點。
- **`minimumRowSize` 與 `baseItemPadding`** 兩個 requirement 是為「框架自行排版每一列」而存在的。
  Phase 2 之後它們可能失去意義,但**不要在確認之前移除**——它們也被 `updateSelectableListView`
  以外的地方用到。
- **P57 自己**在 Phase 2 之後必須重新量測,依 `flow.md` 3e-1:它現在的那一列描述的是舊行為。

Action files that click a row will need re-measuring once the list scrolls;
`minimumRowSize` and `baseItemPadding` may lose their meaning but must not be
removed before that is confirmed; and P57's own matrix row describes the old
behaviour the moment phase 2 lands.
