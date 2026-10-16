import AppKit
@_spi(Backends) import SwiftCrossUI

/// Scroll offsets from the clip view, which is where AppKit keeps the scroll
/// position: it posts `boundsDidChangeNotification` whenever it moves, by
/// wheel, scroll bar, keyboard or `scroll(to:)` alike.
///
/// The y is the distance from the document's top to the clip's top, converted
/// through both views' coordinates: the document here is an NSStackView that
/// is NOT flipped, and its frame is offset inside the clip view.
///
/// 從 clip view 取得捲動位移——AppKit 就是把捲動位置存在那裡：它每次移動——滾輪、捲軸、鍵盤或 `scroll(to:)`
/// 皆然——都會發出 `boundsDidChangeNotification`。y 是文件頂端到 clip 頂端的距離，經兩個 view 的座標換算:
/// 這裡的文件是**未** flipped 的 NSStackView,而它的 frame 在 clip view 裡有位移。
extension AppKitBackend: BackendFeatures.ScrollOffsetReporting {
    public func contentOffset(ofScrollContainer scrollView: Widget) -> SIMD2<Double> {
        guard let scrollView = scrollView as? NSScrollView, let document = scrollView.documentView
        else { return .zero }
        // Measured between the two top-leading corners rather than read off the
        // clip view's bounds: the document is not at the clip's origin. Read off
        // the bounds, P101 reported 700 while its first rows were on screen --
        // the bounds started at y 0 with the document's frame at y -700, its top
        // pinned to the clip's top by a constraint (2026-10-17).
        // 在兩個左上角之間量測，而不是直接讀 clip view 的 bounds:文件並不在 clip 的原點。直接讀 bounds 時，
        // P101 在第一列就在畫面上時回報 700——bounds 從 y 0 開始，文件的 frame 卻在 y -700,它的頂端由
        // constraint 釘在 clip 的頂端(2026-10-17)。
        let clip = scrollView.contentView
        let documentTop = document.convert(
            NSPoint(
                x: document.bounds.minX,
                y: document.isFlipped ? document.bounds.minY : document.bounds.maxY
            ),
            to: clip
        )
        let visible = clip.bounds
        let y =
            clip.isFlipped
            ? visible.minY - documentTop.y
            : documentTop.y - visible.maxY
        return SIMD2(Double(visible.minX - documentTop.x), Double(y))
    }

    public func setContentOffsetHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor (SIMD2<Double>) -> Void)?
    ) {
        guard let scrollView = scrollView as? NSScrollView else { return }
        let key = ObjectIdentifier(scrollView)
        guard let handler else {
            if let observer = Self.scrollObservers.removeValue(forKey: key) {
                NotificationCenter.default.removeObserver(observer.token)
            }
            return
        }
        if let existing = Self.scrollObservers[key] {
            // An identifier outlives its object: a new scroll view at a freed
            // address must not inherit the dead one's observer.
            // 識別碼比物件活得久：落在已釋放位址上的新捲動視圖，不可繼承舊者的觀察者。
            if existing.box.scrollView === scrollView {
                existing.box.handler = handler
                return
            }
            NotificationCenter.default.removeObserver(existing.token)
        }
        let box = ScrollHandlerBox(handler: handler)
        box.scrollView = scrollView
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        let token = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clip,
            queue: nil
        ) { [weak self, weak scrollView] _ in
            MainActor.assumeIsolated {
                guard let self, let scrollView else { return }
                box.handler(self.contentOffset(ofScrollContainer: scrollView))
            }
        }
        Self.scrollObservers[key] = (token, box)
    }

    final class ScrollHandlerBox: @unchecked Sendable {
        var handler: @MainActor (SIMD2<Double>) -> Void
        weak var scrollView: NSScrollView?

        init(handler: @escaping @MainActor (SIMD2<Double>) -> Void) {
            self.handler = handler
        }
    }

    /// One observer per scroll view, replaced in place on every update.
    /// 每個捲動視圖一個觀察者，每次更新時就地替換 handler。
    nonisolated(unsafe) static var scrollObservers:
        [ObjectIdentifier: (token: any NSObjectProtocol, box: ScrollHandlerBox)] = [:]
}
