import CGtk
import Foundation
import Gtk

/// The date as three scrollable columns, one per component.
///
/// This is what SwiftUI's `.wheel` style is. Its documentation describes the
/// style as displaying "each component as columns in a scrollable wheel", and on
/// iOS it is a `UIPickerView` -- itself N columns of scrollable text. That
/// matters here because GtkBackend used to decline `.wheel` outright, with a
/// comment saying GTK "has no wheel widget of any kind, and faking one out of a
/// scrolled list would be a worse lie than the fallback". The premise was wrong:
/// a scrolled list per component is not a fake of the wheel, it is the wheel.
/// Neither AppKit nor UIKit has a single "wheel widget" either.
///
/// Two differences from the iOS wheel remain, and both are behavioural rather
/// than a different control:
///
/// - **Selection is by click, not by what is centred.** On iOS you spin and the
///   centred row becomes the value; here the selected row is highlighted and
///   chosen by clicking it. That suits a pointer, and it is why full snapping is
///   not load-bearing: there is never any doubt about which row is selected.
/// - **Only the wheel snaps.** GTK 4 has no scroll-snap, but scrolling moves by
///   the adjustment's step increment, so setting that to one row makes every
///   notch land row-aligned. Dragging the scrollbar or flicking still moves the
///   adjustment directly and can stop between rows.
///
/// 與 iOS 滾輪仍有兩點差異，且兩者都屬於行為差異而非不同的控制項：
///
/// - **以點擊選取，而非以「置中者」選取。** 在 iOS 上你旋轉它，置中的那一列即成為值；此處則是把
///   選取的列高亮顯示，並以點擊來選定。這較適合指標裝置，也正是「完整吸附並非關鍵」的原因：哪一
///   列被選取從來不存在疑義。
/// - **只有滾輪會吸附。** GTK 4 沒有 scroll-snap，但捲動是依 adjustment 的 step increment 移動的，
///   因此把它設為一列的高度，每個刻度都會對齊列。拖動捲軸或觸控滑動仍是直接改變 adjustment，
///   可能停在兩列之間。
///
/// 日期以三個可捲動的欄位呈現，每個組成部分一欄。
///
/// 這正是 SwiftUI `.wheel` 樣式的本質。其文件將該樣式描述為「將每個組成部分顯示為可捲動滾輪中的
/// 欄位」，而在 iOS 上它就是 `UIPickerView`——本身即為 N 欄可捲動文字。這一點在此處很重要，因為
/// GtkBackend 過去直接拒絕 `.wheel`，並附上一則註解說 GTK「沒有任何形式的滾輪 widget，而用捲動
/// 清單假造一個，會是比退回預設更糟的謊言」。該前提是錯的：每個組成部分一個捲動清單並非滾輪的
/// 贗品，它就是滾輪本身。AppKit 與 UIKit 同樣沒有單一的「滾輪 widget」。
///
/// GTK 真正缺少的是**慣性與吸附**——GTK 4 沒有 scroll-snap，因此此處的欄位會停在被放開的位置，而
/// 不會喀噠一聲對齊最近的一列；且選取項是以高亮顯示，而非位於固定的中央橫條之下。那是同一個
/// 控制項上的外觀差異，而非不同的控制項；此處予以記錄而非隱瞞，因為跨 backend 比對截圖的人一定
/// 會看見它。
final class DateWheel: Box {
    /// Reports a date the user picked.
    ///
    /// Not called for a selection this widget made itself while applying a date
    /// from the binding. `selectRow` emits `row-selected` exactly as a click
    /// does, so without the guard every layout pass would report the date it was
    /// just given as though the user had chosen it -- the same trap the calendar
    /// grid documents on `daySelected`.
    ///
    /// 由這個 widget 自己在套用綁定日期時所做的選取，不會觸發回報。`selectRow` 發出的
    /// `row-selected` 與點擊完全相同，因此若無此防護，每一次 layout pass 都會把「剛被賦予的日期」
    /// 當成使用者的選擇回報出去——這與日曆格線在 `daySelected` 上所記錄的是同一個陷阱。
    var onChange: ((Date) -> Void)?

    private var isApplying = false

    private let calendar: Foundation.Calendar
    private let yearRange: ClosedRange<Int>

    private let yearColumn = ListBox()
    private let monthColumn = ListBox()
    private let dayColumn = ListBox()

    /// The scrollers, kept so a selection can be brought into view.
    ///
    /// `gtk_list_box_select_row` selects without scrolling, which on a hundred
    /// years of rows means the wheel opens showing the oldest year while the
    /// selection sits far below. Measured before this was added: the date was
    /// 2025 and the column was displaying 1925.
    ///
    /// 保留各捲動容器，以便將選取項帶入可視範圍。
    ///
    /// `gtk_list_box_select_row` 只選取而不捲動；在長達一百年的列表上，這代表滾輪開啟時顯示的是
    /// 最舊的年份，而選取項遠在其下方。加入此修正前實測：日期為 2025，欄位顯示的卻是 1925。
    private var yearScroller: ScrolledWindow?
    private var monthScroller: ScrolledWindow?
    private var dayScroller: ScrolledWindow?

