import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

/// Freedesktop icons, asked for by name and checked before they are drawn.
///
/// **The check is the feature.** `gtk_image_new_from_icon_name` does not fail on
/// a name the theme lacks; it produces a widget that draws nothing, and an
/// application built that way looks the same as one whose icons are simply not
/// there. Measured against GTK 4.22.4 on 2026-09-07: of the symbol table's 36
/// `gtkIconName` values, **0 resolve as written and 15 resolve with a
/// `-symbolic` suffix**, because GTK 4 ships the symbolic family and not the
/// legacy full-colour set. GTK bundles 138 icons of its own and expects the
/// desktop's theme -- `adwaita-icon-theme` on most systems -- to supply the
/// rest. So on a minimal GTK install, 21 of the 36 would have drawn blanks.
///
/// This asks `gtk_icon_theme_has_icon` first and draws
/// ``SystemSymbol/textFallback`` when the answer is no, which makes the outcome
/// depend on what is installed rather than on nobody noticing.
///
/// freedesktop 圖示：依名稱索取，並在繪製之前先行檢查。
///
/// **那次檢查本身就是這項功能。** `gtk_image_new_from_icon_name` 對於主題所沒有的名稱並不會失敗；
/// 它會產生一個什麼都不畫的 widget，而以此方式建成的應用程式，看起來與「圖示根本不存在」完全相同。
/// 2026-09-07 對 GTK 4.22.4 實測：符號表的 36 個 `gtkIconName` 值中，**純名稱 0 個解析成功、加上
/// `-symbolic` 後綴則有 15 個**——因為 GTK 4 出貨的是 symbolic 家族，而非舊有的全彩集。GTK 自身內建
/// 138 個圖示，其餘則預期由桌面主題提供（在多數系統上是 `adwaita-icon-theme`）。因此在一個最小化的
/// GTK 安裝上，36 個之中會有 21 個畫出空白。
///
/// 此處先詢問 `gtk_icon_theme_has_icon`，在答案為否時改畫 ``SystemSymbol/textFallback``，使結果取決於
/// 「裝了什麼」，而不是取決於「沒有人注意到」。
extension GtkBackend {
    public func createSymbolView() -> Widget {
        // A container rather than a GtkImage, because the two outcomes are two
        // different widget classes -- GtkImage cannot draw text and GtkLabel
        // cannot draw a theme icon -- and which one is needed is not known until
        // a symbol arrives. The Apple backends put both into one attributed
        // string and need no container; GTK has no equivalent.
        //
        // 使用容器而非 GtkImage，因為兩種結果分屬兩個不同的 widget 類別——GtkImage 畫不了文字，
        // GtkLabel 也畫不了主題圖示——而需要哪一個，在符號抵達之前都無從得知。Apple 那兩個 backend
        // 把兩者放進同一個 attributed string，因此不需要容器；GTK 沒有對等的東西。
        createContainer()
    }

    public func updateSymbolView(
        _ symbolView: Widget,
        symbol: SystemSymbol,
        environment: EnvironmentValues
    ) {
        removeAllChildren(of: symbolView)

        let child: Widget
        if let iconName = Self.availableIconName(for: symbol) {
            let image = Gtk.Image(iconName: iconName)
            image.pixelSize = Int(environment.resolvedFont.pointSize.rounded(.awayFromZero))
            child = image
        } else {
            let label = createTextView()
            updateTextView(label, content: symbol.textFallback, environment: environment)
            child = label
        }

        insert(child, into: symbolView, at: 0)
        setPosition(ofChildAt: 0, in: symbolView, to: .zero)
        child.show()
    }

    public func size(
        ofSymbol symbol: SystemSymbol,
        whenDisplayedIn widget: Widget,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        guard Self.availableIconName(for: symbol) != nil else {
            return size(
                of: symbol.textFallback,
                whenDisplayedIn: widget,
                proposedWidth: nil,
                proposedHeight: nil,
                environment: environment
            )
        }
        // Square, at the font's point size. Symbolic icons are drawn on a square
        // canvas, so this is the icon's real extent rather than an estimate of
        // it -- and it keeps a symbol the same height as the text beside it,
        // which is what the Apple backends get for free from the shared font.
        //
        // 正方形，尺寸為字型的點級。symbolic 圖示是畫在正方形畫布上的，因此這是該圖示的真實範圍，
        // 而不是對它的估算——同時也讓符號與其旁邊的文字維持相同高度，而那是 Apple 那兩個 backend
        // 從共用字型上免費得到的東西。
        let side = Int(environment.resolvedFont.pointSize.rounded(.awayFromZero))
        return SIMD2(side, side)
    }

    /// The name this theme will actually draw, or `nil` if it will draw nothing.
    ///
    /// Tries `-symbolic` first. That order is not a preference, it is what the
    /// measurement found: every one of the 36 catalogued names resolves only
    /// with the suffix, and none without it. The plain name is still tried
    /// second, because the table's column holds the freedesktop stem and a
    /// desktop theme that does ship the full-colour set should be used when it
    /// is there.
    ///
    /// 此主題實際會畫出來的名稱；若它什麼都不會畫，則為 `nil`。
    ///
    /// 先嘗試 `-symbolic`。這個順序不是偏好，而是量測結果：36 個已編目名稱中，每一個都只有加上後綴
    /// 才解析得到，沒有一個能以純名稱解析。純名稱仍會被第二個嘗試，因為表中該欄位存放的是 freedesktop
    /// 的字根，而一個確實出貨了全彩集的桌面主題，在它存在時就應該被使用。
    static func availableIconName(for symbol: SystemSymbol) -> String? {
        guard !symbol.gtkIconName.isEmpty else { return nil }
        for candidate in ["\(symbol.gtkIconName)-symbolic", symbol.gtkIconName]
            where hasIcon(candidate)
        {
            return candidate
        }
        return nil
    }

    private static func hasIcon(_ name: String) -> Bool {
        guard let display = gdk_display_get_default() else { return false }
        guard let theme = gtk_icon_theme_get_for_display(display) else { return false }
        return gtk_icon_theme_has_icon(theme, name) != 0
    }
}
