import CGtk
import GtkCHelpers

/// `GtkListView`: a list that builds a widget only for the rows near the
/// viewport, and recycles those widgets as it scrolls.
///
/// **This exists because `GtkListBox` does not virtualize.** `GtkListBox`
/// realizes one widget per model item -- `gtk_list_box_bind_model` builds them
/// all -- so a ten-thousand-row list costs ten thousand rows of widgets AND ten
/// thousand framework view-graph nodes. `GtkListView` is the GTK 4 widget that
/// asks for a row when it needs one, which is what
/// `BackendFeatures.LazyListRows` reaches for. Measured on WinUI, the same
/// reversal took a 10,000-row list from 328 MB to 143 MB.
///
/// **Hand-written rather than generated, and that was checked rather than
/// assumed.** `GtkListView`, `GtkSignalListItemFactory`, `GtkListItem` and
/// `GtkNoSelection` have zero hits in `Sources/Gtk/Generated`. They did not need
/// generating: `Sources/CGtk/header.h` is `#include <gtk/gtk.h>`, the whole
/// header, so every `gtk_list_view_*` function is already visible from Swift.
/// The same situation as `gtk_widget_grab_focus` and
/// `gtk_widget_translate_coordinates` -- a wrapper to write, not a generator to
/// run.
///
/// `GtkListView`:一個只為視port附近的列建立 widget、並在捲動時回收那些 widget 的清單。
///
/// **它之所以存在,是因為 `GtkListBox` 不做虛擬化。** `GtkListBox` 為模型中的每一項實體化一個 widget
/// ——`gtk_list_box_bind_model` 會把它們全部建出來——因此一份一萬列的清單,代價是一萬列的 widget
/// **加上**一萬個框架的 view-graph 節點。`GtkListView` 才是 GTK 4 中「需要某一列時才去要它」的那個
/// widget,而那正是 `BackendFeatures.LazyListRows` 所要取用的東西。在 WinUI 上量過,同一個方向反轉
/// 讓一份一萬列的清單從 328 MB 降到 143 MB。
///
/// **手寫而非產生,而這是查證過的、不是假設的。** `GtkListView`、`GtkSignalListItemFactory`、
/// `GtkListItem` 與 `GtkNoSelection` 在 `Sources/Gtk/Generated` 中零命中。它們不需要被產生:
/// `Sources/CGtk/header.h` 就是 `#include <gtk/gtk.h>`——整份標頭——因此每一個 `gtk_list_view_*`
/// 函式從 Swift 都已經看得見。這與 `gtk_widget_grab_focus` 及
/// `gtk_widget_translate_coordinates` 是同一個情況:要寫的是 wrapper,不是要跑產生器。
open class ListView: Widget {
    /// Called with a row index when that row is about to be shown. Returns the
    /// row's widget, or `nil` when the index is out of range -- which happens
    /// legitimately while a count is shrinking.
    /// 當某一列即將被顯示時,以該列索引呼叫。回傳該列的 widget;索引超出範圍時回傳 `nil`——那在列數
    /// 正在縮減時是**正當**會發生的。
    public var rowProvider: ((Int) -> Widget?)?

    /// Called when the user selects a row.
    /// 使用者選取某一列時呼叫。
    public var onSelectionChange: ((Int?) -> Void)?
    public var onRowReleased: ((Int) -> Void)?

    /// The rows currently bound to a list item, keyed by position.
    ///
    /// **Held so the widgets are not deallocated while GTK still displays
    /// them.** `gtk_list_item_set_child` does take a reference, but the Swift
    /// `Widget` wrapper around it is a separate object -- and nothing else here
    /// holds that wrapper. Without this table the wrapper would be released at
    /// the end of `bind`, and the next call into it would touch freed memory.
    ///
    /// 目前被綁定到某個 list item 上的那些列,以位置為鍵。
    ///
    /// **持有它們,是為了讓 GTK 仍在顯示那些 widget 時它們不會被釋放。**
    /// `gtk_list_item_set_child` 確實會取得一個 reference,但包在它外面的 Swift `Widget` wrapper 是
    /// 另一個物件——而此處沒有別的東西持有那個 wrapper。少了這張表,該 wrapper 會在 `bind` 結束時被
    /// 釋放,而下一次進入它就會碰到已釋放的記憶體。
    private var boundRows: [Int: Widget] = [:]
    private var boundItems: [Int: OpaquePointer] = [:]
    private var isUpdatingSelection = false

