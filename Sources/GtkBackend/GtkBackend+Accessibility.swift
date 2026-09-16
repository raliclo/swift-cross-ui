import CGtk
import Gtk
import GtkCHelpers
import SwiftCrossUI

extension GtkBackend: BackendFeatures.Accessibility {
    /// `GTK_ACCESSIBLE_PROPERTY_LABEL`, which is what an assistive technology
    /// announces for the widget.
    ///
    /// 螢幕閱讀器為這個 widget 所唸出的東西,對應 `GTK_ACCESSIBLE_PROPERTY_LABEL`。
    public func setAccessibilityLabel(ofWidget widget: Widget, to label: String?) {
        updateStringProperty(of: widget, GTK_ACCESSIBLE_PROPERTY_LABEL, to: label)
    }

    /// `GTK_ACCESSIBLE_PROPERTY_DESCRIPTION`, the supplementary text.
    /// 補充說明文字,對應 `GTK_ACCESSIBLE_PROPERTY_DESCRIPTION`。
    public func setAccessibilityHint(ofWidget widget: Widget, to hint: String?) {
        updateStringProperty(of: widget, GTK_ACCESSIBLE_PROPERTY_DESCRIPTION, to: hint)
    }

    /// The current value, as `GTK_ACCESSIBLE_PROPERTY_VALUE_TEXT`.
    ///
    /// **`VALUE_TEXT`, not `DESCRIPTION`.** GTK has a numeric value trio --
    /// `VALUE_NOW`, `VALUE_MIN`, `VALUE_MAX` -- for things like sliders, and
    /// `VALUE_TEXT` is the string form for everything else. Putting a value into
    /// the description instead would announce it in the wrong place and would
    /// not update as a value.
    ///
    /// 目前的值,以 `GTK_ACCESSIBLE_PROPERTY_VALUE_TEXT` 表示。
    ///
    /// **用 `VALUE_TEXT`,不是 `DESCRIPTION`。** GTK 有一組數值三元組——`VALUE_NOW`、`VALUE_MIN`、
    /// `VALUE_MAX`——供 slider 之類使用,而 `VALUE_TEXT` 是其餘一切的字串形式。若改把值塞進 description,
    /// 它會在錯誤的位置被播報,而且不會以「值」的方式更新。
    public func setAccessibilityValue(ofWidget widget: Widget, to value: String?) {
        updateStringProperty(of: widget, GTK_ACCESSIBLE_PROPERTY_VALUE_TEXT, to: value)
    }

    /// `GTK_ACCESSIBLE_STATE_HIDDEN`: present in the widget tree, absent from
    /// the accessibility one.
    ///
    /// 出現在 widget 樹中、但不出現在無障礙樹中,對應 `GTK_ACCESSIBLE_STATE_HIDDEN`。
    public func setAccessibilityHidden(ofWidget widget: Widget, to hidden: Bool) {
        // `scui_gtype_boolean()`, not `G_TYPE_BOOLEAN`. The G_TYPE_* names are
        // macros and Swift cannot see them, which is why `scui_gtype_string()`
        // already existed for the drop target -- this adds the boolean beside
        // it rather than inventing a second mechanism.
        // 用 `scui_gtype_boolean()`,不是 `G_TYPE_BOOLEAN`。G_TYPE_* 這組名稱是巨集,Swift 看不到,
        // 而那正是 drop target 早已有 `scui_gtype_string()` 的原因——此處是在它旁邊補上 boolean,
        // 而不是另外發明第二套機制。
        var state = GTK_ACCESSIBLE_STATE_HIDDEN
        var value = GValue()
        g_value_init(&value, scui_gtype_boolean())
        g_value_set_boolean(&value, hidden ? 1 : 0)
        defer { g_value_unset(&value) }
        gtk_accessible_update_state_value(accessible(widget), 1, &state, &value)
    }

    /// Sets one string-valued accessible property, or clears it with `nil`.
    ///
    /// **`gtk_accessible_update_property` is VARIADIC and Swift cannot call it.**
    /// The `_value` variant takes counted arrays instead and is the callable
    /// path -- the same escape hatch GLib provides throughout. Checked in
    /// `gtkaccessible.h` rather than assumed: both `update_property` and
    /// `update_state` have one, right below the variadic they mirror.
    ///
    /// A `nil` clears the property by resetting it, which is what removes a
    /// label rather than leaving a stale one being announced.
    ///
    /// 設定一個字串型的 accessible property;傳 `nil` 則清除它。
    ///
    /// **`gtk_accessible_update_property` 是可變參數函式,Swift 呼叫不了它。** `_value` 變體改收
    /// 帶計數的陣列,那才是可呼叫的路徑——與 GLib 一貫提供的逃生口相同。此處是**查** `gtkaccessible.h`
    /// 得知的、不是假設的:`update_property` 與 `update_state` 各有一個,就在它們所對應的可變參數版下方。
    ///
    /// 傳入 `nil` 會以重設的方式清除該屬性,而那正是「移除標籤」的做法——而不是留下一個過期的標籤
    /// 繼續被唸出來。
    private func updateStringProperty(
        of widget: Widget,
        _ property: GtkAccessibleProperty,
        to text: String?
    ) {
        let target = accessible(widget)
        guard let text else {
            var property = property
            gtk_accessible_reset_property(target, property)
            _ = property
            return
        }
        var property = property
        var value = GValue()
        g_value_init(&value, scui_gtype_string())
        text.withCString { g_value_set_string(&value, $0) }
        defer { g_value_unset(&value) }
        gtk_accessible_update_property_value(target, 1, &property, &value)
    }

    /// Every `GtkWidget` implements `GtkAccessible`, so this is the same pointer
    /// widened -- the cast every hand-written binding in this tree makes.
    /// 每一個 `GtkWidget` 都實作了 `GtkAccessible`,因此這只是同一個指標的放寬——與本樹每一份
    /// 手寫綁定所做的轉型相同。
    /// `OpaquePointer`, because `GtkAccessible` is an INTERFACE and the importer
    /// gives interfaces no Swift type -- the same split `ListView` ran into,
    /// where `GtkWindow` is a struct and `GtkSelectionModel` is not. Read off
    /// the compiler rather than assumed from the neighbouring file.
    /// 使用 `OpaquePointer`,因為 `GtkAccessible` 是一個**介面**,而匯入器不會為介面產生 Swift 型別
    /// ——這與 `ListView` 遇到的分裂相同:`GtkWindow` 是 struct,而 `GtkSelectionModel` 不是。
    /// 此處的型別是**從編譯器讀來**的,不是從隔壁檔案推定的。
    private func accessible(_ widget: Widget) -> OpaquePointer {
        OpaquePointer(widget.widgetPointer)
    }
}
