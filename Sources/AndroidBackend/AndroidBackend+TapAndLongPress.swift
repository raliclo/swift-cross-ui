import AndroidKit
@_spi(Backends) import SwiftCrossUI

// A tap and a long press on one view: Android's own pair of listeners on the
// same View. `ViewOnLongClickListener.onLongClick` returns true, which
// consumes the press, so Android does not deliver the click after a long
// click -- the platform already tells the two apart.
// 同一個 view 上的點按與長按：在同一個 View 上使用 Android 自己的一對 listener。`ViewOnLongClickListener.onLongClick`
// 回傳 true,消耗掉這次按壓，因此長按之後 Android 不會再送出點擊——平台本身就分得開兩者。
extension AndroidBackend: BackendFeatures.TapAndLongPressGestures {
    public func createTapAndLongPressTarget(wrapping child: Widget) -> Widget {
        child
    }

    public func updateTapAndLongPressTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) {
        updateTapGestureTarget(target, gesture: .primary, environment: environment, action: onTap)
        updateTapGestureTarget(
            target,
            gesture: .longPress,
            environment: environment,
            action: onLongPress
        )
    }
}