    /// The viewport height every column is fixed to. Named once so the value
    /// that sizes the scroller and the value that centres a row cannot drift.
    /// 每一欄固定的可視高度。此處只命名一次，使「決定捲動容器尺寸的值」與「用來置中某一列的值」
    /// 不可能各自漂移。
    private static let viewportHeight = 132

    /// The number of days the day column currently offers.
    ///
    /// Rebuilt when the month changes, because February is not January. Held so
    /// that a rebuild can be skipped when the count has not moved, which is most
    /// of the time.
    /// 目前日期欄所提供的天數。因月份改變而重建——二月不同於一月。此處予以保存，使天數未變時可略過
    /// 重建，而多數情況下它都沒變。
    private var dayCount = 0

    init(calendar: Foundation.Calendar, yearRange: ClosedRange<Int>) {
        self.calendar = calendar
        self.yearRange = yearRange
        // The raw constructor, not `Box.init(orientation:spacing:)`, which is a
        // convenience initialiser and so cannot be reached through `super`.
        // TimeRow, the other Box subclass here, does the same.
        // 使用原生建構式而非 `Box.init(orientation:spacing:)`——後者是 convenience initialiser，
        // 無法透過 `super` 呼叫。此處另一個 Box 子類別 TimeRow 的做法亦同。
        super.init(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4))

        var built: [ScrolledWindow] = []
        for (column, width) in [(yearColumn, 72), (monthColumn, 108), (dayColumn, 56)] {
            column.selectionMode = .single

            let scroller = ScrolledWindow()
            scroller.setChild(column)
            scroller.setScrollBarPresence(
                hasVerticalScrollBar: true,
                hasHorizontalScrollBar: false
            )
            // A fixed viewport height is what makes this read as a wheel rather
            // than a long list: several rows visible at once, with the rest
            // reachable by scrolling.
            // 固定的可視高度，正是讓它讀起來像滾輪而非一份長清單的關鍵：一次可見數列，其餘則以
            // 捲動抵達。
            scroller.minimumContentHeight = Self.viewportHeight
            scroller.maximumContentHeight = Self.viewportHeight
            scroller.minimumContentWidth = width
            add(scroller)
            built.append(scroller)
        }
        yearScroller = built[0]
        monthScroller = built[1]
        dayScroller = built[2]

        for year in yearRange {
            yearColumn.append(Label(string: String(year)))
        }
        for name in calendar.monthSymbols {
            monthColumn.append(Label(string: name))
        }