    public func refreshBoundRows() {
        for (position, item) in Array(boundItems) {
            guard let row = rowProvider?(position) else { continue }
            if boundRows[position] !== row {
                boundRows[position]?.parentWidget = nil
                gtk_list_item_set_child(item, row.widgetPointer)
                boundRows[position] = row
                row.parentWidget = self
            }
        }
    }

    /// The selection model, kept because the list view's own reference to it is
    /// not reachable through a typed accessor here.
    /// 選取模型;之所以留著,是因為此處沒有具型別的存取器可以取回 list view 自己持有的那個 reference。
    private var selectionModel: OpaquePointer?

    private var factory: OpaquePointer?
    private var setupHandlerID: gulong?
    private var bindHandlerID: gulong?
    private var unbindHandlerID: gulong?
    private var selectionHandlerID: gulong?

    /// Creates an empty list view. Call ``setRowCount(_:)`` to give it rows.
    /// 建立一個空的 list view。呼叫 ``setRowCount(_:)`` 來給它列。
    public convenience init() {
        // `gtk_string_list_new(nil)` is an empty GListModel of strings, used
        // here purely as a COUNTER. The strings are never read: a row's content
        // comes from `rowProvider`, keyed by `gtk_list_item_get_position`. A
        // model is still required, because the list view sizes its scrollbar
        // from the item count without building anything -- which is the whole
        // point of the exercise.
        //
        // A string per row rather than a custom GListModel subclass: subclassing
        // GObject from Swift means hand-writing a GType registration, and the
        // thing being avoided is 31 KB a row, not the handful of bytes an empty
        // string costs. WinUI's half of this used boxed Int32 placeholders for
        // exactly the same reason.
        //
        // `gtk_string_list_new(nil)` 是一個空的、由字串組成的 GListModel,此處純粹當**計數器**用。
        // 那些字串永遠不會被讀取:一列的內容來自 `rowProvider`,以 `gtk_list_item_get_position` 為鍵。
        // 但模型仍是必要的,因為 list view 會在不建立任何東西的情況下,依項目數為捲軸定尺寸——而那正是
        // 這整件事的全部意義。
        //
        // 每列一個字串、而非自訂一個 GListModel 子類別:從 Swift 繼承 GObject 意謂著要手寫一份 GType
        // 註冊,而此處要避免的是每列 31 KB、不是一個空字串那幾個位元組。WinUI 那一半用 boxed Int32
        // 佔位,理由完全相同。
        // **Every GTK object here imports as `OpaquePointer`, not as a typed
        // struct, so none of these calls needs a cast.** That was measured, not
        // assumed: a probe file assigning each call's result to `Int` made the
        // compiler name the real types -- `gtk_string_list_new`,
        // `gtk_single_selection_new` and `gtk_signal_list_item_factory_new` all
        // return `OpaquePointer?`, and only `gtk_list_view_new` returns
        // `UnsafeMutablePointer<GtkWidget>?`. The first version of this file
        // wrote `assumingMemoryBound(to: GtkSelectionModel.self)` and similar
        // throughout and produced 28 errors, all of them that one mistake.
        //
        // **此處每一個 GTK 物件都是以 `OpaquePointer` 匯入的、而非具型別的 struct,因此這些呼叫
        // 一個 cast 都不需要。** 這是量出來的、不是假設的:用一個把每個呼叫結果指派給 `Int` 的探針檔,
        // 讓編譯器把真正的型別講出來——`gtk_string_list_new`、`gtk_single_selection_new` 與
        // `gtk_signal_list_item_factory_new` 全都回傳 `OpaquePointer?`,只有 `gtk_list_view_new`
        // 回傳 `UnsafeMutablePointer<GtkWidget>?`。本檔的第一版通篇寫著
        // `assumingMemoryBound(to: GtkSelectionModel.self)` 之類的東西,產生了 28 個錯誤,而它們
        // 全部都是同一個錯。
        let model = gtk_string_list_new(nil)
        // `gtk_single_selection_new` is (transfer full) on its argument -- read
        // from gtk4-source, not from memory -- so the string list's reference is
        // consumed here and must not be unreffed.
        // `gtk_single_selection_new` 對其引數是 (transfer full)——這是**讀** gtk4 原始碼得知的,
        // 不是憑記憶——因此那個 string list 的 reference 在此被吃掉,不可以再 unref。
        let selection = gtk_single_selection_new(model)
        gtk_single_selection_set_autoselect(selection, 0)
        gtk_single_selection_set_can_unselect(selection, 1)
        let factory = gtk_signal_list_item_factory_new()

        // `gtk_list_view_new` is (transfer full) on BOTH arguments, and its own
        // documentation says so in as many words: "The function takes ownership
        // of the arguments". So neither is unreffed here either.
        // `gtk_list_view_new` 對**兩個**引數都是 (transfer full),而它自己的文件就是這樣寫的:
        // 「The function takes ownership of the arguments」。因此此處兩者也都不做 unref。
        self.init(gtk_list_view_new(selection, factory))

        self.selectionModel = selection
        self.factory = factory
    }

