import CGtk
import Gtk
import GtkCHelpers
@_spi(Backends) import SwiftCrossUI

/// A button-style toggle whose label is a SwiftCrossUI view: a
/// `GtkToggleButton`, the widget a string-label toggle is (`createToggle()`),
/// with the label set as its child (`gtk_button_set_child`) instead of a
/// title, as `createButton(wrapping:)` does for a plain button.
///
/// The child is part of the button, so a click on the label is a click on the
/// toggle. The accessible role is GTK's toggle button, whose name GTK computes
/// from the texts of its content when no label property is set, as it does for
/// a view-label button.
///
/// 標籤為 SwiftCrossUI view 的按鈕樣式 toggle:一個 `GtkToggleButton`(字串標籤 toggle 用的就是它，見 `createToggle()`),
/// 以標籤作為它的子 widget(`gtk_button_set_child`)而非標題，與 `createButton(wrapping:)` 對一般按鈕的做法相同。子 widget
/// 是按鈕的一部分，因此點擊標籤就是點擊 toggle。輔助使用角色是 GTK 的 toggle button,在沒有設定 label 屬性時，GTK 從其內容的
/// 文字計算它的名稱，與 view 標籤按鈕相同。
extension GtkBackend: BackendFeatures.ViewLabelToggleButtons {
    public func createToggle(wrapping widget: Widget) -> Widget {
        let toggle = ToggleButton()
        gtk_button_set_child(toggle.widgetPointer.cast(), widget.widgetPointer)

        widget.horizontalAlignment = .center
        widget.verticalAlignment = .center

        return Self.withoutFocusOnClick(toggle)
    }

    public func updateToggle(
        _ toggle: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let toggle = toggle as! Gtk.ToggleButton
        toggle.sensitive = environment.isEnabled
        toggle.toggled = { widget in
            onChange(widget.active)
        }
        // `isControl: false` for the reason `updateToggle(_:label:environment:onChange:)`
        // gives: the control background would make on and off look the same.
        // 與 `updateToggle(_:label:environment:onChange:)` 的理由相同使用 `isControl: false`:控制項背景會讓開與關看起來一樣。
        toggle.css.set(properties: cssProperties(for: environment, isControl: false), clear: true)
    }

    public func setState(ofViewLabelToggle toggle: Widget, to state: Bool) {
        let toggle = toggle as! Gtk.ToggleButton
        toggle.withBlockedSignal(named: "toggled") {
            toggle.active = state
        }
    }

    /// The bordered button's padding: a `GtkToggleButton` takes the theme's
    /// `button` padding and border. / 帶框按鈕的 padding:`GtkToggleButton` 使用主題中 `button` 的 padding 與邊框。
    public func toggleButtonPadding(in environment: EnvironmentValues) -> SIMD2<Int> {
        measureBorderedButtonPadding()
    }
}
