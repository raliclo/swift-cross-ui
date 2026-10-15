import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

#if os(macOS)
    import AppKit
#endif

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
        if let drawn = Self.sfSymbolTexture(for: symbol, in: environment) {
            let picture = Gtk.Picture()
            picture.setPaintable(drawn.texture)
            child = picture
        } else if let iconName = Self.availableIconName(for: symbol) {
            let image = Gtk.Image(iconName: iconName)
            image.pixelSize = Int(environment.resolvedFont.pointSize.rounded(.awayFromZero))
            child = image
        } else {
            let label = createTextView()
            updateTextView(label, content: symbol.textFallback, environment: environment)
            child = label
        }

        // The child needs its own size. `Image.commit` sizes the widget that
        // `createSymbolView()` returned, and here that is the container -- so
        // without this the child sits at its default extent, which on Android is
        // zero and draws nothing at all. The Apple backends never hit this
        // because they return the drawing view itself and the size lands on it.
        //
        // After `insert`, never before. `setSize` begins with
        // `guard let layoutParams = widget.getLayoutParams() else { return }`,
        // and a view that has not been added to a parent has none -- so the
        // call returns having done nothing, silently, and the symbol is laid
        // out with space reserved for it and nothing drawn in that space.
        // That is what the first attempt at this fix did, and the screenshot
        // afterwards was identical to the one before it.
        //
        // 必須在 `insert` 之後,絕不能在之前。`setSize` 的第一行是
        // `guard let layoutParams = widget.getLayoutParams() else { return }`,
        // 而一個尚未被加入父層的 view 沒有 layout params——於是該呼叫什麼都沒做就返回了,
        // 而且是靜默的,結果就是符號的位置被保留了空間、空間裡卻什麼都沒畫。這正是本修正第一次
        // 嘗試時所做的事,而其後的截圖與修正前那張一模一樣。
        //
        // Computed rather than remembered: the size depends only on the symbol
        // and the environment, both of which are arguments here, so there is no
        // state to keep in step.
        //
        // 子 widget 需要有自己的尺寸。`Image.commit` 設定的是 `createSymbolView()` 所回傳的那個
        // widget,而在此處那是容器——因此少了這一步,子 widget 就會停留在其預設範圍,而那在 Android
        // 上是零,於是什麼都畫不出來。Apple 那兩個 backend 不會遇到這件事,因為它們回傳的就是負責繪製
        // 的那個 view,尺寸直接落在它身上。
        //
        // 這裡是「算出來」而非「記下來」:該尺寸只取決於符號與 environment,而兩者都是此處的參數,
        // 因此沒有任何需要保持同步的狀態。
        insert(child, into: symbolView, at: 0)
        setPosition(ofChildAt: 0, in: symbolView, to: .zero)
        setSize(
            of: child,
            to: size(ofSymbol: symbol, whenDisplayedIn: symbolView, environment: environment)
        )
        child.show()
    }

    public func size(
        ofSymbol symbol: SystemSymbol,
        whenDisplayedIn widget: Widget,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        if let drawn = Self.sfSymbolTexture(for: symbol, in: environment) {
            return drawn.size
        }
        guard Self.availableIconName(for: symbol) != nil else {
            // Measured through a label styled as the one that draws it. `widget` is
            // the container, whose font is GTK's default rather than the
            // environment's, so the name came out a few points short and the
            // label ellipsized it ("definitely.not.a.sy…", P47, 2026-10-16).
            // 以一個與實際繪製者相同樣式的 label 量測。`widget` 是容器，其字型是 GTK 預設而非
            // environment 的，因此名稱量短了幾點,label 便把它省略了(P47,2026-10-16)。
            let label = createTextView()
            updateTextView(label, content: symbol.textFallback, environment: environment)
            return size(
                of: symbol.textFallback,
                whenDisplayedIn: label,
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

    /// The SF Symbol itself, drawn by AppKit, when GTK runs on macOS.
    ///
    /// GTK on macOS is in a process that can draw the system's symbols, and
    /// the icon theme cannot: Homebrew's GTK ships GTK's own 138 icons, so
    /// 18 of P47's 36 symbols fell back to their names, squeezed into a
    /// glyph-sized cell ("Pho...", "M..."; 2026-10-16). Drawn here at the font's
    /// point size and weight-free, tinted with the foreground colour, at 2x, and
    /// handed to GTK as a texture -- the picture AppKitBackend shows.
    ///
    /// GTK 在 macOS 上所在的行程畫得出系統的符號，而圖示主題畫不出來:Homebrew 的 GTK 只帶 GTK 自己的
    /// 138 個圖示，因此 P47 的 36 個符號中有 18 個退回成名稱，被擠進一個字形大小的格子裡。這裡以字型點級、
    /// 前景色、2 倍解析度由 AppKit 畫出，再以 texture 交給 GTK——與 AppKitBackend 顯示的是同一張圖。
    static func sfSymbolTexture(
        for symbol: SystemSymbol,
        in environment: EnvironmentValues
    ) -> (texture: OpaquePointer, size: SIMD2<Int>)? {
        #if os(macOS)
            guard !symbol.sfSymbol.isEmpty,
                let base = NSImage(
                    systemSymbolName: symbol.sfSymbol,
                    accessibilityDescription: symbol.name
                )
            else { return nil }
            let font = environment.resolvedFont
            let image =
                base.withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: CGFloat(font.pointSize), weight: .regular)
                ) ?? base
            let width = max(Int(image.size.width.rounded(.up)), 1)
            let height = max(Int(image.size.height.rounded(.up)), 1)
            let scale = 2
            guard
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: width * scale,
                    pixelsHigh: height * scale,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: width * scale * 4,
                    bitsPerPixel: 32
                ),
                let context = NSGraphicsContext(bitmapImageRep: rep)
            else { return nil }
            let colour = (environment.foregroundColor ?? environment.suggestedForegroundColor)
                .resolve(in: environment)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let bounds = NSRect(x: 0, y: 0, width: width * scale, height: height * scale)
            image.draw(in: bounds)
            NSColor(
                srgbRed: CGFloat(colour.red),
                green: CGFloat(colour.green),
                blue: CGFloat(colour.blue),
                alpha: CGFloat(colour.opacity)
            ).setFill()
            bounds.fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
            guard let bytes = rep.bitmapData else { return nil }
            // The bitmap is premultiplied; a GdkPixbuf with alpha is straight.
            // 點陣圖是預乘的;帶 alpha 的 GdkPixbuf 是未預乘的。
            let count = width * scale * height * scale * 4
            var rgba = [UInt8](repeating: 0, count: count)
            for index in stride(from: 0, to: count, by: 4) {
                let alpha = Int(bytes[index + 3])
                rgba[index + 3] = UInt8(alpha)
                guard alpha > 0 else { continue }
                for channel in 0..<3 {
                    rgba[index + channel] = UInt8(
                        min(255, (Int(bytes[index + channel]) * 255 + alpha / 2) / alpha)
                    )
                }
            }
            let texture = texture(fromStraightRGBA: rgba, width: width * scale, height: height * scale)
            return (texture, SIMD2(width, height))
        #else
            return nil
        #endif
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
