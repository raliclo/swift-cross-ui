import CGtk
import Gtk
import GtkCHelpers
@_spi(Backends) import SwiftCrossUI

/// `BackendFeatures.ButtonPressState` on GTK 4.
///
/// GtkBackend had nothing to reuse. A grep for `isPressed`, `isHighlighted` or
/// `pressed` across `Sources/GtkBackend/` returned zero on 2026-09-08 -- unlike
/// AppKit, UIKit and WinUI, this backend never kept a press flag of its own,
/// because it never needed one: the pressed look is drawn by CSS
/// (`GtkBackend+Button.swift:174`, `button.customButton.flat:active`), and the
/// `:active` selector is fed by GTK, not by us.
///
/// **So the signal to listen to is the same one that CSS selector reads.**
/// `GTK_STATE_FLAG_ACTIVE` is the flag behind `:active`
/// (`Sources/GtkCodeGen/GirFiles/Gtk-4.0.gir:136944`), `state-flags-changed` is
/// emitted whenever a widget's flags change (`Gtk-4.0.gir:178793`), and
/// `gtk_widget_get_state_flags` reads the current set (`Gtk-4.0.gir:175351`).
/// That is one signal connection per button and no new event controller.
///
/// **Why not `GtkGestureClick`.** A `GtkButton` already owns a click gesture. A
/// second gesture on the same widget competes for the same event sequence, and
/// the moment the button's own gesture claims that sequence ours is denied and
/// cancelled -- so the press would be reported and then immediately withdrawn,
/// for every press. Reading the state flags is not a gesture and nothing can
/// deny it.
///
/// **Why not `GtkEventControllerMotion` for the abandon case.** It would have
/// worked, and it was rejected for a specific collision:
/// `GtkBackend.swift:3972` finds the hover controller with
/// `eventControllers.first { $0 is EventControllerMotion }`. A button that is
/// also an `.onHover` target would then have two of them, and `first` would hand
/// `updateHoverTarget` whichever was added first -- silently replacing this
/// file's `enter`/`leave` closures, or not, depending on the order the two
/// modifiers happened to commit in. `GTK_STATE_FLAG_PRELIGHT`
/// (`Gtk-4.0.gir:136953`) answers the same question, arrives on the signal we
/// already have, and adds no object to that array.
///
/// GTK 4 上的 `BackendFeatures.ButtonPressState`。
///
/// GtkBackend 沒有任何既有狀態可以沿用。2026-09-08 於 `Sources/GtkBackend/` 中搜尋 `isPressed`、
/// `isHighlighted` 或 `pressed` 的結果為零——與 AppKit、UIKit、WinUI 不同，這個 backend 從未自行
/// 保存過按下旗標，因為它從不需要：按下的外觀是由 CSS 繪製的
/// （`GtkBackend+Button.swift:174`，`button.customButton.flat:active`），而 `:active` 這個選擇器
/// 是由 GTK 餵養的，不是由我們。
///
/// **因此要監聽的訊號，正是該 CSS 選擇器所讀取的那一個。** `GTK_STATE_FLAG_ACTIVE` 就是 `:active`
/// 背後的旗標（`Sources/GtkCodeGen/GirFiles/Gtk-4.0.gir:136944`），`state-flags-changed` 會在
/// widget 旗標改變時發出（`Gtk-4.0.gir:178793`），而 `gtk_widget_get_state_flags` 讀取當前的旗標
/// 集合（`Gtk-4.0.gir:175351`）。這樣每顆按鈕只需一次 signal 連接，且不需新增任何 event controller。
///
/// **為何不用 `GtkGestureClick`。** `GtkButton` 本身已擁有一個 click gesture。同一個 widget 上的第二個
/// gesture 會與它爭奪同一條 event sequence，而一旦按鈕自己的 gesture 宣告（claim）該 sequence，我們的
/// 就會被否決並取消——於是每一次按壓都會先被回報、隨即又被撤回。讀取 state flag 並不是一個 gesture，
/// 沒有東西能否決它。
///
/// **為何不用 `GtkEventControllerMotion` 處理放棄的情況。** 它本來可行，之所以被否決是為了一個具體的
/// 衝突：`GtkBackend.swift:3972` 是以
/// `eventControllers.first { $0 is EventControllerMotion }` 來尋找 hover controller 的。一顆同時也是
/// `.onHover` 目標的按鈕上便會有兩個，而 `first` 會把「先被加入的那一個」交給 `updateHoverTarget`
/// ——於是本檔的 `enter`/`leave` closure 會不會被悄悄取代，全看兩個 modifier 剛好以什麼順序 commit。
/// `GTK_STATE_FLAG_PRELIGHT`（`Gtk-4.0.gir:136953`）能回答同一個問題，隨我們已有的訊號一同抵達，
/// 而且不會在那個陣列中多放任何物件。
///
/// **A bare extension, deliberately.** The conformance is declared on the class
/// itself at `GtkBackend.swift:58`; naming `BackendFeatures.ButtonPressState`
/// again here would be a redundant conformance and would not compile.
///
/// **刻意採用不帶 conformance 的 extension。** 該 conformance 已宣告於類別本身
/// （`GtkBackend.swift:58`）；在此再次寫出 `BackendFeatures.ButtonPressState` 會構成重複
/// conformance 而無法編譯。
extension GtkBackend {
    public func updateButtonPressHandler(
        _ button: Widget,
        handler: @escaping (Bool) -> Void
    ) {
        GtkButtonPressTracker.install(on: button, handler: handler)
    }
}

