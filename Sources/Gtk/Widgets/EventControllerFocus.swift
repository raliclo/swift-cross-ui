import CGtk
import GtkCHelpers

/// `GtkEventControllerFocus`: reports the focus entering and leaving a widget
/// OR ANY OF ITS CHILDREN.
///
/// **That "or any of its children" is the whole reason this exists rather than
/// `notify::has-focus`.** The property is about one widget, and what this
/// backend hands out for a text field is a wrapper around a `GtkEntry` -- GTK
/// focuses the entry, so the wrapper's own `has-focus` stays false the entire
/// time a user is typing into it. `enter` and `leave` on the controller fire for
/// the subtree, which is what makes them agree with
/// `GtkBackend.isFocused(_:)`, and disagreeing with it would be a silent,
/// plausible wrongness rather than an error.
///
/// Hand-written, checked the same way `ListView` was: `GtkEventControllerFocus`
/// has zero hits in `Sources/Gtk/Generated`, and it needs none, because
/// `Sources/CGtk/header.h` is `#include <gtk/gtk.h>` -- the whole header -- so
/// `gtk_event_controller_focus_new` is already visible from Swift. A wrapper to
/// write, not a generator to run.
///
/// `GtkEventControllerFocus`:回報焦點進入與離開某個 widget **或其任一子節點**。
///
/// **「或其任一子節點」正是此物存在、而不用 `notify::has-focus` 的全部理由。** 那個屬性談的是單一
/// widget,而本 backend 為文字欄位交出去的是一個包著 `GtkEntry` 的 wrapper——GTK 聚焦的是那個 entry,
/// 因此在使用者輸入的整段期間,wrapper 自身的 `has-focus` 都維持 false。控制器的 `enter` 與 `leave`
/// 是對整棵子樹觸發的,而那正是它們與 `GtkBackend.isFocused(_:)` 一致的原因;若與它不一致,
/// 那會是一種無聲而看似合理的錯誤,而不是一個會報錯的失敗。
///
/// 手寫,查證方式與 `ListView` 相同:`GtkEventControllerFocus` 在 `Sources/Gtk/Generated` 中零命中,
/// 而它也不需要被產生,因為 `Sources/CGtk/header.h` 就是 `#include <gtk/gtk.h>`——整份標頭——
/// 因此 `gtk_event_controller_focus_new` 從 Swift 已經看得見。要寫的是 wrapper,不是要跑產生器。
public class EventControllerFocus: EventController {
    /// Focus entered this widget or one of its descendants.
    /// 焦點進入了這個 widget 或它的某個後代。
    public var enter: ((EventControllerFocus) -> Void)?

    /// Focus left this widget and all of its descendants.
    /// 焦點離開了這個 widget 及其所有後代。
    public var leave: ((EventControllerFocus) -> Void)?

    private var enterHandlerID: gulong?
    private var leaveHandlerID: gulong?

    public convenience init() {
        self.init(gtk_event_controller_focus_new())
    }

    open override func registerSignals() {
        super.registerSignals()
        // Guarded, because a widget being reparented registers signals again and
        // a second connection would report every focus change twice. The same
        // guard ListView carries, for the same reason.
        // 加上防護,因為一個 widget 被重新指定父節點時會再次註冊 signal,而第二次連接會讓每一次
        // 焦點變更被回報兩次。ListView 帶著同一個防護,理由相同。
        guard enterHandlerID == nil else { return }

        // Unretained: the widget owns this controller through its
        // `eventControllers` array, so the wrapper outlives every callback, and
        // the ids are disconnected in deinit below.
        // 不保留:widget 透過它的 `eventControllers` 陣列擁有這個控制器,因此 wrapper 活得比每一次
        // callback 都久;而那些 id 會在下方的 deinit 中被斷開。
        let data = Unmanaged.passUnretained(self).toOpaque()

        let entered: @convention(c) (
            UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
        ) -> Void = { _, data in
            guard let data else { return }
            let controller = Unmanaged<EventControllerFocus>.fromOpaque(data)
                .takeUnretainedValue()
            controller.enter?(controller)
        }
        enterHandlerID = g_signal_connect_data(
            UnsafeMutableRawPointer(opaquePointer),
            "enter",
            gCallback(entered),
            data,
            nil,
            SHIM_G_CONNECT_DEFAULT
        )

        let left: @convention(c) (
            UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
        ) -> Void = { _, data in
            guard let data else { return }
            let controller = Unmanaged<EventControllerFocus>.fromOpaque(data)
                .takeUnretainedValue()
            controller.leave?(controller)
        }
        leaveHandlerID = g_signal_connect_data(
            UnsafeMutableRawPointer(opaquePointer),
            "leave",
            gCallback(left),
            data,
            nil,
            SHIM_G_CONNECT_DEFAULT
        )
    }

    deinit {
        // Connected with `g_signal_connect_data` rather than through GObject's
        // `addSignal`, so they are not in the set it disconnects for us. A
        // callback arriving after this object is gone would call
        // `takeUnretainedValue` on freed memory -- the hazard DropTarget and
        // ListView both record.
        // 這些是以 `g_signal_connect_data` 連接的,而非經由 GObject 的 `addSignal`,因此不在它替我們
        // 斷開的那個集合裡。一個在本物件消失之後才抵達的 callback,會對已釋放的記憶體呼叫
        // `takeUnretainedValue`——DropTarget 與 ListView 都記載過這個危險。
        for id in [enterHandlerID, leaveHandlerID].compactMap({ $0 }) {
            g_signal_handler_disconnect(UnsafeMutableRawPointer(opaquePointer), id)
        }
    }
}
