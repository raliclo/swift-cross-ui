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
        // The bug was mine and it was introduced by the line below it. Setting
        // `can-focus` unconditionally is what makes a container focusable, which
        // this needs, and it is also what silences the one refusal the protocol
        // has to get right.
        //
        // **不敏感(insensitive)的 widget 會被拒絕,而這道防護放在此處,是因為下方那行授予
        // `can-focus` 的程式碼否則會覆寫掉 GTK 自己的拒絕。** 2026-09-16 由 P70 量到:少了它,
        // 「ask both for focus」回報 `DISABLED FOCUS reported true`——本 backend 把鍵盤交給了一個
        // 被停用的按鈕,並告訴 `@FocusState` 這件事成功了。AppKit 以先檢查 `acceptsFirstResponder`
        // 拒絕同一個情形;而 `sensitive` 就是 GTK 對它的寫法。
        //
        // 這個缺陷是我自己造成的,而且正是由它下面那一行引入的。無條件設定 `can-focus` 是「讓容器
        // 可以取得焦點」所必需的——而它同時也讓本協定唯一必須答對的那次拒絕失聲。
        guard gtk_widget_get_sensitive(pointer) != 0 else { return false }

        // Raw `gboolean` rather than the `toGBoolean()` / `toBool()` helpers:
        // those are internal to the Gtk module and not visible from GtkBackend.
        // Caught by building.
        // 使用原生的 `gboolean`,而非 `toGBoolean()` / `toBool()` 兩個輔助函式:它們是 Gtk 模組的
        // internal,從 GtkBackend 看不到。以建置抓到。
        gtk_widget_set_can_focus(pointer, 1)
        return gtk_widget_grab_focus(pointer) != 0
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
    /// `computeLayout`, so it runs on every frame -- adding a controller each
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
    /// 控制器每個 widget 最多安裝一次。本方法由 `computeLayout` 呼叫,因此每一幀都會跑——每次都新增
    /// 一個控制器,正是本 backend slider 上量到的那個缺陷(按一次回報 `began=5`),也正是手勢程式碼
    /// 被重構所要避開的那一個。此處只替換 handler。
    public func setFocusChangeHandler(
        ofWidget widget: Widget,
        to handler: @escaping (Bool) -> Void
    ) {
        let key = ObjectIdentifier(widget)
        focusChangeHandlers[key] = handler
        guard !widgetsWithFocusController.contains(key) else { return }
        widgetsWithFocusController.insert(key)

        let controller = EventControllerFocus()
        controller.enter = { [weak self] _ in
            self?.focusChangeHandlers[key]?(true)
        }
        controller.leave = { [weak self] _ in
            self?.focusChangeHandlers[key]?(false)
        }
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
}