/// Per-button state behind ``GtkBackend/updateButtonPressHandler(_:handler:)``.
///
/// Owned by the `GtkWidget` through `g_object_set_data_full`, not by a table in
/// this file. `Button.commit` reinstalls the handler on every update
/// (`Sources/SwiftCrossUI/Views/Button.swift:349`), so the lookup has to be
/// keyed by the widget and has to be cheap; and a Swift-side dictionary keyed by
/// object identity would keep an entry for every button the application ever
/// built. GObject data is destroyed with the widget, which is the lifetime we
/// actually want.
///
/// ``GtkBackend/updateButtonPressHandler(_:handler:)`` 背後的每按鈕狀態。
///
/// 它由 `GtkWidget` 透過 `g_object_set_data_full` 持有，而非由本檔中的某個表格持有。
/// `Button.commit` 在每次更新時都會重新安裝 handler（`Sources/SwiftCrossUI/Views/Button.swift:349`），
/// 因此查找必須以 widget 為鍵、且必須廉價；而一個以物件識別為鍵的 Swift 端字典，會為應用程式曾建立過的
/// 每一顆按鈕永久保留一筆項目。GObject data 會隨 widget 一同銷毀，那正是我們真正想要的生命週期。
@MainActor
final class GtkButtonPressTracker {
    private static let dataKey = "scui-button-press-state-tracker"

    private let widget: UnsafeMutablePointer<GtkWidget>
    private var handler: (Bool) -> Void

    /// The last value handed to the handler. The contract asks for a call on
    /// every transition, which means exactly one call per transition; without
    /// this, hovering a button would re-report `false` on every crossing.
    /// 最後一次交給 handler 的值。合約要求每次轉換都呼叫一次，也就是每次轉換恰好一次；若沒有它，
    /// 只是把指標移過按鈕就會在每次進出時重複回報 `false`。
    private var reported = false

    /// Whether the press that is currently in flight began under the pointer.
    ///
    /// A keyboard activation sets `ACTIVE` with the pointer somewhere else
    /// entirely, so gating on `PRELIGHT` unconditionally would report a
    /// space-bar press as not pressed. Recorded at the rising edge instead.
    ///
    /// 目前進行中的這次按壓是否始於指標之下。
    ///
    /// 鍵盤觸發會在指標位於完全不同位置的情況下設定 `ACTIVE`，因此若無條件以 `PRELIGHT` 把關，
    /// 一次空白鍵按壓會被回報為未按下。改為在上升緣時記錄。
    private var pointerInitiated = false

    private init(
        widget: UnsafeMutablePointer<GtkWidget>,
        handler: @escaping (Bool) -> Void
    ) {
        self.widget = widget
        self.handler = handler
    }