    /// Sets how many rows the list has, without building any of them.
    ///
    /// The count is applied by splicing the placeholder model, so the scrollbar
    /// resizes and GTK realizes containers for the visible rows only.
    ///
    /// 設定這份清單有幾列,過程中不建立其中任何一列。
    ///
    /// 列數是透過對佔位模型做 splice 來套用的,於是捲軸會重新定尺寸,而 GTK 只會為可見的那些列實體化容器。
    public func setRowCount(_ count: Int) {
        precondition(count >= 0)
        isUpdatingSelection = true
        defer { isUpdatingSelection = false }
        guard let selectionModel else { return }
        guard let list = gtk_single_selection_get_model(selectionModel) else { return }
        let existing = Int(g_list_model_get_n_items(list))

        // Rows that no longer exist must lose their held widget too, or the
        // table grows without bound as a list shrinks and regrows.
        // 已不存在的列,其被持有的 widget 也必須釋放,否則當一份清單縮小又長回來時,這張表會無限成長。

        if count > existing {
            "".withCString { empty in
                let additions = Array<UnsafePointer<CChar>?>(
                    repeating: empty, count: count - existing
                ) + [nil]
                additions.withUnsafeBufferPointer { buffer in
                    gtk_string_list_splice(list, guint(existing), 0, buffer.baseAddress)
                }
            }
        } else if count < existing {
            gtk_string_list_splice(list, guint(count), guint(existing - count), nil)
        }
    }

    /// The currently selected row, or `nil`.
    /// 目前被選取的列,或 `nil`。
    public var selectedIndex: Int? {
        get {
            guard let selectionModel else { return nil }
            let position = gtk_single_selection_get_selected(selectionModel)
            return position == GTK_INVALID_LIST_POSITION ? nil : Int(position)
        }
        set {
            guard let selectionModel else { return }
            isUpdatingSelection = true
            defer { isUpdatingSelection = false }
            gtk_single_selection_set_selected(
                selectionModel,
                newValue.map(guint.init) ?? GTK_INVALID_LIST_POSITION
            )
        }
    }

