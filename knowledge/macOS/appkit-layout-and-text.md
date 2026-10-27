# AppKitBackend: text, tables, lists and scrolling

Root causes of layout defects found on macOS, with the measurement that
showed each one.

## Text is measured by the control that draws it

`NSString.boundingRect` reported about 4 pt less than the `NSTextField` draws,
on every string tried. Two-digit rows in P34 stopped at x=319 mid-glyph while
row 0 ended at 316. Text is now measured with the field's own
`cell.cellSize` (P34, 2026-09-10).

## A clamped Text keeps whole lines, at least one

A zero-height proposal came back from `NSTextField` 1 pt tall, so a caption
beside a fixed-size sibling was not drawn and the view below rose into its
place (queue item 17: P10, P2, P8, P11, P13, P17, P27, P29, P30, P43, P44,
P50, P83). Since 7efbaede (2026-10-16) a height shorter than one line still
gets one line, and since 9fd3ba85 a clamped height is whole lines only, so
`truncatesLastVisibleLine` ends a long cell in an ellipsis instead of half a
second line. Change in `Sources/SwiftCrossUI/Views/Text.swift`, so every
backend gets it.

## Tables take the framework's column widths

AppKitBackend never implemented `setColumnWidths`: columns kept AppKit's own
widths (about 234 pt in P23 and P26) while `Table` measured cells at its share
(about 392 pt), so text ran into the next column. The inset style macOS 11
chooses added 16 pt per side. Columns now take Table's widths with no spacing
and the full-width style (9fd3ba85, 2026-10-16).

Sorting: `sortDescriptorPrototype` must be set on every commit, because
`setColumnLabels` rebuilds the columns; removing a column is announced as a
sort change and made the binding oscillate until the guard covered every
framework-driven mutation (P23, 2026-09-16).

## Lists: rows, recycling and memory

- An `NSTableRowView` with no identifier cannot be recycled: live row views
  went 30 -> 1745 while scrolling; with an identifier, 31 (352b8c52,
  2026-09-11).
- With lazy rows and `LazyListRowLifetimes` (didAdd/didRemove on the row
  view), 10,000 rows cost 104 MB against a 101 MB one-row baseline (was
  423 MB); scrolling the whole list settles at 134 MB (P57, 2026-09-11).
  `didRemove`'s row index is -1 when the row is gone, so the index is recorded
  at `didAdd`.
- `NSTableView` coalesces layout during a scrollbar drag and renders only the
  landing position: a drag built 38 rows, the wheel built all 500 (P57,
  2026-09-16/17). Measure traversal with the wheel.

## Scroll bars

AppKit posts `NSScroller.preferredScrollerStyleDidChangeNotification` to the
app's own notification centre, not the distributed one. An app launched with
a mouse attached reports overlay scrollers, then legacy a moment later; the
backend listened on the wrong centre and laid out with a scroller width of 0,
so P8's labels sat under the 15 pt scroller (6f4f94a2, 2026-10-19).

## Crash shapes seen at launch

- `.inspect` overloads cast the node's widget; once `TextField` became a
  styled container the cast trapped. They now search the subtree for the
  requested `NSView` subclass (P4, e7f5eb37, 2026-09-17).
- Exclusive-access trap in `ForEach.commit`: an `inout` on a class property
  held exclusive access while committing children that re-entered it.
  `withStackLayoutCache` copies the cache out and back (P8, e7f5eb37). Core
  code, but found on macOS.

## Limits

- The `Button` zero-height proposal fix that sets a window's minimum height is
  in `window-sizes.md`.
- macOS 27 made an `NSButton` 82x24 where older systems gave 72x20; tests that
  hard-code control metrics break on an OS update (install_tool_mac.zsh).

---

# AppKitBackend:文字、表格、清單與捲動

在 macOS 上找到的版面缺陷根本原因，附上顯示出問題的量測。

## 文字以實際繪製它的控制項量測