    static func install(on button: Gtk.Widget, handler: @escaping (Bool) -> Void) {
        let object = button.gobjectPointer

        if let existing = g_object_get_data(object, dataKey) {
            Unmanaged<GtkButtonPressTracker>.fromOpaque(existing)
                .takeUnretainedValue()
                .handler = handler
            return
        }

        let tracker = GtkButtonPressTracker(
            widget: button.widgetPointer,
            handler: handler
        )
        let boxed = Unmanaged.passRetained(tracker).toOpaque()

        // +1 here, released by the destroy notify. The signal below takes the
        // same pointer unretained: GObject disconnects signals in dispose and
        // destroys qdata in finalize, so the callback is gone before the box is.
        // 此處 +1，由 destroy notify 釋放。下方的 signal 取用同一個指標但不持有：GObject 於
        // dispose 中斷開 signal、於 finalize 中銷毀 qdata，因此 callback 會在這個 box 之前消失。
        g_object_set_data_full(
            object,
            dataKey,
            boxed,
            { pointer in
                guard let pointer else { return }
                Unmanaged<GtkButtonPressTracker>.fromOpaque(pointer).release()
            }
        )

        // The second parameter is the *previous* flag set (`Gtk-4.0.gir:178803`)
        // and is deliberately ignored -- `gtk_widget_get_state_flags` gives the
        // current one, which is what a transition should be computed from.
        // Typed `UInt32` rather than `GtkStateFlags` so the callback's C
        // signature does not depend on which shape the importer picks for a
        // plain C enum.
        //
        // 第二個參數是**先前的**旗標集合（`Gtk-4.0.gir:178803`），此處刻意忽略——
        // `gtk_widget_get_state_flags` 給的是當前的那一個，而轉換本就該由它算出。型別寫成 `UInt32`
        // 而非 `GtkStateFlags`，好讓這個 callback 的 C 簽章不依賴匯入器為一個普通 C enum 所選的形狀。
        let callback:
            @convention(c) (
                UnsafeMutableRawPointer,
                UInt32,
                UnsafeMutableRawPointer
            ) -> Void = { _, _, data in
                MainActor.assumeIsolated {
                    Unmanaged<GtkButtonPressTracker>.fromOpaque(data)
                        .takeUnretainedValue()
                        .stateFlagsChanged()
                }
            }

        g_signal_connect_data(
            object,
            "state-flags-changed",
            unsafeBitCast(callback, to: GCallback.self),
            boxed,
            nil,
            SHIM_G_CONNECT_AFTER
        )
    }

    /// Recomputes the press state from the widget's current flags.
    ///
    /// The abandon case -- press, drag off the button, release -- is covered
    /// twice over, and deliberately. GTK clearing `ACTIVE` when the pointer
    /// leaves during a press is enough on its own; if a GTK build instead keeps
    /// `ACTIVE` and only drops `PRELIGHT`, the `&&` still reports `false`. Both
    /// flags arrive on this one signal, so covering both costs nothing. The only
    /// way to latch is a GTK that keeps both set while the pointer is outside,
    /// which would also leave its own `:active` styling lit on a button the
    /// user had dragged away from.
    ///
    /// 由 widget 當前的旗標重新算出按下狀態。
    ///
    /// 放棄的情況——按下、拖離按鈕、放開——被涵蓋了兩次，而且是刻意的。若 GTK 在按壓期間指標離開時
    /// 會清除 `ACTIVE`，光靠它就足夠；若某個 GTK 版本反而保留 `ACTIVE` 而只取消 `PRELIGHT`，那個
    /// `&&` 依然會回報 `false`。兩個旗標都隨這一個訊號抵達，因此兩者兼顧毫無成本。唯一會卡住的情況，
    /// 是某個 GTK 在指標位於外部時仍同時保留兩者——而那樣的 GTK 也會讓使用者已拖離的按鈕繼續亮著它
    /// 自己的 `:active` 樣式。
    private func stateFlagsChanged() {
        let flags = gtk_widget_get_state_flags(widget).rawValue
        let isActive = flags & GTK_STATE_FLAG_ACTIVE.rawValue != 0
        let isPrelight = flags & GTK_STATE_FLAG_PRELIGHT.rawValue != 0

        if isActive && !reported {
            pointerInitiated = isPrelight
        }

        report(isActive && (isPrelight || !pointerInitiated))
    }

    private func report(_ pressed: Bool) {
        guard pressed != reported else { return }
        reported = pressed
        handler(pressed)
    }
}
