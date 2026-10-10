/// Where the pointer is over a view, and which modifier keys are held.
///
/// **`modifiers` is part of each report, not a separate key event,** because
/// a key event goes to the focused view and the view under the pointer is
/// usually not focused: "hold Command over the model to read a value" has to
/// work without clicking it first. Backends report a new `.active` when the
/// pointer moves, and AppKitBackend also when a modifier changes while the
/// pointer is still. Elsewhere a modifier pressed without moving is seen at the
/// next move; pair this with ``View/onKeyPress(perform:)`` for a focused view
/// that must react at once.
///
/// Named `PointerHoverPhase` rather than SwiftUI's `HoverPhase`, which
/// `_SwiftCrossUIPortingKit` already declares with a `CGPoint` and no
/// modifiers.
///
/// 指標在一個 view 上的位置，以及按住了哪些修飾鍵。
///
/// **`modifiers` 是每次回報的一部分，而不是另一個按鍵事件**:按鍵事件送往取得焦點的 view,而指標下的
/// view 通常沒有焦點——「在模型上按住 Command 讀數值」必須在不先點它的情況下運作。backend 在指標移動時回報
/// 新的 `.active`,AppKitBackend 另外在指標不動、修飾鍵改變時也回報。其他 backend 不移動而按下的修飾鍵，
/// 要到下一次移動才看得到；需要立即反應、且已有焦點的 view,可以再搭配 ``View/onKeyPress(perform:)``。
///
/// 命名為 `PointerHoverPhase` 而非 SwiftUI 的 `HoverPhase`,因為 `_SwiftCrossUIPortingKit` 已宣告了一個帶
/// `CGPoint`、沒有修飾鍵的 `HoverPhase`。
public enum PointerHoverPhase: Equatable, Sendable {
    /// In the view's own coordinates, in points, origin at the top left.
    /// 以 view 自身座標、點為單位，原點在左上角。
    case active(location: SIMD2<Double>, modifiers: EventModifiers)
    case ended
}

extension BackendFeatures {
    /// Reports where the pointer is over a view, continuously.
    /// 持續回報指標在 view 上的位置。
    @MainActor
    public protocol PointerHover: Core {
        /// Wraps `child` so its hover can be reported. The wrapper must not
        /// take clicks, drags or scrolls from the child.
        /// 包住 `child`,以便回報它的 hover。這個包裝不得搶走子 view 的點擊、拖曳或捲動。
        func createPointerHoverTarget(wrapping child: Widget) -> Widget

        func updatePointerHoverTarget(
            _ target: Widget,
            environment: EnvironmentValues,
            action: @escaping (PointerHoverPhase) -> Void
        )
    }
}
