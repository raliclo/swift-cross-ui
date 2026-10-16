@_spi(Backends) import SwiftCrossUI
import WinUI

/// Scroll offsets from the ScrollViewer's `HorizontalOffset`/`VerticalOffset`,
/// with `ViewChanged` as the call on every move: it fires during a scroll
/// (`IsIntermediate`) as well as at its end, for touch, wheel, scroll bar,
/// keyboard and `StartBringIntoView` (which is how `scrollContainer` scrolls).
/// Effective pixels, the units layout uses here.
///
/// **Not compiled on the Mac that wrote it (2026-10-17)**; WinUIBackend does
/// not build there (queue item 25). The names are the generated bindings' in
/// swift-winui: `ScrollViewer.horizontalOffset`, `.verticalOffset`, and the
/// `viewChanged` event with `addHandler`, the shape
/// `WinUIBackend+Refreshable.swift` uses for `click`.
///
/// 從 ScrollViewer 的 `HorizontalOffset`/`VerticalOffset` 取得捲動位移，以 `ViewChanged` 作為每次移動時的
/// 呼叫：它在捲動途中(`IsIntermediate`)與結束時都會觸發——觸控、滾輪、捲軸、鍵盤與 `StartBringIntoView`
/// (`scrollContainer` 就是這樣捲動的)皆然。單位是 effective pixel,即這裡排版所用的單位。**撰寫它的 Mac
/// 上未編譯(2026-10-17)**;WinUIBackend 在那裡建不起來(queue 第 25 項)。名稱取自 swift-winui 產生的繫結:
/// `ScrollViewer.horizontalOffset`、`.verticalOffset`,以及以 `addHandler` 訂閱的 `viewChanged` 事件,
/// 與 `WinUIBackend+Refreshable.swift` 訂閱 `click` 的形狀相同。
extension WinUIBackend: BackendFeatures.ScrollOffsetReporting {
    public func contentOffset(ofScrollContainer scrollView: Widget) -> SIMD2<Double> {
        guard let viewer = scrollView as? WinUI.ScrollViewer else { return .zero }
        return SIMD2(viewer.horizontalOffset, viewer.verticalOffset)
    }

    public func setContentOffsetHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor (SIMD2<Double>) -> Void)?
    ) {
        guard let viewer = scrollView as? WinUI.ScrollViewer else { return }
        let key = ObjectIdentifier(viewer)
        Self.scrollOffsetHandlers[key] = handler
        guard handler != nil else { return }
        // Subscribed once per viewer; an identifier whose viewer died is a new viewer.
        // 每個 viewer 只訂閱一次;viewer 已死的識別碼代表一個新的 viewer。
        if let subscribed = Self.scrollOffsetSubscriptions[key], subscribed.viewer === viewer {
            return
        }
        Self.scrollOffsetSubscriptions[key] = WeakScrollViewer(viewer: viewer)
        viewer.viewChanged.addHandler { [weak viewer] _, _ in
            MainActor.assumeIsolated {
                guard let viewer else { return }
                Self.scrollOffsetHandlers[ObjectIdentifier(viewer)]?(
                    SIMD2(viewer.horizontalOffset, viewer.verticalOffset)
                )
            }
        }
    }

    struct WeakScrollViewer {
        weak var viewer: WinUI.ScrollViewer?
    }

    nonisolated(unsafe) static var scrollOffsetHandlers:
        [ObjectIdentifier: @MainActor (SIMD2<Double>) -> Void] = [:]

    nonisolated(unsafe) static var scrollOffsetSubscriptions: [ObjectIdentifier: WeakScrollViewer] = [:]
}
