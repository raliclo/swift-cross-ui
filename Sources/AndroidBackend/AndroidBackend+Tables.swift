import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// `Table` on Android.
///
/// The geometry is in `TableContainer.kt`, including why this is a grid of
/// equal columns rather than Android's own `TableLayout`.
///
/// Header cells are made here with the same `createTextView` and
/// `updateTextView` every other piece of text in this backend goes through, so
/// a table's headings pick up the font, the colour scheme and the text style
/// from the environment without this file knowing anything about any of them.
///
/// Android 上的 `Table`。
///
/// 幾何計算位於 `TableContainer.kt`，其中也說明了為何此處採用等寬格線，而非 Android 自己的
/// `TableLayout`。
///
/// header 的 cell 在此處是以 `createTextView` 與 `updateTextView` 建立的——與本 backend 中其他
/// 每一段文字所走的路徑相同——因此表格的標題會從 environment 取得字型、配色與文字樣式，而本檔
/// 不需要知道其中任何一項。
extension AndroidBackend: BackendFeatures.Tables {
    // -1 for both, as UIKitBackend: `Table.swift` reads them through a `max`
    // against the measured height, so a row is as tall as its tallest cell.
    // The desktop backends use 20 and 4; with those the phone rows came out
    // 32 dp here against 22 pt on iOS, and P23 showed half the rows iOS does
    // (2026-10-10).
    //
    // 兩者都是 -1,與 UIKitBackend 相同:`Table.swift` 透過與量測高度取 `max` 來讀它們，所以一列的高度就是
    // 它最高的 cell。桌面 backend 用 20 與 4;用那兩個值時，這裡的手機列高是 32 dp,iOS 是 22 pt,P23 只顯示了
    // iOS 一半的列數(2026-10-10)。
    public var defaultTableRowContentHeight: Int { -1 }
    public var defaultTableCellVerticalPadding: Int { -1 }

    public func createTable() -> Widget {
        let table = TableContainer(Self.activity, environment: Self.env)
        let density = Self.activity.getResources().getDisplayMetrics().density
        table.setHeaderHeight(Int32(Float(Self.headerHeightInPoints) * density))
        return table.as(AndroidKit.View.self)!
    }

    /// UIKitBackend's `TableWidget` uses the same 24, so the two phone backends
    /// put the first row in the same place.
    /// UIKitBackend 的 `TableWidget` 用的也是 24，因此兩個手機 backend 會把第一列放在同一個位置。
    private static var headerHeightInPoints: Int { 24 }

    public func setRowCount(ofTable table: Widget, to rows: Int) {
        // Nothing to do: `setCells` carries the rows and their heights, and it
        // is always called after this. UIKitBackend's is empty for the same
        // reason. Written out rather than left to a default, because an empty
        // body that is correct and an empty body that is a gap look identical.
        //
        // 無事可做：`setCells` 會帶著各列及其高度，而它總是在此之後被呼叫。UIKitBackend 的實作為空，
        // 理由相同。此處明寫而不留給預設實作，因為「正確的空實作」與「作為缺口的空實作」看起來
        // 完全一樣。
        _ = (table, rows)
    }

    public func setColumnLabels(
        ofTable table: Widget,
        to labels: [String],
        environment: EnvironmentValues
    ) {
        let table = table.as(TableContainer.self)!
        table.clearHeaders()
        for label in labels {
            let heading = createTextView()
            updateTextView(heading, content: label, environment: environment)
            table.addHeader(heading)
        }
    }

    public func setCells(
        ofTable table: Widget,
        to cells: [Widget],
        withRowHeights rowHeights: [Int]
    ) {
        let table = table.as(TableContainer.self)!
        let density = Self.activity.getResources().getDisplayMetrics().density
        table.clearCells()
        for height in rowHeights {
            table.addRowHeight(Int32(Float(height) * density))
        }
        for cell in cells {
            table.addCell(cell)
        }
    }

    public func setTextSelectability(ofTable table: Widget, to isSelectable: Bool) {
        // Every cell that draws text does so through a `TextView`, and
        // `setTextIsSelectable` is exactly this feature: it gives the view a
        // caret and a selection handle set and makes it focusable, which is
        // what the protocol's note says selection costs.
        //
        // Applied to the cells, not to the table, because what is selectable is
        // the text a cell draws rather than the cell as an object. A cell whose
        // widget is not a `TextView` -- an image, a nested stack -- has no text
        // to select and is skipped rather than being made focusable for
        // nothing.
        //
        // 每一個繪製文字的 cell 都是透過 `TextView` 進行的，而 `setTextIsSelectable` 正是這項功能：
        // 它會給該 view 一個游標與一組選取控制點，並使其可取得焦點——那正是 protocol 的說明中所指
        // 「選取所付出的代價」。
        //
        // 套用於各個 cell 而非整張表格，因為可被選取的是 cell 所繪製的文字，而不是作為物件的 cell。
        // 若某個 cell 的 widget 不是 `TextView`——例如一張圖、一個巢狀堆疊——它沒有文字可供選取，
        // 因此會被略過，而不是白白變成可取得焦點。
        let container = table.as(AndroidKit.ViewGroup.self)!
        for index in 0..<Int(container.getChildCount()) {
            guard let child = container.getChildAt(Int32(index)),
                  let textView = child.as(AndroidKit.TextView.self)
            else { continue }
            textView.setTextIsSelectable(isSelectable)
        }
    }
}
