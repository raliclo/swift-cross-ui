import AndroidKit
@_spi(Backends) import SwiftCrossUI
import SwiftJava

/// Scroll offsets from this backend's own `ScrollContainer`, whose inner
/// ScrollView and HorizontalScrollView call a `SwiftAction` from
/// `onScrollChanged` -- a drag, a fling and `scrollTo` alike. The offsets are
/// pixels there and points here, divided by the display density as
/// `originInWindow` divides.
///
/// 從本 backend 自有的 `ScrollContainer` 取得捲動位移：其內部的 ScrollView 與 HorizontalScrollView 在
/// `onScrollChanged` 中呼叫一個 `SwiftAction`——拖曳、甩動與 `scrollTo` 皆然。位移在那裡是像素、在這裡是點，
/// 與 `originInWindow` 一樣除以螢幕密度。
extension AndroidBackend: BackendFeatures.ScrollOffsetReporting {
    public func contentOffset(ofScrollContainer scrollView: Widget) -> SIMD2<Double> {
        guard let container = scrollView.as(ScrollContainer.self) else { return .zero }
        let density = Double(container.getResources().getDisplayMetrics().density)
        guard density > 0 else { return .zero }
        return SIMD2(
            Double(container.contentOffsetX()) / density,
            Double(container.contentOffsetY()) / density
        )
    }

    public func setContentOffsetHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor (SIMD2<Double>) -> Void)?
    ) {
        guard let container = scrollView.as(ScrollContainer.self) else { return }
        guard let handler else {
            container.setScrollAction(nil)
            return
        }
        // The widget, not `container`: the widget is the reference the view
        // graph already keeps across updates, and `as` makes a fresh wrapper.
        // 捕捉 widget 而非 `container`:widget 是 view graph 本來就跨更新保留的參照，`as` 會產生新的包裝。
        container.setScrollAction(
            SwiftAction(environment: Self.env) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handler(self.contentOffset(ofScrollContainer: scrollView))
                }
            }
        )
    }
}

extension ScrollContainer {
    @JavaMethod
    func setScrollAction(_ action: SwiftAction?)

    @JavaMethod
    func contentOffsetX() -> Int32

    @JavaMethod
    func contentOffsetY() -> Int32
}
