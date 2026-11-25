import DebugFeatures
import Foundation
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
/// A press can arrive with no move before it -- a touch landing -- and is then
/// hit-tested with the flags of an earlier position. Every handler of this
/// backend therefore decides the press again at the press itself
/// (``admits(_:_:)``), and the root grid forwards such a press to the gestures
/// of the element it should have reached; see the extension below.
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
/// 按壓可能在之前沒有任何移動的情況下抵達——例如觸控落下——此時它以先前位置的旗標做命中測試。因此本
/// backend 的每個 handler 都在按壓當下重新決定(``admits(_:_:)``),而根 grid 會把這樣的按壓轉交給它本應
/// 抵達之元素的手勢；見下方的 extension。
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
        diagnose("set \(type(of: element)) \(ObjectIdentifier(element).hashValue) region=\(describe(region))")
        entry.region = region
        if region == nil { entry.inside = true }
        entry.apply()
        recount()
    }

    /// TEMPORARY diagnostics for the WinUI hover-versus-content-shape failure (P131, CI
    /// run 45561431566): which elements get a region, and what each hover event sees.
    /// Written only by binaries built with SCUI_DEBUG, as CI's test apps are.
    /// 暫時性診斷，追查 WinUI 懸停與 content shape 的失敗(P131,CI run 45561431566):哪些元素拿到形狀，以及每個
    /// 懸停事件看到什麼。只有以 SCUI_DEBUG 建置的執行檔(如 CI 的測試 app)才會寫出。
    static func diagnose(_ message: @autoclosure () -> String) {
        guard DebugFeatures.isCompiledIn else { return }
        FileHandle.standardError.write(Data(("-contentshape: " + message() + "\n").utf8))
    }

    static func describe(_ region: HitRegion?) -> String {
        guard let region else { return "nil" }
        let points = region.contours.flatMap { $0 }
        guard let first = points.first else { return "empty" }
        let low = points.reduce(first) { SIMD2(min($0.x, $1.x), min($0.y, $1.y)) }
        let high = points.reduce(first) { SIMD2(max($0.x, $1.x), max($0.y, $1.y)) }
        return "\(points.count)pts (\(Int(low.x)),\(Int(low.y)))-(\(Int(high.x)),\(Int(high.y)))"
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
}

// MARK: Presses with no move before them, hover, forwarding

/// What a pointer event means for a shaped tree, decided at the event itself.
///
/// `isHitTestVisible` follows the pointer's moves, so a press that arrives with
/// none before it -- a touch landing, which has no hover -- is hit-tested with
/// the flags of the last position, and XAML hit-tests a press before any
/// handler runs. Each press is therefore decided again here: every shaped
/// element is brought up to date for the press position, and
/// `VisualTreeHelper.findElementsInHostCoordinates` -- XAML's own hit test,
/// with those flags -- names the element the press should have reached.
///
/// - A handler of this backend takes the press only if its element is on that
///   element's chain and the point is inside its shape (``admits(_:_:)``), so
///   a press XAML sent to the wrong element is refused there.
/// - The window's root grid sees the presses that bubble up to it. When the
///   element XAML hit differs from the fresh one, the press, the moves and the
///   release of that pointer are forwarded to the gestures registered on the
///   fresh element's chain below the point where the two chains meet
///   (``setForwarded(_:on:handler:)``): taps, long presses, tap-and-long-press,
///   mouse-style drags and context menus.
///
/// 在事件本身決定一個指標事件對有形狀之樹的意義。
///
/// `isHitTestVisible` 跟隨指標的移動，因此之前沒有任何移動就抵達的按壓——觸控落下，它沒有懸停——會以上一個
/// 位置的旗標做命中測試，而 XAML 在任何 handler 執行前就已對按壓做了命中測試。因此每次按壓都在此重新決定：
/// 每個有形狀的元素都更新到按壓的位置，再由 `VisualTreeHelper.findElementsInHostCoordinates`——XAML 自己的
/// 命中測試，使用那些旗標——指出這次按壓本應抵達的元素。
///
/// - 本 backend 的 handler 只有在其元素位於該元素的鏈上、且該點在其形狀內時才接下按壓(``admits(_:_:)``),
///   因此被 XAML 送錯元素的按壓會在那裡被拒絕。
/// - 視窗的根 grid 會看到冒泡到它的按壓。當 XAML 命中的元素與重新挑選的不同時，該指標的按下、移動與放開會
///   轉交給新元素鏈上、兩條鏈交會點以下所登記的手勢(``setForwarded(_:on:handler:)``):點按、長按、點按或
///   長按、滑鼠式拖曳與內容選單。
extension WinUIContentShapes {
    enum Phase {
        case pressed
        case moved
        case released
    }

