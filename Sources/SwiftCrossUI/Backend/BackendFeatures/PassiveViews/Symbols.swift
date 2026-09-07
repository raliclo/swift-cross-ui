extension BackendFeatures {
    /// Drawing one of the toolkit's ``SystemSymbol`` values.
    ///
    /// Deliberately shaped like ``TextViews`` rather than like ``Images``: a
    /// symbol is a glyph at the current font size, not a bitmap with pixel
    /// dimensions, so the size comes from the environment exactly as a string's
    /// does and there is no `targetWidth` to scale to.
    ///
    /// **The backend decides whether to draw the glyph or the fallback, and that
    /// is the entire point of the feature.** Whether a symbol can be drawn is
    /// not known to SwiftCrossUI and cannot be answered at build time: GTK 4
    /// ships 138 icons and the desktop's theme supplies the rest, and Segoe
    /// Fluent Icons is absent from Windows 10 by default. Both produce a blank
    /// where the icon belongs, silently, if nobody asks first. So each backend
    /// asks its own platform -- `gtk_icon_theme_has_icon`, a font lookup, a
    /// resource identifier -- and draws ``SystemSymbol/textFallback`` when the
    /// answer is no. A caller therefore always gets something visible, and never
    /// has to know which backend it is on.
    ///
    /// 繪製本工具組 ``SystemSymbol`` 中的某一個值。
    ///
    /// 刻意寫成與 ``TextViews`` 相同的形狀，而非 ``Images`` 的形狀：符號是「目前字級下的一個字符」，
    /// 不是帶有像素尺寸的點陣圖，因此其尺寸與字串一樣來自 environment，也沒有需要縮放到的
    /// `targetWidth`。
    ///
    /// **由 backend 決定要畫字符還是畫退路，而這正是本 feature 的全部意義。** 某個符號畫不畫得出來，
    /// SwiftCrossUI 並不知道，而且在建置期也無從回答：GTK 4 只內建 138 個圖示、其餘由桌面主題提供，
    /// 而 Windows 10 預設沒有 Segoe Fluent Icons。若沒有人事先詢問，兩者都會在圖示該出現的位置靜默地
    /// 留下空白。因此每個 backend 各自詢問自己的平台——`gtk_icon_theme_has_icon`、一次字型查詢、
    /// 一個資源識別碼——並在答案為否時改畫 ``SystemSymbol/textFallback``。呼叫端因而總是得到看得見的
    /// 東西，也永遠不需要知道自己身在哪一個 backend 上。
    @MainActor
    public protocol Symbols: TextViews {
        /// A view that draws one symbol. Its content is set by
        /// ``updateSymbolView(_:symbol:environment:)``, never by this call.
        /// 一個繪製單一符號的 view。其內容由 ``updateSymbolView(_:symbol:environment:)`` 設定，
        /// 而非由本呼叫設定。
        func createSymbolView() -> Widget

        /// Draws `symbol`, or its ``SystemSymbol/textFallback`` if this platform
        /// cannot produce the glyph.
        /// 繪製 `symbol`；若此平台無法產生該字符，則改繪其 ``SystemSymbol/textFallback``。
        func updateSymbolView(
            _ symbolView: Widget,
            symbol: SystemSymbol,
            environment: EnvironmentValues
        )

        /// How large `symbol` will be drawn -- of whichever of the two the
        /// backend has decided to draw, since a fallback string is rarely the
        /// size of the glyph it replaces.
        /// `symbol` 將被繪製出來的大小——且是「backend 決定要畫的那一個」的大小，因為退路字串
        /// 極少與它所替代的字符同尺寸。
        func size(
            ofSymbol symbol: SystemSymbol,
            whenDisplayedIn widget: Widget,
            environment: EnvironmentValues
        ) -> SIMD2<Int>
    }
}

// MARK: Default Implementations

extension BackendFeatures.Symbols {
    /// Draws every symbol as its ``SystemSymbol/textFallback``.
    ///
    /// **This is the feature working, not a backend going without it.** A
    /// terminal draws `+` for `add` because `+` is what a terminal has, and the
    /// fifth column of the symbol table exists to say so; the same default is
    /// the right answer for any backend whose platform has no icon set at all.
    /// What it is not is a blank where an icon belongs, which is the outcome
    /// this whole feature was shaped to make unreachable.
    ///
    /// A backend that can do better overrides all three methods together. It
    /// cannot override only `size(ofSymbol:...)`, because the size has to
    /// describe whichever of the glyph and the fallback that backend actually
    /// drew, and only the backend knows which one that was.
    ///
    /// 把每一個符號都畫成它的 ``SystemSymbol/textFallback``。
    ///
    /// **這是功能正常運作，不是某個 backend 沒有這項功能。** 終端機為 `add` 畫出 `+`，是因為 `+`
    /// 正是終端機所擁有的東西，而符號表的第五欄存在的意義就是說明這件事；對任何「平台上根本沒有圖示
    /// 集」的 backend 而言，同一個預設也是正確答案。它唯一不是的東西，是「在圖示該出現的位置留下
    /// 空白」——而整項功能的形狀，正是為了讓那個結果無從發生而設計的。
    ///
    /// 能做得更好的 backend 應**三個方法一起覆寫**。它不能只覆寫 `size(ofSymbol:...)`，因為該尺寸
    /// 必須描述「該 backend 實際畫出來的是字符還是退路」，而只有 backend 自己知道那是哪一個。
    public func createSymbolView() -> Widget {
        createTextView()
    }

    public func updateSymbolView(
        _ symbolView: Widget,
        symbol: SystemSymbol,
        environment: EnvironmentValues
    ) {
        updateTextView(symbolView, content: symbol.textFallback, environment: environment)
    }

    public func size(
        ofSymbol symbol: SystemSymbol,
        whenDisplayedIn widget: Widget,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        size(
            of: symbol.textFallback,
            whenDisplayedIn: widget,
            proposedWidth: nil,
            proposedHeight: nil,
            environment: environment
        )
    }
}
