extension BackendFeatures {
    /// Backend methods for drawing SVG `<text>` with the platform's text engine.
    ///
    /// ``Image`` uses this when it rasterises an ``SVGDocument``: the core
    /// draws every shape itself and asks the backend only for the coverage of
    /// each text run (see ``SVGTextMaskRequest``), then applies the SVG's colour,
    /// opacity and paint order. A backend without it still shows the text's
    /// place outlined in magenta, and the document's diagnostics say why.
    ///
    /// 以平台文字引擎繪製 SVG `<text>` 的 backend 方法。``Image`` 點陣化 ``SVGDocument`` 時會用到它：
    /// 核心自己畫所有形狀，只向 backend 要每段文字的覆蓋率(見 ``SVGTextMaskRequest``),再套用 SVG 的
    /// 顏色、不透明度與繪製順序。沒有它的 backend 仍會以洋紅色框出文字的位置，文件的診斷會說明原因。
    @MainActor
    public protocol SVGText: Images {
        /// The coverage of one text run, `request.width * request.height`
        /// bytes, top row first; nil when the platform could not draw it.
        /// 一段文字的覆蓋率，`request.width * request.height` 個位元組、最上面一列在前；平台畫不出來時為 nil。
        func svgTextMask(_ request: SVGTextMaskRequest) -> [UInt8]?
    }
}