    open override func registerSignals() {
        super.registerSignals()
        // Parent changes register signals again; these handlers are owned here.
        guard bindHandlerID == nil else { return }
        guard let factory else { return }

        // Unretained user data: the list view owns the factory, and this wrapper
        // owns the list view, so the wrapper outlives every callback -- and the
        // handler ids are disconnected in deinit below, which closes the window
        // where a factory could outlive it.
        // 不保留的 user data:list view 擁有那個 factory,而本 wrapper 擁有那個 list view,因此 wrapper
        // 活得比每一次 callback 都久——而下方的 deinit 會斷開這些 handler id,關掉「factory 可能活得比
        // wrapper 久」的那個時間窗。
        let data = Unmanaged.passUnretained(self).toOpaque()

        // `setup` creates the reusable container. It runs once per RECYCLED
        // widget, not once per row -- that distinction is the feature.
        // `setup` 建立可重用的容器。它是每個**被回收的 widget** 跑一次、而不是每一列跑一次——那個區別
        // 正是這項功能本身。
        let setup: @convention(c) (
            UnsafeMutableRawPointer?, OpaquePointer?, UnsafeMutableRawPointer?
        ) -> Void = { _, listItem, _ in
            guard let listItem else { return }
            gtk_list_item_set_child(listItem, nil)
        }
        setupHandlerID = g_signal_connect_data(
            UnsafeMutableRawPointer(factory),
            "setup",
            gCallback(setup),
            data,
            nil,
            SHIM_G_CONNECT_DEFAULT
        )

        // `bind` is the reversal: GTK asks US for the row at this position.
        // `bind` 就是那個反轉:GTK 向**我們**索取這個位置上的列。
        let bind: @convention(c) (
            UnsafeMutableRawPointer?, OpaquePointer?, UnsafeMutableRawPointer?
        ) -> Void = { _, listItem, data in
            guard let listItem, let data else { return }
            let view = Unmanaged<ListView>.fromOpaque(data).takeUnretainedValue()
            let position = Int(gtk_list_item_get_position(listItem))
            guard let row = view.rowProvider?(position) else {
                gtk_list_item_set_child(listItem, nil)
                return
            }
            view.boundRows[position] = row
            view.boundItems[position] = listItem
            gtk_list_item_set_child(listItem, row.widgetPointer)
            row.parentWidget = view
        }
        bindHandlerID = g_signal_connect_data(
            UnsafeMutableRawPointer(factory),
            "bind",
            gCallback(bind),
            data,
            nil,
            SHIM_G_CONNECT_DEFAULT
        )

        // `unbind` is the half that is easy to forget, and forgetting it turns
        // this into a slower version of the eager path: rows would be built on
        // demand and then kept for ever.
        // `unbind` 是那一半容易被忘記的;而忘記它,會把這件事變成 eager 路徑的一個較慢版本:列會依需求
        // 建立,然後被永遠留著。
        let unbind: @convention(c) (
            UnsafeMutableRawPointer?, OpaquePointer?, UnsafeMutableRawPointer?
        ) -> Void = { _, listItem, data in
            guard let listItem, let data else { return }
            let view = Unmanaged<ListView>.fromOpaque(data).takeUnretainedValue()
            let position = Int(gtk_list_item_get_position(listItem))
            gtk_list_item_set_child(listItem, nil)
            view.boundRows[position]?.parentWidget = nil
            view.boundRows[position] = nil
            view.boundItems[position] = nil
            view.onRowReleased?(position)
        }
        unbindHandlerID = g_signal_connect_data(
            UnsafeMutableRawPointer(factory),
            "unbind",
            gCallback(unbind),
            data,
            nil,
            SHIM_G_CONNECT_DEFAULT
        )

        // Selection comes from the model's `selection-changed`, not from a row
        // widget's click. On GtkListBox the backend listened to `row-selected`;
        // there are no persistent rows here to listen to.
        // 選取來自模型的 `selection-changed`,而不是某個列 widget 的點擊。在 GtkListBox 上,backend 監聽
        // 的是 `row-selected`;而此處並沒有持久存在的列可供監聽。
        if let selectionModel {
            let selectionChanged: @convention(c) (
                UnsafeMutableRawPointer?, guint, guint, UnsafeMutableRawPointer?
            ) -> Void = { _, _, _, data in
                guard let data else { return }
                let view = Unmanaged<ListView>.fromOpaque(data).takeUnretainedValue()
                guard !view.isUpdatingSelection else { return }
                view.onSelectionChange?(view.selectedIndex)
            }
            selectionHandlerID = g_signal_connect_data(
                UnsafeMutableRawPointer(selectionModel),
                "selection-changed",
                gCallback(selectionChanged),
                data,
                nil,
                SHIM_G_CONNECT_DEFAULT
            )
        }
    }

    deinit {
        // Disconnected by hand: these were connected with
        // `g_signal_connect_data` rather than through GObject's `addSignal`, so
        // they are not in the set it disconnects for us. A callback arriving
        // after this object is gone would call `takeUnretainedValue` on freed
        // memory -- the same hazard DropTarget records.
        // 手動斷開:這些是以 `g_signal_connect_data` 連接的、而非經由 GObject 的 `addSignal`,因此它們
        // 不在它替我們斷開的那個集合裡。一個在本物件消失之後才抵達的 callback,會對已釋放的記憶體呼叫
        // `takeUnretainedValue`——與 DropTarget 所記載的是同一個危險。
        if let factory {
            for id in [setupHandlerID, bindHandlerID, unbindHandlerID].compactMap({ $0 }) {
                g_signal_handler_disconnect(UnsafeMutableRawPointer(factory), id)
            }
        }
        if let selectionModel, let selectionHandlerID {
            g_signal_handler_disconnect(UnsafeMutableRawPointer(selectionModel), selectionHandlerID)
        }
    }
}