`NSString.boundingRect` 回報的寬度，在每個試過的字串上都比 `NSTextField` 實際畫出來的少約 4 pt。P34 兩位數的列停在
x=319、字畫到一半，而第 0 列結束在 316。現在以欄位自己的 `cell.cellSize` 量測(P34,2026-09-10)。

## 被壓縮的 Text 保留整行，至少一行

高度 0 的提議從 `NSTextField` 回來時是 1 pt 高，所以與固定大小兄弟並排的說明文字不會畫出，下方的 view 還往上頂到它的位置
(queue 第 17 項:P10、P2、P8、P11、P13、P17、P27、P29、P30、P43、P44、P50、P83)。自 7efbaede(2026-10-16)起，比一行矮的
高度仍給一行;自 9fd3ba85 起，被壓縮的高度只取整行，於是 `truncatesLastVisibleLine` 會讓長儲存格以刪節號結束，而不是畫出半行。
改在 `Sources/SwiftCrossUI/Views/Text.swift`,所有 backend 都受益。

## 表格採用框架給的欄寬

AppKitBackend 從未實作 `setColumnWidths`:欄位保持 AppKit 自己的寬度(P23、P26 約 234 pt),而 `Table` 以自己分配的寬度
(約 392 pt)量儲存格，文字因此跑進下一欄。macOS 11 選用的 inset 樣式還在兩側各加 16 pt。現在欄位採用 Table 的寬度、無間距、
full-width 樣式(9fd3ba85,2026-10-16)。

排序:`sortDescriptorPrototype` 每次 commit 都要設，因為 `setColumnLabels` 會重建欄位;移除欄位會被宣告成排序變更，使 binding
來回震盪，直到防護涵蓋所有由框架引起的變更(P23,2026-09-16)。

## 清單：列、回收與記憶體

- 沒有 identifier 的 `NSTableRowView` 無法回收：捲動時存活的 row view 由 30 增加到 1745;加上 identifier 後是 31
  (352b8c52,2026-09-11)。
- 有了 lazy rows 與 `LazyListRowLifetimes`(row view 的 didAdd/didRemove),10,000 列只花 104 MB,一列的基準是 101 MB
  (原本 423 MB);整份捲完穩定在 134 MB(P57,2026-09-11)。列已消失時 `didRemove` 的列索引是 -1,所以索引在 `didAdd` 時記下。
- 拖動捲軸時 `NSTableView` 會合併排版，只算繪落點：拖動只建了 38 列，滾輪則建了全部 500 列(P57,2026-09-16/17)。
  要量「走過整份清單」,用滾輪。

## 捲軸

AppKit 把 `NSScroller.preferredScrollerStyleDidChangeNotification` 送到 app 自己的通知中心，不是 distributed 那個。接上滑鼠時
啟動的 app 先回報 overlay 捲軸，片刻後才變成 legacy;backend 聽錯了中心，排版時捲軸寬度一直是 0,P8 的標籤因此被 15 pt 的捲軸蓋住
(6f4f94a2,2026-10-19)。

## 啟動時看過的崩潰形態

- `.inspect` overload 直接轉型節點的 widget;`TextField` 變成帶樣式的容器之後，轉型就會 trap。現在改為在子樹中搜尋所要的
  `NSView` 子類別(P4,e7f5eb37,2026-09-17)。
- `ForEach.commit` 的 exclusive access trap:class 屬性上的 `inout` 在 commit 子節點期間一直持有獨占存取，而子節點又重入它。
  `withStackLayoutCache` 把快取複製出來再寫回(P8,e7f5eb37)。是核心程式碼，但在 macOS 上發現。

## 限制

- 決定視窗最小高度的 `Button` 高度 0 提議修正，記在 `window-sizes.md`。
- macOS 27 上 `NSButton` 是 82x24,舊系統是 72x20;寫死控制項尺寸的測試會在系統更新時壞掉(install_tool_mac.zsh)。
