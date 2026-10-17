import Foundation
@_spi(Backends) import SwiftCrossUI
import UWP
import WinUI

// A tap and a long press on one view. The long press is timed the way
// TapGestures' `.longPress` is (WinUI's `Holding` never comes from a mouse):
// `pointerPressed` starts a generation and schedules the long press; a release
// or an exit moves the generation on. The tap is reported on release, and only
// when the long press did not fire for that press.
// 同一個 view 上的點按與長按。長按的計時與 TapGestures 的 `.longPress` 相同(WinUI 的 `Holding` 從不來自滑鼠):
// `pointerPressed` 推進 generation 並排程長按;放開或移出再推進 generation。點按在放開時回報，而且只在這次按壓的
// 長按沒有觸發時。
extension WinUIBackend: BackendFeatures.TapAndLongPressGestures {
    public func createTapAndLongPressTarget(wrapping child: Widget) -> Widget {
        let target = TapAndLongPressTarget()
        insert(child, into: target, at: 0)
        target.child = child

        // Transparent, so the whole area is hit tested without changing how
        // the view looks. / 透明，讓整個區域都被命中測試，又不改變外觀。
        let brush = SolidColorBrush()
        brush.color = UWP.Color(a: 0, r: 0, g: 0, b: 0)
        target.background = brush

        target.pointerPressed.addHandler { [weak target] _, _ in
            guard let target else { return }
            target.pressGeneration += 1
            target.isPressed = true
            target.longPressFired = false
            let generation = target.pressGeneration
            DispatchQueue.main.asyncAfter(
                deadline: .now() + WinUIBackend.longPressDuration
            ) { [weak target] in
                guard let target, target.pressGeneration == generation, target.isPressed else {
                    return
                }
                target.longPressFired = true
                target.longPressHandler?()
            }
        }
        target.pointerReleased.addHandler { [weak target] _, _ in
            guard let target else { return }
            let wasPressed = target.isPressed
            target.pressGeneration += 1
            target.isPressed = false
            if wasPressed && !target.longPressFired {
                target.tapHandler?()
            }
        }
        target.pointerExited.addHandler { [weak target] _, _ in
            guard let target else { return }
            target.pressGeneration += 1
            target.isPressed = false
        }
        return target
    }

    public func updateTapAndLongPressTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) {
        let target = target as! TapAndLongPressTarget
        target.tapHandler = environment.isEnabled ? onTap : nil
        target.longPressHandler = environment.isEnabled ? onLongPress : nil
    }
}

final class TapAndLongPressTarget: WinUI.Canvas {
    var tapHandler: (() -> Void)?
    var longPressHandler: (() -> Void)?
    var child: WinUI.FrameworkElement?
    /// See `TapGestureTarget.pressGeneration`. / 見 `TapGestureTarget.pressGeneration`。
    var pressGeneration = 0
    var isPressed = false
    var longPressFired = false
}
