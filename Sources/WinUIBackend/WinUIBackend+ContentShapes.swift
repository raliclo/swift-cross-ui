@_spi(Backends) import SwiftCrossUI
import WinUI
import WindowsFoundation

extension WinUIBackend: BackendFeatures.ContentShapes {
    public func setContentShape(of widget: Widget, to region: HitRegion?) {
        WinUIContentShapes.set(region, for: widget)
    }
}

/// Content shapes on WinUI.
///
/// XAML hit-tests rendered geometry and offers no per-element override, and
/// `UIElement.Clip` takes only a rectangle. What does take an element and its
/// whole subtree out of hit testing is `isHitTestVisible`. So a shaped
/// element's `isHitTestVisible` follows the pointer: the window's root grid
/// receives every `pointerMoved` that bubbles up (it has a background, so it
/// is hit wherever nothing above it is), and each move sets every shaped
/// element to whether the pointer is inside its shape. XAML hit-tests each
/// press afresh, so a press outside the shape then reaches whatever is
/// underneath.
///
/// A press can arrive with no move before it -- a touch landing -- so tap
/// targets also check the shape in their handlers (``accepts(_:at:)``): such
/// a press outside the shape is then not a tap, though it does not reach the
/// element below.
///
/// `allowsHitTesting(false)` also sets `isHitTestVisible`, so it goes through
/// ``setAllowsHitTesting(_:for:)`` and both are combined.
///
/// WinUI 上的 content shape。
///
/// XAML 依繪出的幾何做命中測試，沒有逐元素的覆寫，而 `UIElement.Clip` 只接受矩形。真正能把一個元素及其
/// 整棵子樹排除在命中測試之外的是 `isHitTestVisible`。因此有形狀元素的 `isHitTestVisible` 跟隨指標：
/// 視窗的根 grid 會收到每個向上冒泡的 `pointerMoved`(它有背景，所以凡是上方沒有東西之處都會命中它),
/// 而每次移動都把每個有形狀的元素設為「指標是否在其形狀內」。XAML 對每次按壓都重新做命中測試，因此形狀外
/// 的按壓接著就會到達下方的東西。
///
/// 按壓可能在之前沒有任何移動的情況下抵達——例如觸控落下——因此點擊目標也在 handler 中檢查形狀
/// (``accepts(_:at:)``):這樣的形狀外按壓便不算點擊，只是它不會到達下方的元素。
///
/// `allowsHitTesting(false)` 同樣設定 `isHitTestVisible`,因此它經由 ``setAllowsHitTesting(_:for:)``,
/// 兩者合併計算。
enum WinUIContentShapes {
    final class Entry {
        weak var element: WinUI.UIElement?
        var region: HitRegion?
        var inside = true
        var allowsHitTesting = true

        init(element: WinUI.UIElement) {
            self.element = element
        }

        func apply() {
            guard let element else { return }
            let visible = allowsHitTesting && (region == nil || inside)
            if element.isHitTestVisible != visible {
                element.isHitTestVisible = visible
            }
        }
    }

    /// Keyed by identity; an entry whose element has gone is dropped on the
    /// next change. / 以識別碼為鍵;元素已消失的項目會在下一次變更時移除。
    nonisolated(unsafe) static var entries: [ObjectIdentifier: Entry] = [:]
    /// How many entries have a region, so moves cost nothing without shapes.
    /// 有區域的項目數，讓沒有形狀時移動不需任何成本。
    nonisolated(unsafe) static var shapedCount = 0

    static func entry(for element: WinUI.UIElement) -> Entry {
        let key = ObjectIdentifier(element)
        if let entry = entries[key], entry.element === element {
            return entry
        }
        entries = entries.filter { $0.value.element != nil }
        let entry = Entry(element: element)
        entries[key] = entry
        return entry
    }

    static func recount() {
        shapedCount = entries.values.filter { $0.region != nil && $0.element != nil }.count
    }

    static func set(_ region: HitRegion?, for element: WinUI.UIElement) {
        let entry = entry(for: element)
        entry.region = region
        if region == nil { entry.inside = true }
        entry.apply()
        recount()
    }

    static func setAllowsHitTesting(_ allowsHitTesting: Bool, for element: WinUI.UIElement) {
        let entry = entry(for: element)
        entry.allowsHitTesting = allowsHitTesting
        entry.apply()
    }

    static func pointerMoved(_ args: PointerRoutedEventArgs?) {
        guard shapedCount > 0, let args else { return }
        for entry in entries.values {
            guard let region = entry.region, let element = entry.element,
                let position = try? args.getCurrentPoint(element)?.position
            else { continue }
            entry.inside = region.contains([Double(position.x), Double(position.y)])
            entry.apply()
        }
    }

    /// Whether a press at `position`, relative to `element`, is inside its
    /// shape; true without a shape or a position.
    /// 相對於 `element` 位於 `position` 的按壓是否在其形狀內；沒有形狀或沒有位置時為 true。
    static func accepts(_ element: WinUI.UIElement, at position: Point?) -> Bool {
        guard shapedCount > 0, let position,
            let region = entries[ObjectIdentifier(element)]?.region
        else { return true }
        return region.contains([Double(position.x), Double(position.y)])
    }
}
