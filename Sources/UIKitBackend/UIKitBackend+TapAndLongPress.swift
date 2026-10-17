@_spi(Backends) import SwiftCrossUI
import UIKit

// A tap and a long press on one view: both recognisers on one TappableWidget,
// the tap waiting for the long press to fail (TappableWidget's delegate
// method), so a held press is not also a tap.
// 同一個 view 上的點按與長按：兩個辨識器在同一個 TappableWidget 上，點按等長按失敗(TappableWidget 的委派方法),
// 所以按住不放不會同時是點按。
extension UIKitBackend: BackendFeatures.TapAndLongPressGestures {
    public func createTapAndLongPressTarget(wrapping child: Widget) -> Widget {
        TappableWidget(child: child)
    }

    public func updateTapAndLongPressTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) {
        let wrapper = target as! TappableWidget
        wrapper.onTap = environment.isEnabled ? onTap : {}
        wrapper.onLongPress = environment.isEnabled ? onLongPress : {}
    }
}
