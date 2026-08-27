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
/// What GTK genuinely lacks is the *momentum and snapping* -- there is no
/// scroll-snap in GTK 4, so a column here settles wherever it is left rather
/// than clicking to the nearest row, and the selected row is highlighted rather
/// than sitting under a fixed centre bar. That is a cosmetic difference in the
/// same widget, not a different control, and it is recorded rather than hidden
/// because someone comparing screenshots across backends will see it.
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
        let centred = (Double(index) + 0.5) * rowHeight - Double(Self.viewportHeight) / 2
        let highest = max(0, contentHeight - Double(Self.viewportHeight))
        gtk_adjustment_set_value(adjustment, min(max(0, centred), highest))
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
