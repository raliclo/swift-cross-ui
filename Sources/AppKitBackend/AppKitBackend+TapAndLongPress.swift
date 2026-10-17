import AppKit
@_spi(Backends) import SwiftCrossUI

// A tap and a long press on one view: the same container as TapGestures, with
// both handlers set on its NSCustomTapGestureTarget. The click recogniser
// requires the press recogniser to fail (its delegate method in
// AppKitBackend+Gestures.swift), so a held press is not also a click.
// 同一個 view 上的點按與長按：與 TapGestures 相同的容器，在它的 NSCustomTapGestureTarget 上同時設定兩個 handler。
// 點擊辨識器要求長按辨識器先失敗(委派方法在 AppKitBackend+Gestures.swift),因此按住不放不會同時是一次點擊。
extension AppKitBackend: BackendFeatures.TapAndLongPressGestures {
    public func createTapAndLongPressTarget(wrapping child: Widget) -> Widget {
        createTapGestureTarget(wrapping: child, gesture: .primary)
    }

    public func updateTapAndLongPressTarget(
        _ container: Widget,
        environment: EnvironmentValues,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) {
        let target = container.subviews[1] as! NSCustomTapGestureTarget
        target.rightClickHandler = nil
        if environment.isEnabled {
            target.leftClickHandler = onTap
            target.longPressHandler = onLongPress
        } else {
            target.leftClickHandler = nil
            target.longPressHandler = nil
        }
    }
}