    /// Runs for a forwarded event with the point in the element's coordinates.
    /// 以元素座標中的點，為被轉交的事件執行。
    typealias ForwardedHandler = (_ phase: Phase, _ point: SIMD2<Double>) -> Void

    final class Forwarded {
        weak var element: WinUI.UIElement?
        var handlers: [String: ForwardedHandler] = [:]

        init(element: WinUI.UIElement) {
            self.element = element
        }
    }

    final class Misdirected {
        weak var fresh: WinUI.UIElement?
        weak var stale: WinUI.UIElement?
        let pointerId: UInt32

        init(fresh: WinUI.UIElement, stale: WinUI.UIElement, pointerId: UInt32) {
            self.fresh = fresh
            self.stale = stale
            self.pointerId = pointerId
        }
    }

    nonisolated(unsafe) static var forwarded: [ObjectIdentifier: Forwarded] = [:]
    nonisolated(unsafe) static var misdirected: Misdirected?

    /// Registers (or with `nil` removes) what a forwarded press means to the
    /// gesture `kind` on `element`. / 登記(或以 `nil` 移除)被轉交的按壓對 `element` 上 `kind` 手勢的意義。
    static func setForwarded(_ kind: String, on element: WinUI.UIElement, handler: ForwardedHandler?) {
        let key = ObjectIdentifier(element)
        if let record = forwarded[key], record.element === element {
            record.handlers[kind] = handler
            return
        }
        guard let handler else { return }
        forwarded = forwarded.filter { $0.value.element != nil }
        let record = Forwarded(element: element)
        record.handlers[kind] = handler
        forwarded[key] = record
    }

    /// Whether `element` is `descendant` or one of its ancestors.
    /// `element` 是否就是 `descendant` 或其祖先之一。
    static func isAncestorOrSelf(_ element: WinUI.UIElement, of descendant: WinUI.UIElement) -> Bool {
        var current: WinUI.DependencyObject? = descendant
        while let candidate = current {
            if candidate === element { return true }
            current = try? VisualTreeHelper.getParent(candidate)
        }
        return false
    }

    /// The element XAML hit-tests at `windowPoint` now, topmost first.
    /// XAML 此刻在 `windowPoint` 命中測試所得的最上層元素。
    static func topElement(at windowPoint: Point, near element: WinUI.UIElement) -> WinUI.UIElement? {
        guard let root = element.xamlRoot?.content,
            let elements = try? VisualTreeHelper.findElementsInHostCoordinates(windowPoint, root),
            let iterator = elements.first(), iterator.hasCurrent
        else { return nil }
        return iterator.current
    }

    /// Whether `region`, set on `element`, or that of any shaped element above
    /// it, leaves out a pointer event's position.
    /// 設在 `element` 上的區域，或其上任何有形狀元素的區域，是否排除了某指標事件的位置。
    static func excludes(_ element: WinUI.UIElement, position: (WinUI.UIElement) -> Point?) -> Bool {
        var current: WinUI.DependencyObject? = element
        while let candidate = current {
            if let ui = candidate as? WinUI.UIElement,
                let region = entries[ObjectIdentifier(ui)]?.region,
                entries[ObjectIdentifier(ui)]?.element === ui,
                let point = position(ui),
                !region.contains([Double(point.x), Double(point.y)])
            {
                return true
            }
            current = try? VisualTreeHelper.getParent(candidate)
        }
        return false
    }

    /// Whether a pointer press belongs to `element`: inside its content shape
    /// and every shape above it, and on the chain of the element XAML's hit
    /// test finds once every shape is up to date for this position. True
    /// without shapes. See the note on this extension.
    ///
    /// 一次指標按壓是否屬於 `element`:位於其 content shape 及其上每個形狀之內，且位於「每個形狀都更新到此
    /// 位置之後，XAML 命中測試所找到的元素」的鏈上。沒有形狀時為 true。見本 extension 的說明。
    static func admits(_ element: WinUI.UIElement, _ args: PointerRoutedEventArgs?) -> Bool {
        guard shapedCount > 0, let args else { return true }
        pointerMoved(args)
        if excludes(element, position: { try? args.getCurrentPoint($0)?.position }) {
            return false
        }
        guard let windowPoint = try? args.getCurrentPoint(nil)?.position,
            let fresh = topElement(at: windowPoint, near: element)
        else { return true }
        return isAncestorOrSelf(element, of: fresh)
    }