        yearColumn.rowSelected = { [weak self] _, _ in self?.selectionChanged(rebuildDays: true) }
        monthColumn.rowSelected = { [weak self] _, _ in self?.selectionChanged(rebuildDays: true) }
        dayColumn.rowSelected = { [weak self] _, _ in self?.selectionChanged(rebuildDays: false) }
    }

    /// Shows `date`, without reporting it back.
    func apply(_ date: Date) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }

        isApplying = true
        defer { isApplying = false }

        rebuildDayColumn(year: year, month: month)

        if yearRange.contains(year) {
            select(
                year - yearRange.lowerBound,
                in: yearColumn, scroller: yearScroller, of: yearRange.count
            )
        }
        select(
            month - 1,
            in: monthColumn, scroller: monthScroller, of: calendar.monthSymbols.count
        )
        select(day - 1, in: dayColumn, scroller: dayScroller, of: dayCount)
    }

    /// Selects a row and scrolls it to the middle of its column.
    ///
    /// The offset is computed from the row index and a uniform row height rather
    /// than read from the row's allocation, because `apply` runs during a layout
    /// pass and an allocation is not available until after one. Every row here
    /// is a plain label, so they are the same height and the arithmetic holds.
    ///
    /// 選取某一列，並將其捲動至該欄的中央。
    ///
    /// 偏移量由「列索引 × 統一列高」推算，而非讀取該列的 allocation——因為 `apply` 在一次 layout
    /// pass 之中執行，而 allocation 要等到一次 pass 之後才存在。此處每一列都是單純的 label，高度
    /// 一致，因此這個算式成立。
    private func select(
        _ index: Int,
        in column: ListBox,
        scroller: ScrolledWindow?,
        of count: Int
    ) {
        _ = column.selectRow(at: index)

        guard
            count > 0,
            let scroller,
            let adjustment = gtk_scrolled_window_get_vadjustment(scroller.opaquePointer)
        else { return }

        let contentHeight = gtk_adjustment_get_upper(adjustment)
        guard contentHeight > 0 else { return }

        let rowHeight = contentHeight / Double(count)
        guard rowHeight > 0 else { return }

        // Resize the viewport to a whole number of rows, once the row height is
        // known -- it is a theme metric, so it cannot be known before layout.
        //
        // Without this the column is 7.33 rows tall and one edge always shows a
        // sliver of a row, which reads as a rendering fault and also makes
        // snapping impossible to see: a half-row at the bottom looks the same
        // whether the offset is row-aligned or not. Measured at the fixed 132pt:
        // rows came out about 18pt, so the eighth row was always cut.
        //
        // An odd count so the selected row has the same number of neighbours
        // above and below, which is what makes it read as centred.
        //
        // 一旦得知列高，便把可視範圍調整為整數列——列高是主題度量，因此在 layout 之前無從得知。
        //
        // 若無此調整，欄位高度會是 7.33 列，某一邊緣永遠露出半列，看起來像繪製錯誤；同時也讓吸附
        // 變得無從觀察：底部的半列，無論偏移是否對齊列，看起來都一樣。在原本固定的 132pt 下實測：
        // 列高約為 18pt，因此第八列永遠被切掉。
        //
        // 取奇數列，使選取列上下的鄰居數量相同，那正是它讀起來「置中」的原因。
        var visibleRows = Int((Double(Self.viewportHeight) / rowHeight).rounded())
        if visibleRows.isMultiple(of: 2) { visibleRows -= 1 }
        visibleRows = max(3, visibleRows)

        let snappedHeight = Int((Double(visibleRows) * rowHeight).rounded())
        if scroller.minimumContentHeight != snappedHeight {
            scroller.minimumContentHeight = snappedHeight
            scroller.maximumContentHeight = snappedHeight
        }

        // Snapping, such as GTK allows. There is no scroll-snap in GTK 4, but
        // the wheel moves by the adjustment's step increment, so setting that to
        // one row makes every notch land row-aligned by construction -- no
        // timer, no settle detection, nothing to get wrong. A page moves a
        // viewport's worth, still in whole rows.
        //
        // This does not snap a drag: dragging the scrollbar or a touch flick
        // moves the adjustment directly and can stop anywhere. Saying so matters
        // because "we added snapping" would otherwise read as covering both, and
        // the wheel is the input this actually fixes.
        //
        // 在 GTK 允許的範圍內做吸附。GTK 4 沒有 scroll-snap，但滾輪是依 adjustment 的 step
        // increment 移動的，因此把它設為一列的高度，每一個刻度就會在結構上對齊列——不需要計時器、
        // 不需要偵測停止、也就沒有什麼會出錯。翻頁則移動一個可視高度，同樣以整列為單位。
        //
        // 這並不會吸附「拖曳」：拖動捲軸或觸控滑動是直接改變 adjustment 的，可以停在任何位置。
        // 此處明說是必要的，否則「我們加了吸附」會被讀成兩者皆涵蓋，而滾輪才是這項改動真正解決的
        // 輸入方式。
        gtk_adjustment_set_step_increment(adjustment, rowHeight)
        gtk_adjustment_set_page_increment(adjustment, rowHeight * Double(visibleRows))

        // Centre by whole rows, not by pixels: put the selection's row index
        // half the visible count from the top. Centring by pixel arithmetic
        // would leave a fractional offset and undo the alignment this method
        // just set up.
        // 以整列而非像素進行置中：把選取列的索引放在距頂端「可見列數的一半」處。若以像素運算置中，
        // 會留下小數偏移，反而抵銷此方法剛剛建立起來的對齊。
        let topRow = Double(index - visibleRows / 2)
        let highest = max(0, contentHeight - Double(visibleRows) * rowHeight)
        gtk_adjustment_set_value(adjustment, min(max(0, topRow * rowHeight), highest))
    }

    /// Rebuilds the day column when the month's length changes.
    ///
    /// Keyed on the count rather than on the month, so that moving between two
    /// 31-day months does not throw away a selection and re-make identical rows.
    /// 以天數而非月份為判斷依據，如此在兩個 31 天的月份之間移動時，不會丟棄選取狀態、再重建一組
    /// 完全相同的列。
    private func rebuildDayColumn(year: Int, month: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard
            let firstOfMonth = calendar.date(from: components),
            let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else { return }

        guard range.count != dayCount else { return }
        dayCount = range.count

        dayColumn.removeAll()
        for day in range {
            dayColumn.append(Label(string: String(day)))
        }
    }

    private func selectionChanged(rebuildDays: Bool) {
        guard !isApplying else { return }

        guard
            let yearIndex = yearColumn.selectedRowIndex,
            let monthIndex = monthColumn.selectedRowIndex
        else { return }

        let year = yearRange.lowerBound + yearIndex
        let month = monthIndex + 1

        if rebuildDays {
            // Changing the month can shorten the column out from under the
            // selection: picking the 31st and then moving to February must not
            // report the 31st of February. Rebuilding first, then clamping, is
            // what Foundation would do anyway when it normalised the components.
            // 更改月份可能會使欄位在選取項底下變短：先選了 31 日、再切到二月，絕不能回報「二月
            // 31 日」。先重建、再夾限，這也正是 Foundation 在正規化這些 component 時會做的事。
            let previous = dayColumn.selectedRowIndex
            isApplying = true
            rebuildDayColumn(year: year, month: month)
            _ = dayColumn.selectRow(at: min(previous ?? 0, dayCount - 1))
            isApplying = false
        }

        guard let dayIndex = dayColumn.selectedRowIndex else { return }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayIndex + 1
        guard let date = calendar.date(from: components) else { return }

        onChange?(date)
    }
}
