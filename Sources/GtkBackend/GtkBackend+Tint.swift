import Gtk
@_spi(Backends) import SwiftCrossUI

/// `tint(_:)` on GTK: CSS rules, scoped to one control's own class, that paint
/// the nodes the theme fills with its accent (`@accent_bg_color`, formerly
/// `@theme_selected_bg_color`) in the tint instead.
///
/// Background colour, border colour and `background-image: none` together,
/// because a theme may draw the accent as any of the three; the image is the
/// one that would otherwise cover the colour. Only enabled controls: a
/// disabled one keeps the theme's insensitive look, as on the other backends.
/// The rules name descendants (`check`, `trough highlight`, `trough progress`),
/// so the provider is installed for the display, as a picker's label rules are.
///
/// GTK 上的 `tint(_:)`:限定在單一控制項自己 class 的 CSS 規則，把主題以強調色(`@accent_bg_color`,舊稱
/// `@theme_selected_bg_color`)填滿的節點改用 tint 繪製。
///
/// 同時設定背景色、邊框色與 `background-image: none`,因為主題可能以三者中任一種畫出強調色;不清掉圖片，它會蓋住顏色。
/// 只作用於啟用中的控制項：停用的控制項維持主題的停用外觀，與其他 backend 相同。規則指名後代(`check`、
/// `trough highlight`、`trough progress`),所以 provider 安裝在 display 上，與 picker 標籤的規則相同。
extension GtkBackend {
    /// The rules that paint `parts` of `widget` in the environment's tint, or
    /// "" without one. Each part is appended to the widget's own class.
    /// 把 `widget` 的 `parts` 以 environment 的 tint 繪製的規則;沒有 tint 時為 ""。每個 part 接在 widget 自己的 class 後面。
    func tintCSS(
        of environment: EnvironmentValues,
        for widget: Gtk.Widget,
        parts: [String]
    ) -> String {
        guard let tint = environment.tint else { return "" }
        let color = CSSProperty.rgba(tint.resolve(in: environment).gtkColor)
        let selectors = parts.map { ".\(widget.css.cssClass)\($0)" }
        return """
            \(selectors.joined(separator: ", ")) {
                background-color: \(color);
                border-color: \(color);
                background-image: none;
            }
            """
    }

    /// Loads the widget's own `css` block followed by its tint rules. A control
    /// that has never been tinted is left alone, so an untinted app adds no
    /// display-wide provider; one that was tinted and no longer is reloads
    /// without the rules. 載入 widget 自己的 `css` 區塊，後面接它的 tint 規則。從未加過 tint 的控制項完全不碰，
    /// 所以沒有用 tint 的 app 不會多出 display 範圍的 provider;加過而現在沒有的，重新載入時不帶這些規則。
    func applyTint(
        of environment: EnvironmentValues,
        to widget: Gtk.Widget,
        parts: [String]
    ) {
        let rules = tintCSS(of: environment, for: widget, parts: parts)
        guard !rules.isEmpty || widget.cssProviderScope == .display else { return }
        widget.cssProviderScope = .display
        widget.loadCSSText(from: widget.css.stringRepresentation + "\n" + rules)
    }
}
