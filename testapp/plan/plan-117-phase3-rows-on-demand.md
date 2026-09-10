# #117 phase 3:依需求建列 —— 為什麼它比它看起來大

**狀態:已量測、形狀已定,尚未實作。這一項需要五個 backend 的協定改動,而那個改動是「方向反轉」,
不是新增一個方法。**

**Status: measured, shape settled, not implemented. This one needs a protocol
change on all five backends, and the change is a REVERSAL of direction rather
than an added method.**

---

## 一、量到的 / What was measured

2026-09-11,P57 在 AppKit 上,RSS:

| 列數 | RSS | 每列 |
| --- | --- | --- |
| 400 | 113 MB | — |
| 10,000 | 423 MB | 約 **31 KB** |

那 31 KB 不在 backend 的 widget 裡——AppKit 的 `NSTableView` 本來就回收 cell。它在**框架**這一側:
`Views/List.swift:170` 是 `(0..<rowCount).map(rowContent)`,每一列一個 `AnyViewGraphNode`,而
`computeLayout` 在每次更新時逐列跑一遍。

Measured on AppKit: 31 KB per row, and it is not in the backend's widgets --
`NSTableView` recycles cells already. It is one `AnyViewGraphNode` per row in the
framework, plus a layout pass per row on every update.

---

## 二、為什麼「加一個 visibleRowRange」不夠 / Why one more getter does not do it

顯而易見的做法是加一個 getter:

```swift
func visibleRowRange(ofSelectableListView listView: Widget) -> Range<Int>?
```

然後只為那個範圍建節點。**它行不通,而理由在資料流的方向。**

今天的流向是:框架建好**全部**的列,交給 backend
(`AppKitBackend` 的 `table.customDelegate.widgets = cells`)。backend 拿到的是一個完整陣列。
若框架只交出可見的那些,那個表格會顯示一片空白——因為它並沒有「向框架要第 N 列」的管道。

而 `NSTableView` 原生的運作方式**正是**那個管道(`tableView(_:viewFor:row:)`),
`UITableView`、GTK 的 `GtkListView`(帶 factory)與 WinUI 的 `ItemsRepeater` 也都是。
**五個 backend 都已經支援「向資料來源要一列」,而本套件沒有在用它。**

The obvious move -- add a `visibleRowRange` getter and build only that range --
does not work, and the reason is the direction of the data flow. Today the
framework builds every row and hands the backend a complete array. All five
backends natively support asking a data source for row N, and this package does
not use that.

---

## 三、形狀 / The shape

```swift
extension BackendFeatures {
    public protocol LazyListRows: SelectableListViews {
        /// Tells the list how many rows exist, without building any of them.
        func setRowCount(ofSelectableListView listView: Widget, to count: Int)

        /// Asks the framework for one row's widget, when the list needs it.
        ///
        /// Called by the BACKEND, on the main thread, for a row that is about to
        /// become visible. Returning `nil` means "not ready", and the list is
        /// expected to show an empty row rather than to fail.
        func setRowProvider(
            ofSelectableListView listView: Widget,
            to provider: @escaping (Int) -> Widget?
        )

        /// Tells the framework a row's widget is no longer needed.
        ///
        /// Without this the memory never comes back: rows would be built on
        /// demand and then kept for ever, which is a slower version of the same
        /// problem.
        func setRowRecycler(
            ofSelectableListView listView: Widget,
            to recycler: @escaping (Int) -> Void
        )
    }
}
```

### 為什麼是三個方法,而不是一個

- **`setRowCount` 必須與內容分離。** 捲軸的長度由列數決定,而列數在任何一列被建立之前就已知。
- **`setRowProvider` 是那個反轉。** 它是唯一一個「backend 呼叫框架」的方法,而那正是本項的全部內容。
- **`setRowRecycler` 是那一半容易被忘記的。** 少了它,記憶體只會延後成長、不會回來——而那在
  「捲到底」之後與今天完全相同。

### 框架這一側要改什麼

`List.computeLayout` 目前 `zip(rowViews, children.nodes)` 逐列計算。改成:
一個逐列的節點快取(建過的留著、被回收時丟掉),以及一個「這一列多高」的估計值——因為捲軸需要
總高度,而未建立的列沒有量過。**均一列高是第一版該做的假設**,並且要寫明:一個「每列高度不同」的
清單,在捲軸長度上會是錯的,直到那些列被建出來為止。

---

## 四、為什麼還沒做 / Why it is not implemented yet

**因為它會動到剛剛才在五個 backend 上修好的東西。** #117 的 phase 2/4a/5 才把 list viewport 修對,
而這一項要改的是同一批程式碼的資料流方向。做壞了的失效方式是「清單看起來是空的」或「捲軸長度錯了」
——兩者都會在五個平台上同時出現。

規模誠實地說:一個新協定(三個方法)、五份 backend 實作、`List` 的節點快取與高度估計、一支量記憶體
的測試 app。這不是一個可以夾在其他事情之間做完的項目。

**下一步是決定要不要投入**,而那個決定的輸入是上面那張表:10,000 列 423 MB。若目標裝置是手機,
那個數字就是理由;若不是,這一項可以繼續排在後面而不必愧疚。

It is not implemented because it changes the direction of the data flow through
code that was fixed on five backends days ago, and a bad version fails as "the
list is empty" or "the scrollbar is the wrong length" on all five at once. The
next step is a decision about whether to spend that, and the input to the
decision is the table at the top.
