extension View {
    /// Draws a border of the given colour and width around this view.
    ///
    /// The border is drawn *inside* the view's bounds and does not change the
    /// layout, which is SwiftUI's behaviour and is worth stating because the
    /// obvious alternative -- padding plus a background -- would grow the view.
    /// If you want the content pushed inwards, add `.padding` yourself.
    ///
    /// Composed rather than given a backend protocol of its own: an overlaid
    /// stroked ``Rectangle`` is exactly what a border is, and every backend that
    /// can draw a path already draws it. Adding
    /// `BackendFeatures.Borders` would give six backends a new method to
    /// implement for something they can all already express.
    ///
    /// - Parameters:
    ///   - color: The border's colour.
    ///   - width: The border's thickness, in points.
    ///
    /// 在此 view 周圍繪製指定顏色與寬度的邊框。
    ///
    /// 邊框繪製於 view 的邊界**之內**，且不改變版面配置——這是 SwiftUI 的行為，值得明說，因為那個
    /// 顯而易見的替代做法（padding 加上 background）會讓 view 變大。若希望內容被往內推，請自行加上
    /// `.padding`。
    ///
    /// 此處以組合實作，而非為它另立 backend protocol：一個疊加其上、帶描邊的 ``Rectangle`` 本身就是
    /// 邊框的定義，而任何能繪製 path 的 backend 都早已畫得出來。若新增
    /// `BackendFeatures.Borders`，等於要六個 backend 為一件它們全都已能表達的事各實作一個新方法。
    public func border(_ color: Color, width: Double = 1) -> some View {
        overlay {
            // Inset by half the width, because a stroke straddles the path it
            // follows. Without this the outer half of the line falls outside the
            // view's bounds, where a clipping ancestor cuts it off and a border
            // asked for as 2 points draws as 1.
            // 內縮寬度的一半，因為描邊是跨在其所依循的路徑兩側的。若無此內縮，線條外側的一半會落在
            // view 邊界之外，被具裁切能力的祖先切掉——於是要求 2 點寬的邊框只會畫出 1 點。
            Rectangle()
                .inset(by: width / 2)
                .stroke(color, style: StrokeStyle(width: width))
        }
    }
}
