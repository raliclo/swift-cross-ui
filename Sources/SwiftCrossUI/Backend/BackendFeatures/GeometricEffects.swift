extension BackendFeatures {
    /// Backend methods for drawing a view somewhere other than where it was
    /// laid out.
    ///
    /// These are used by ``View/offset(x:y:)``, ``View/rotationEffect(_:anchor:)``,
    /// ``View/scaleEffect(_:anchor:)`` and ``View/transformEffect(_:)``.
    ///
    /// Separate from ``BackendFeatures/VisualEffects`` on purpose. A compositing
    /// effect changes what a view's pixels look like; this changes where they
    /// land, which means it also changes where the view can be clicked. A
    /// backend can easily support one and not the other -- GTK expresses these
    /// two through different mechanisms -- and one protocol covering both would
    /// force a backend to implement both to offer either.
    ///
    /// 用於「把 view 畫在它被排版位置以外之處」的 backend 方法。
    ///
    /// 刻意與 ``BackendFeatures/VisualEffects`` 分開。合成效果改變的是 view 的像素外觀；此處改變的
    /// 則是那些像素落在哪裡——也就連帶改變了 view 可被點擊的位置。某個 backend 完全可能支援其中
    /// 一種而不支援另一種（GTK 就是以兩套不同機制表達這兩者），而把兩者合為一個 protocol，等於
    /// 逼迫 backend 為了提供其中一種而必須兩種都實作。
    @MainActor
    public protocol GeometricEffects: Core {
        /// Create a container capable of transforming its child.
        ///
        /// If no container is necessary, this method is allowed to return
        /// `child` unmodified.
        ///
        /// - Parameters:
        ///   - child: The widget being wrapped to transform.
        func createGeometricEffectContainer(wrapping child: Widget) -> Widget

        /// Draw a widget under an affine transform, replacing any transform
        /// previously set on it.
        ///
        /// The transform arrives already resolved about its anchor, in the
        /// widget's own coordinate space with the origin at its top left. The
        /// anchor is not passed separately because resolving it needs the view's
        /// size, which the layout system knows and the backend would otherwise
        /// have to be told; doing it once here also means a backend never has to
        /// reproduce SwiftUI's anchor arithmetic.
        ///
        /// 傳入的 transform 已針對其錨點解析完成，位於該 widget 自身的座標空間中、原點在左上角。
        /// 錨點不另行傳遞，因為解析錨點需要 view 的尺寸——那是 layout 系統知道、而 backend 原本
        /// 必須被額外告知的資訊；在此處一次做完，也代表沒有任何 backend 需要重現 SwiftUI 的錨點
        /// 運算。
        ///
        /// - Parameters:
        ///   - transform: The transform to draw under. ``AffineTransform/identity``
        ///     means remove any transform.
        ///   - widget: The widget to transform.
        func setGeometricEffect(_ transform: AffineTransform, ofWidget widget: Widget)
    }
}