    /// ``admits(_:_:)`` for an event that carries only a position -- a right
    /// tap, a context request, a drag over the element.
    /// 只帶位置之事件版本的 ``admits(_:_:)``——右鍵點按、內容選單要求、拖放經過元素。
    static func admits(_ element: WinUI.UIElement, position: (WinUI.UIElement?) -> Point?) -> Bool {
        guard shapedCount > 0 else { return true }
        if excludes(element, position: { position($0) }) {
            return false
        }
        guard let windowPoint = position(nil),
            let fresh = topElement(at: windowPoint, near: element)
        else { return true }
        return isAncestorOrSelf(element, of: fresh)
    }

    /// Whether a pointer over `element` is inside its content shape and every
    /// shape above it, for hover. / 位於 `element` 上的指標是否在其 content shape 及其上每個形狀
    /// 之內，供懸停使用。
    static func contains(_ element: WinUI.UIElement, _ args: PointerRoutedEventArgs?) -> Bool {
        guard shapedCount > 0, let args else { return true }
        return !excludes(element, position: { try? args.getCurrentPoint($0)?.position })
    }

    /// The root grid's press: a press XAML hit-tested with flags from an
    /// earlier position is forwarded to the chain it should have reached.
    /// 根 grid 的按壓：以先前位置之旗標做命中測試的按壓，會被轉交給它本應抵達的那條鏈。
    static func rootPointerPressed(_ args: PointerRoutedEventArgs?) {
        guard shapedCount > 0, misdirected == nil, let args,
            let stale = args.originalSource as? WinUI.UIElement
        else { return }
        pointerMoved(args)
        guard let windowPoint = try? args.getCurrentPoint(nil)?.position,
            let fresh = topElement(at: windowPoint, near: stale),
            !isAncestorOrSelf(fresh, of: stale), !isAncestorOrSelf(stale, of: fresh)
        else { return }
        misdirected = Misdirected(fresh: fresh, stale: stale, pointerId: args.pointer.pointerId)
        forward(.pressed, args)
    }

    static func rootPointerReleased(_ args: PointerRoutedEventArgs?) {
        guard let record = misdirected, let args, args.pointer.pointerId == record.pointerId else {
            return
        }
        forward(.released, args)
        misdirected = nil
    }

    static func forwardMove(_ args: PointerRoutedEventArgs?) {
        guard let record = misdirected, let args, args.pointer.pointerId == record.pointerId else {
            return
        }
        forward(.moved, args)
    }

    private static func forward(_ phase: Phase, _ args: PointerRoutedEventArgs) {
        guard let record = misdirected, let fresh = record.fresh else { return }
        var current: WinUI.DependencyObject? = fresh
        while let candidate = current {
            // From here up, XAML's own routing reaches the element.
            // 從這裡往上，XAML 自己的路由就會抵達該元素。
            if let stale = record.stale, let ui = candidate as? WinUI.UIElement,
                isAncestorOrSelf(ui, of: stale)
            {
                break
            }
            if let ui = candidate as? WinUI.UIElement,
                let entry = forwarded[ObjectIdentifier(ui)], entry.element === ui,
                let point = try? args.getCurrentPoint(ui)?.position
            {
                let local = SIMD2(Double(point.x), Double(point.y))
                for handler in Array(entry.handlers.values) {
                    handler(phase, local)
                }
            }
            current = try? VisualTreeHelper.getParent(candidate)
        }
    }

    /// A long press made of forwarded events: `action` runs once the press is
    /// held for WinUI's long-press time without a release or a move of more
    /// than a few pixels. / 由轉交事件組成的長按：按壓維持 WinUI 的長按時間、期間沒有放開也沒有移動超過
    /// 數個像素時，`action` 執行一次。
    @MainActor
    final class LongPress {
        private var generation = 0
        private var start = SIMD2<Double>(0, 0)
        var fired = false
        /// Between a press this long press took and its release.
        /// 介於本長按接下的按壓與其放開之間。
        private(set) var active = false

        func handle(_ phase: Phase, _ point: SIMD2<Double>, action: @escaping () -> Void) {
            switch phase {
                case .pressed:
                    generation += 1
                    fired = false
                    active = true
                    start = point
                    let generation = generation
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(
                            nanoseconds: UInt64(WinUIBackend.longPressDuration * 1_000_000_000))
                        guard let self, self.generation == generation else { return }
                        self.fired = true
                        action()
                    }
                case .moved:
                    let moved = point - start
                    if (moved * moved).sum() > 8 * 8 { generation += 1 }
                case .released:
                    generation += 1
                    active = false
            }
        }
    }
}
