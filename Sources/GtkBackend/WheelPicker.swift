import CGtk
import Gtk

/// `PickerStyle.wheel` on GTK: a short scrolling list with one row selected.
///
/// GTK 4 has no wheel widget, so this is the shape AppKitBackend's
/// `WheelPicker` takes on macOS for the same reason: a list in a scrolled
/// window, five rows tall, single selection, scrolled so the selection is in
/// view. Until 2026-10-06 `createPicker(style: .wheel)` hit `fatalError`, and
/// `.wheel` was missing from `supportedPickerStyles`.
///
/// GTK 上的 `PickerStyle.wheel`:一個短的捲動清單，選中其中一列。GTK 4 沒有 wheel 元件，所以採用
/// AppKitBackend 在 macOS 上基於同樣理由所用的形狀：捲動視窗中的清單，五列高、單選，並捲到讓選取項可見。
/// 2026-10-06 之前 `createPicker(style: .wheel)` 會撞上 `fatalError`,`supportedPickerStyles` 也沒有 `.wheel`。
final class WheelPicker: Box {
    static let visibleRows = 5
    static let rowHeight = 30

    var onChange: ((Int?) -> Void)?

    private let list = ListBox()
    private let scroller = ScrolledWindow()
    private var options: [String] = []
    private var isApplyingSelection = false

    init() {
        super.init(gtk_box_new(GTK_ORIENTATION_VERTICAL, 0))
        list.selectionMode = .single
        scroller.setChild(list)
        add(scroller)
        scroller.setScrollBarPresence(hasVerticalScrollBar: true, hasHorizontalScrollBar: false)
        let height = Self.visibleRows * Self.rowHeight
        scroller.minimumContentHeight = height
        scroller.maximumContentHeight = height
        scroller.propagateNaturalWidth = true
        gtk_widget_add_css_class(scroller.widgetPointer, "frame")
        list.rowSelected = { [weak self] list, _ in
            guard let self, !self.isApplyingSelection else { return }
            self.onChange?(list.selectedRowIndex)
        }
    }

    func update(options: [String]) {
        guard options != self.options else { return }
        let selected = list.selectedRowIndex
        self.options = options
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        list.removeAll()
        for option in options {
            let label = Label(string: option)
            label.setSizeRequest(width: -1, height: Self.rowHeight)
            gtk_widget_set_margin_start(label.widgetPointer, 12)
            gtk_widget_set_margin_end(label.widgetPointer, 12)
            list.append(label)
        }
        if let selected, selected < options.count {
            list.selectRow(at: selected)
        }
    }

    func setSelectedIndex(to index: Int?) {
        guard index != list.selectedRowIndex else { return }
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        if let index, list.selectRow(at: index) {
            // Scrolled into view: a wheel shows its value.
            // 捲到可見範圍：wheel 會顯示自己的值。
            if let row = gtk_list_box_get_row_at_index(list.opaquePointer, gint(index)) {
                gtk_widget_grab_focus(UnsafeMutablePointer<GtkWidget>(OpaquePointer(row)))
            }
        } else {
            list.unselectAll()
        }
    }
}
