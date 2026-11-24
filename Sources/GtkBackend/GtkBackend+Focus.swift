import CGtk
import GtkCHelpers
import Gtk
import SwiftCrossUI

extension GtkBackend: BackendFeatures.FocusableViews {
    /// `gtk_widget_grab_focus`, which returns whether the widget took it.
    ///
    /// **`can-focus` is set first, and that is not a convenience.** GTK refuses
    /// focus to a widget whose `can-focus` is false, and most of what this
    /// backend hands out is a container -- a `Box` or a `ScrolledWindow` wrapper
    /// around the real control. Granting it here makes the answer this protocol
    /// promises, "did it take the focus", come from GTK rather than from a
    /// property nobody set.
    ///
    /// The return value is used rather than assumed. AppKit's version checks
    /// `acceptsFirstResponder` before asking, for the same reason: a wrapper
    /// that cannot focus should report `false`, not a plausible `true`.
    ///
    /// `gtk_widget_grab_focus`——它會回傳該 widget 是否接受了焦點。
    ///
    /// **此處先設定 `can-focus`,而那不是為了方便。** GTK 會拒絕把焦點給 `can-focus` 為 false 的
    /// widget,而本 backend 交出去的東西多半是一個**容器**——包在真正控制項外面的 `Box` 或
    /// `ScrolledWindow`。在此處授予它,才讓本協定所承諾的那個答案(「它有沒有接受焦點」)出自 GTK,
    /// 而不是出自一個沒有人設定過的屬性。
    ///
    /// 回傳值是被**使用**的,不是被假設的。AppKit 版本在詢問之前先檢查 `acceptsFirstResponder`,
    /// 理由相同:一個無法取得焦點的 wrapper 應該回報 `false`,而不是一個看似合理的 `true`。
    @discardableResult
    public func focus(_ widget: Widget) -> Bool {
        let pointer = widget.widgetPointer

        // **An insensitive widget is refused, and the guard is here because
        // granting `can-focus` below would otherwise OVERRIDE GTK's own
        // refusal.** Measured by P70 on 2026-09-16: without it, "ask both for
        // focus" reported `DISABLED FOCUS reported true` -- this backend handed
        // the keyboard to a disabled button and told `@FocusState` it had
        // worked. AppKit refuses the same case by checking
        // `acceptsFirstResponder` first; `sensitive` is GTK's spelling of it.
        //
        // Setting `can-focus` unconditionally, below, is what makes a container
        // focusable, which this needs, and it is also what would silence the one
        // refusal the protocol has to get right.
        //
        // **不敏感(insensitive)的 widget 會被拒絕,而這道防護放在此處,是因為下方那行授予
        // `can-focus` 的程式碼否則會覆寫掉 GTK 自己的拒絕。** 2026-09-16 由 P70 量到:少了它,
        // 「ask both for focus」回報 `DISABLED FOCUS reported true`——本 backend 把鍵盤交給了一個
        // 被停用的按鈕,並告訴 `@FocusState` 這件事成功了。AppKit 以先檢查 `acceptsFirstResponder`
        // 拒絕同一個情形;而 `sensitive` 就是 GTK 對它的寫法。
        //
        // 下方無條件設定 `can-focus` 是「讓容器可以取得焦點」所必需的——而它同時也會讓本協定唯一
        // 必須答對的那次拒絕失聲。
        guard gtk_widget_get_sensitive(pointer) != 0 else { return false }

        // Raw `gboolean` rather than the `toGBoolean()` / `toBool()` helpers:
        // those are internal to the Gtk module and not visible from GtkBackend.
        // 使用原生的 `gboolean`,而非 `toGBoolean()` / `toBool()` 兩個輔助函式:它們是 Gtk 模組的
        // internal,從 GtkBackend 看不到。
        gtk_widget_set_can_focus(pointer, 1)
        if GtkBackend.grabFocus(in: pointer) { return true }
        // Refused. Before the window is mapped that is GTK, not the widget:
        // the request is applied when the window maps (see `focusWhenMapped`),
        // and `false` is still the honest answer now.
        // 被拒絕。視窗 map 之前，那是 GTK 而不是 widget 的拒絕：要求在視窗 map 時套用(見 `focusWhenMapped`),
        // 而此刻誠實的答案仍是 `false`。
        if let window = windowRoot(of: widget) {
            let windowWidget = UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWidget.self)
            if gtk_widget_get_mapped(windowWidget) == 0 {
                focusWhenMapped(widget, window: windowWidget)
            }
        }
        return false
    }

    /// Moves the focus off this widget by clearing it on the window.
    ///
    /// **GTK has no "unfocus" for a widget**, only `gtk_window_set_focus` with
    /// NULL, which is a statement about the WINDOW. So this is guarded on
    /// ``isFocused(_:)``: without that, a layout pass calling `unfocus` on a
    /// widget that never had the focus would clear it from whatever did.
    ///
    /// The same shape as the AppKit and WinUI versions, which hand the focus
    /// back to the window and to the root element respectively -- in all three
    /// the focus is a position rather than a flag, and removing it from here
    /// means putting it somewhere harmless.
    ///
    /// 把焦點移出這個 widget,做法是在**視窗**上清掉它。
    ///
    /// **GTK 沒有針對 widget 的「取消聚焦」**,只有傳 NULL 的 `gtk_window_set_focus`,而那是一句
    /// 關於**視窗**的陳述。因此此處以 ``isFocused(_:)`` 作為前置條件:少了它,一次對「本來就沒有
    /// 焦點的 widget」呼叫 `unfocus` 的 layout pass,會把焦點從真正持有它的東西上清掉。
    ///
    /// 這與 AppKit、WinUI 兩個版本是同一個形狀(它們分別把焦點交還給視窗與 root 元素)——在三者之中,
    /// 焦點都是一個**位置**而非旗標,而「把它從這裡移走」意謂著「把它放到某個無害的地方」。
    public func unfocus(_ widget: Widget) {
        guard isFocused(widget), let window = windowRoot(of: widget) else { return }
        gtk_window_set_focus(window, nil)
    }

    /// Whether this widget, or anything inside it, holds the focus.
    ///
    /// **Descendants count.** A `TextField` on this backend is a `GtkEntry`
    /// inside a wrapper, and it is the entry GTK focuses; comparing only the
    /// widget itself would report `false` for a field being typed into.
    /// `gtk_widget_has_focus` answers for one widget, so the window's current
    /// focus widget is walked up instead.
    ///
    /// 這個 widget——或它內部的任何東西——是否持有焦點。
    ///
    /// **後代也算。** 本 backend 的 `TextField` 是一個包在 wrapper 裡的 `GtkEntry`,而 GTK 聚焦的是
    /// 那個 entry;若只比對 widget 自身,對於正在被輸入的欄位會回報 `false`。
    /// `gtk_widget_has_focus` 只回答單一 widget,因此此處改為從視窗當前的焦點 widget 往上走。
    public func isFocused(_ widget: Widget) -> Bool {
        guard let window = windowRoot(of: widget) else { return false }
        guard var current = gtk_window_get_focus(window) else { return false }
        let target = widget.widgetPointer
        while true {
            if current == target { return true }
            guard let parent = gtk_widget_get_parent(current) else { return false }
            current = parent
        }
    }

    /// Reports focus in and out through a `GtkEventControllerFocus`.
    ///
    /// **`enter` and `leave` on the controller, not `notify::has-focus` on the
    /// widget.** The controller reports focus entering the widget OR any of its
    /// children, which is what makes it agree with ``isFocused(_:)`` above; the
    /// property is about the one widget and would stay false while the entry
    /// inside it is being typed into.
    ///
    /// The controller is installed at most once per widget. This is called from
    /// the modifier's commit, so it runs on every frame -- adding a controller each
    /// time is the defect measured on this backend's slider, where one press
    /// reported `began=5`, and the one the gesture code was restructured to
    /// avoid. Only the handler is replaced.
    ///
    /// 透過 `GtkEventControllerFocus` 回報焦點的進出。
    ///
    /// **用控制器的 `enter` 與 `leave`,而不是 widget 的 `notify::has-focus`。** 該控制器回報的是
    /// 「焦點進入該 widget **或其任一子節點**」,而那正是它與上方 ``isFocused(_:)`` 一致的原因;
    /// 那個屬性談的是單一 widget,在其內部的 entry 正被輸入時它會維持 false。
    ///
    /// 控制器每個 widget 最多安裝一次。本方法由 modifier 的 commit 呼叫,因此每一幀都會跑——每次都新增
    /// 一個控制器,正是本 backend slider 上量到的那個缺陷(按一次回報 `began=5`),也正是手勢程式碼
    /// 被重構所要避開的那一個。此處只替換 handler。
    public func setFocusChangeHandler(
        ofWidget widget: Widget,
        to handler: @escaping (Bool) -> Void
    ) {
        let key = ObjectIdentifier(widget)
        if let watch = focusWatches[key], watch.widget === widget {
            watch.handler = handler
            return
        }
        // A new widget, or a new one at a dead one's address: dead entries go,
        // as WinUIBackend+Focus.swift drops them.
        // 新的 widget,或位於已死 widget 位址上的新 widget:清掉已死的項目，與 WinUIBackend+Focus.swift 相同。
        focusWatches = focusWatches.filter { $0.value.widget != nil }
        let watch = FocusWatch(widget: widget, handler: handler)
        focusWatches[key] = watch

        let controller = EventControllerFocus()
        controller.enter = { [weak watch] _ in watch?.report(true) }
        controller.leave = { [weak watch] _ in watch?.report(false) }
        widget.addEventController(controller)
    }

    /// The `GtkWindow` this widget lives in, or nil before it is in a tree.
    ///
    /// `gtk_widget_get_root` returns a `GtkRoot`, which is an interface rather
    /// than a type; every root in this backend is a `GtkWindow`, and the cast is
    /// the same widening the rest of this tree's hand-written bindings make.
    ///
    /// 這個 widget 所在的 `GtkWindow`;若它尚未進入樹中則為 nil。
    ///
    /// `gtk_widget_get_root` 回傳的是 `GtkRoot`,那是一個**介面**而非型別;在本 backend 中每一個 root
    /// 都是 `GtkWindow`,而此處的轉型與本樹其餘手寫綁定所做的是同一種放寬。
    private func windowRoot(of widget: Widget) -> UnsafeMutablePointer<GtkWindow>? {
        guard let root = gtk_widget_get_root(widget.widgetPointer) else { return nil }
        // Rebound rather than cast through `OpaquePointer`: `gtk_window_set_focus`
        // and `gtk_window_get_focus` both take `UnsafeMutablePointer<GtkWindow>`
        // here, unlike the list-view calls that import as `OpaquePointer`. The
        // importer is not uniform about this, so the type is read off the error
        // message rather than assumed from a neighbouring file.
        // 以重新繫結而非經由 `OpaquePointer` 轉型:此處的 `gtk_window_set_focus` 與
        // `gtk_window_get_focus` 收的都是 `UnsafeMutablePointer<GtkWindow>`,與那些匯入為
        // `OpaquePointer` 的 list-view 呼叫不同。匯入器在這件事上並不一致,因此型別是**從錯誤訊息讀來**
        // 的,而不是從隔壁檔案推定的。
        return UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self)
    }

    /// One watched widget: the widget, held weakly, and its current handler.
    ///
    /// **The widget is held so its identity can be checked, not only its
    /// address.** The table used to be keyed by `ObjectIdentifier` alone, and
    /// an identifier outlives the object it was taken from: a widget freed and
    /// replaced by a new one at the same address found its key already marked
    /// "controller installed", so the new widget never got a controller and
    /// its focus was never reported. The controller's closures hold the watch
    /// weakly, so a GtkWidget that outlives its Swift wrapper reports into
    /// nothing rather than into the next widget's handler.
    ///
    /// 一個被觀察的 widget:弱參照的 widget 本身，以及它目前的 handler。
    ///
    /// **保存 widget 是為了比對身分，而不只是位址。** 這張表原本只以 `ObjectIdentifier` 為鍵，而識別碼
    /// 活得比它所取自的物件久：一個被釋放、又被同一位址上的新 widget 取代的 widget,會發現自己的鍵早已
    /// 標為「已安裝控制器」,於是新 widget 永遠沒有控制器，它的焦點也永遠不會被回報。控制器的 closure
    /// 以弱參照持有 watch,因此一個比 Swift 包裝活得久的 GtkWidget 會回報到空處，而不是回報進下一個
    /// widget 的 handler。
    final class FocusWatch {
        weak var widget: Widget?
        var handler: (Bool) -> Void

        init(widget: Widget, handler: @escaping (Bool) -> Void) {
            self.widget = widget
            self.handler = handler
        }

        func report(_ focused: Bool) {
            guard widget != nil else { return }
            handler(focused)
        }
    }

    /// A focus request made before its window was mapped, applied when it is.
    ///
    /// **GTK refuses `grab_focus` until the window is mapped, and then picks a
    /// focus of its own.** `@FocusState var field = .email` is asked for in the
    /// first commit, before `present()`; the grab returned false, and showing the
    /// window moved the focus to the FIRST focusable widget -- P70 launched with
    /// `-start email` on GtkBackend opened with the caret in NAME and `focused
    /// field: name` (2026-11-24), and by the time ``FocusModifier`` asked again
    /// the name field had already reported itself focused. So the request waits
    /// for the window's `map` signal. `gtk_window_show` maps the window and only
    /// then, if no widget has the focus, moves it to the first one; a grab made
    /// from the `map` handler is in place before that check, so GTK leaves it.
    ///
    /// 一個在視窗 map 之前提出的聚焦要求，在視窗 map 時套用。
    ///
    /// **視窗 map 之前 GTK 會拒絕 `grab_focus`,map 之後又自己挑一個焦點。** `@FocusState var field = .email`
    /// 在第一次 commit 時提出，那時還沒 `present()`;grab 回傳 false,顯示視窗時焦點被移到**第一個**可聚焦的 widget
    /// ——以 `-start email` 在 GtkBackend 上啟動的 P70,開啟時游標在 NAME、畫面寫著 `focused field: name`
    /// (2026-11-24),而等 ``FocusModifier`` 再問一次時,name 欄位早已回報自己取得焦點。因此這個要求等視窗的
    /// `map` signal。`gtk_window_show` 先 map 視窗，之後若沒有 widget 持有焦點才把它移到第一個；在 `map` handler
    /// 裡做的 grab 早於那個檢查，所以 GTK 不會動它。
    final class FocusWhenMapped {
        weak var widget: Widget?
        var handlerID: gulong = 0

        init(widget: Widget) {
            self.widget = widget
        }
    }

    func focusWhenMapped(_ widget: Widget, window: UnsafeMutablePointer<GtkWidget>) {
        let box = FocusWhenMapped(widget: widget)
        let onMap: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = {
            instance, data in
            guard let instance, let data else { return }
            let box = Unmanaged<FocusWhenMapped>.fromOpaque(data).takeUnretainedValue()
            let handlerID = box.handlerID
            if let target = box.widget?.widgetPointer, gtk_widget_get_sensitive(target) != 0 {
                GtkBackend.grabFocus(in: target)
            }
            // One-shot. Disconnecting runs the destroy notify, which releases
            // the box, so it is not touched after this line.
            // 只執行一次。斷開連線會執行 destroy notify 並釋放 box,所以這一行之後不再碰它。
            g_signal_handler_disconnect(instance, handlerID)
        }
        let release: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<GClosure>?) -> Void = {
            data, _ in
            guard let data else { return }
            Unmanaged<FocusWhenMapped>.fromOpaque(data).release()
        }
        box.handlerID = g_signal_connect_data(
            UnsafeMutableRawPointer(window),
            "map",
            unsafeBitCast(onMap, to: GCallback.self),
            Unmanaged.passRetained(box).toOpaque(),
            release,
            GConnectFlags(rawValue: 0)
        )
    }

    /// Focuses this widget, or the first thing inside it that takes the focus.
    ///
    /// **`grab_focus` alone focused nothing a `TextField` is made of.** GTK 4
    /// separates `can-focus` (this widget or something in it may hold the focus)
    /// from `focusable` (this widget itself may), and `grab_focus` on a widget
    /// that is not focusable returns false. The widget this backend hands out for
    /// a field is a `PassthroughFixed` around the `GtkEntry`, focusable=0, so
    /// every request from code was refused -- P70 on GtkBackend (macOS,
    /// 2026-11-24) logged `grab refused mapped=1 focusable=0` for `field =
    /// .email` and wrote `none` back. `gtk_widget_child_focus` is GTK's own way of
    /// moving the focus INTO a widget, the same search Tab uses, so the wrapper
    /// is asked that next.
    ///
    /// 讓這個 widget——或它裡面第一個能取得焦點的東西——取得焦點。
    ///
    /// **單靠 `grab_focus`,`TextField` 的任何組成部分都不會取得焦點。** GTK 4 把 `can-focus`(這個 widget 或
    /// 它裡面的東西可以持有焦點)與 `focusable`(這個 widget 本身可以)分開，而對不是 focusable 的 widget 呼叫
    /// `grab_focus` 會回傳 false。本 backend 為欄位交出去的 widget 是包著 `GtkEntry` 的 `PassthroughFixed`,
    /// focusable=0,所以每個來自程式的要求都被拒絕——GtkBackend 上的 P70(macOS,2026-11-24)對 `field = .email`
    /// 記下 `grab refused mapped=1 focusable=0`,並寫回 `none`。`gtk_widget_child_focus` 是 GTK 自己把焦點
    /// **移進**一個 widget 的方式，與 Tab 用的是同一個搜尋，所以接著問 wrapper 這一個。
    @discardableResult
    nonisolated static func grabFocus(in widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
        gtk_widget_grab_focus(widget) != 0
            || gtk_widget_child_focus(widget, GTK_DIR_TAB_FORWARD) != 0
    }
}
