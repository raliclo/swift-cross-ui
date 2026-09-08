import AndroidKit
@_spi(Backends) import SwiftCrossUI
import SwiftJava

extension AndroidKit.PopupWindow {
    @JavaMethod
    func setContentView(_ contentView: AndroidKit.View?)

    @JavaMethod
    func showAsDropDown(_ anchor: AndroidKit.View?)

    @JavaMethod
    func isShowing() -> Bool
}

/// `PopupWindow`, anchored to the widget the modifier is attached to.
///
/// Android has no stock popover class the way the other four platforms do --
/// `PopupWindow` is the primitive, and everything anchored on Android is built
/// on it. What it does not give away for free is the two behaviours that make
/// a popover a popover rather than a floating panel: it must take touches, and
/// touching outside it must close it. Both are set in ``createPopover(content:)``
/// and neither is the default.
///
/// `PopupWindow`,錨定在該 modifier 所附著的 widget 上。
///
/// Android 並不像其餘四個平台那樣有一個現成的 popover 類別——`PopupWindow` 就是那個原語,而 Android
/// 上所有帶錨點的東西都建構於它之上。它不會免費給的,是使 popover 成為 popover(而非一塊浮動面板)的
/// 那兩項行為:它必須接收觸控,而觸碰它以外之處必須把它關掉。兩者都在 ``createPopover(content:)``
/// 中設定,而且都不是預設值。
extension AndroidBackend {
    public typealias Popover = AndroidKit.PopupWindow

    public func createPopover(content: Widget) -> AndroidKit.PopupWindow {
        let popup = AndroidKit.PopupWindow(environment: Self.env)
        popup.setContentView(content)

        // Focusable so it receives touches at all, and outside-touchable so a
        // touch beyond its bounds dismisses it. A PopupWindow with neither is a
        // panel that sits there and swallows nothing, which is not a popover.
        // 設為 focusable 才會接收到觸控,設為 outside-touchable 才會在其範圍之外被觸碰時關閉。
        // 兩者皆無的 PopupWindow 只是一塊「杵在那裡、什麼都不吞」的面板,那不是 popover。
        popup.setFocusable(true)
        popup.setOutsideTouchable(true)

        return popup
    }

    public func updatePopover(
        _ popover: AndroidKit.PopupWindow,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        onDismiss: @escaping () -> Void
    ) {
        let density = environment.androidActivity.getResources()
            .getDisplayMetrics().density
        popover.setWidth(Int32(Float(size.x) * density))
        popover.setHeight(Int32(Float(size.y) * density))

        let action = SwiftAction(environment: Self.env) {
            onDismiss()
        }
        popover.setOnDismissListener(
            CustomPopupDismissListener(action, environment: Self.env)
                .as(AndroidKit.PopupWindow.OnDismissListener.self)
        )
    }

    public func presentPopover(
        _ popover: AndroidKit.PopupWindow,
        relativeTo anchor: Widget,
        window: Window
    ) {
        // `showAsDropDown` is the anchored form. `showAtLocation` exists and
        // takes window coordinates, which would put the popup wherever the
        // caller computed rather than beside the view -- and computing that
        // position is exactly the work the platform is being asked to do.
        // `showAsDropDown` 是帶錨點的那一種。`showAtLocation` 也存在,但它接收的是視窗座標,那會把
        // popup 放到呼叫端自行算出來的位置、而不是放在該 view 旁邊——而算出那個位置,恰恰就是此處
        // 要交給平台去做的工作。
        popover.showAsDropDown(anchor)
    }

    public func dismissPopover(_ popover: AndroidKit.PopupWindow, window: Window) {
        popover.dismiss()
    }

    public func size(ofPopover popover: AndroidKit.PopupWindow) -> SIMD2<Int> {
        SIMD2(Int(popover.getWidth()), Int(popover.getHeight()))
    }
}
