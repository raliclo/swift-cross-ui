import Gtk
@_spi(Backends) import SwiftCrossUI

// GtkBackend's half of `TextFieldStyle`. Kept in its own file rather than added
// to the ~5500-line `GtkBackend.swift`, which is under concurrent edit for the
// toolbar work.
//
// GtkBackend 對應 `TextFieldStyle` 的部分。獨立成一個檔案，而非加進約 5500 行的
// `GtkBackend.swift`——後者正因 toolbar 的工作而被同時編輯中。
extension GtkBackend {
    /// Applies a text field shape to a `GtkEntry`, returning the CSS the shape
    /// needs on top of what `cssProperties(for:isControl:)` already produced.
    ///
    /// Two mechanisms, not one, and the split is not arbitrary:
    ///
    /// - **`has-frame`** (`Sources/Gtk/Generated/Entry.swift:862`, the
    ///   `gtk-entry-has-frame` GObject property) is what GTK itself offers for
    ///   "draw a frame or don't", so `plain` uses it. It is a property rather
    ///   than a style class, which matters: it survives a theme change, and a
    ///   theme cannot decide to ignore it.
    /// - **CSS** is what GTK offers for the corner radius, because there is no
    ///   GObject property for one. `border-radius` is a documented GTK4 CSS
    ///   property and ``CSSProperty/cornerRadius(_:)`` already existed for the
    ///   `cornerRadius(_:)` modifier.
    ///
    /// `plain` sets both anyway -- `has-frame: false` *and* explicit
    /// zero-width, transparent, shadowless CSS. That is belt and braces on
    /// purpose. GTK4's `gtk_entry_set_has_frame()` is documented as "whether
    /// the entry has a beveled frame around it", but what a theme does with
    /// that is the theme's business, and Adwaita in particular draws entry
    /// chrome from `background` and `box-shadow` as well as `border`. Relying
    /// on the property alone would make the feature theme-dependent, and a
    /// style that works on one machine and not another is worse than one that
    /// does not work at all, because only the second gets reported.
    ///
    /// The class selector this CSS lands in (`.<customCSSClass>`, see
    /// ``CSSBlock/stringRepresentation``) outranks the theme's bare `entry`
    /// element selector on specificity, which is why it takes effect without
    /// `!important`.
    ///
    /// - Returns: Extra properties for the caller to merge into the entry's
    ///   CSS block. Returning them rather than setting them here keeps the
    ///   single `css.clear()` / `css.set(properties:)` pair in
    ///   `updateTextField` -- two writers to one block would race on the
    ///   `clear()`.
    ///
    /// 兩種機制而非一種，且這個分工並非隨意：
    ///
    /// - **`has-frame`**（`Sources/Gtk/Generated/Entry.swift:862`，即 `gtk-entry-has-frame`
    ///   這個 GObject 屬性）正是 GTK 自身為「畫不畫外框」所提供的東西，因此 `plain` 使用它。它是
    ///   屬性而非 style class，這一點很重要：它能在主題更換後存續，而主題也無法決定忽略它。
    /// - **CSS** 則是 GTK 為圓角半徑所提供的東西，因為並沒有對應的 GObject 屬性。`border-radius`
    ///   是 GTK4 有文件記載的 CSS 屬性，而 ``CSSProperty/cornerRadius(_:)`` 早已為
    ///   `cornerRadius(_:)` modifier 而存在。
    ///
    /// `plain` 兩者都設——`has-frame: false`**以及**明確的零寬度、透明、無陰影 CSS。這是刻意的雙重
    /// 保險。GTK4 的 `gtk_entry_set_has_frame()` 文件寫的是「entry 周圍是否有斜面外框」，但主題拿它
    /// 去做什麼是主題的事，而 Adwaita 尤其會同時用 `background` 與 `box-shadow`（而不只是 `border`）
    /// 來繪製 entry 的外框裝飾。只依賴該屬性會讓這項功能取決於主題，而「在某台機器上有效、在另一台
    /// 無效」的樣式比「完全無效」更糟，因為只有後者會被回報。
    func textFieldStyleProperties(
        _ style: BackendTextFieldStyle,
        applyingTo entry: Entry
    ) -> [CSSProperty] {
        switch style {
            case .automatic:
                // GtkEntry's own default. Restored explicitly rather than
                // skipped, because the same widget is re-committed on every
                // update and may have been `plain` a moment ago; a no-op here
                // would make `plain` a one-way door.
                //
                // No CSS is returned: `updateTextField` calls `css.clear()`
                // before merging, so dropping the overrides is enough to hand
                // the entry back to the theme. There is deliberately no
                // `border-radius` here either -- the theme's own radius is
                // what `automatic` means.
                //
                // GtkEntry 自身的預設值。之所以明確還原而非略過，是因為同一個 widget 在每次更新時
                // 都會被重新 commit，而它上一刻可能是 `plain`；此處若什麼都不做，`plain` 就會變成
                // 一扇單向門。
                entry.hasFrame = true
                return []
            case .plain:
                entry.hasFrame = false
                return [
                    CSSProperty(key: "border-width", value: "0"),
                    CSSProperty(key: "border-color", value: "transparent"),
                    CSSProperty(key: "box-shadow", value: "none"),
                    CSSProperty(key: "background-image", value: "none"),
                    CSSProperty(key: "background-color", value: "transparent"),
                    CSSProperty(key: "outline-width", value: "0"),
                ]
            case .roundedBorder:
                entry.hasFrame = true
                // 6px is Adwaita's own entry radius, so this reads as "the
                // rounded one" next to `squareBorder` rather than as a
                // different widget. Named here rather than left to the theme
                // because `roundedBorder` is a request for a specific shape --
                // an application that wants the theme's choice asks for
                // `automatic`.
                //
                // 6px 就是 Adwaita 自身的 entry 圓角半徑，因此它與 `squareBorder` 並列時讀起來會是
                // 「圓角的那一個」，而不是另一個 widget。之所以在此指名而不交給主題，是因為
                // `roundedBorder` 要的是一個特定外形——想要主題的選擇，該問的是 `automatic`。
                return [.cornerRadius(6)]
            case .squareBorder:
                entry.hasFrame = true
                return [.cornerRadius(0)]
        }
    }
}
