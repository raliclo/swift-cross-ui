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
extension AndroidBackend: BackendFeatures.Popovers {
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
        backgroundColor: Color.Resolved?,
        onDismiss: @escaping () -> Void
    ) {
        // WRITTEN ON WINDOWS 2026-09-09, NOT RUN, AND NOT EVEN TYPE-CHECKED.
        // ANDROID_HOME is unset on that machine and there is no SDK, so
        // `compile.zsh -android` cannot run there -- this file is never handed
        // to a compiler on the Windows side at all.
        //
        // TWO SPECIFIC ASSUMPTIONS TO CHECK FIRST, named rather than left for
        // the compiler to find, because the same shape broke the Mac build
        // earlier the same day (`2d4010d4` put a `try` inside a non-throwing
        // function in AppKitSynthesiser, invisible on Windows, fixed in
        // `76b9d8e7`):
        //
        //   1. that AndroidKit exposes `setBackgroundDrawable` on
        //      `PopupWindow`. A grep for it across `Sources/AndroidBackend/`
        //      returns ONLY this file -- there is no precedent anywhere in the
        //      tree, so nothing here proves the binding exists.
        //   2. that `ColorDrawable.init` accepts the `Int32` that
        //      `asColorInt()` returns (`AndroidBackend+Colors.swift:5`). The
        //      one existing call passes an untyped literal
        //      (`AndroidBackend+List.swift:76`), which would infer whatever the
        //      initialiser wants and therefore proves nothing about `Int32`.
        //
        // **2026-09-09 於 Windows 上寫成,未曾執行,甚至未曾通過型別檢查。** 那台機器上
        // `ANDROID_HOME` 未設定、亦無 SDK,因此 `compile.zsh -android` 在該處無法執行——本檔在
        // Windows 側**根本不會被交給任何編譯器**。
        //
        // **有兩項具體假設必須先查**,此處明白指名而不是留給編譯器去找,因為同一天稍早正是這個形狀
        // 弄壞了 Mac 的建置(`2d4010d4` 在 AppKitSynthesiser 中把 `try` 放進一個非 throwing 的函式,
        // 在 Windows 上完全看不見,已由 `76b9d8e7` 修復):
        //
        //   1. AndroidKit 是否在 `PopupWindow` 上暴露了 `setBackgroundDrawable`。在
        //      `Sources/AndroidBackend/` 中 grep 它**只會命中本檔**——樹中沒有任何先例,
        //      因此此處沒有任何東西能證明該 binding 存在。
        //   2. `ColorDrawable.init` 是否接受 `asColorInt()` 所回傳的 `Int32`
        //      (`AndroidBackend+Colors.swift:5`)。唯一既有的呼叫傳的是無型別字面量
        //      (`AndroidBackend+List.swift:76`),它會推導成 initialiser 想要的任何型別,
        //      因此對 `Int32` 一事什麼都證明不了。
        //
        // `setBackgroundDrawable` rather than `setBackgroundColor`: the latter
        // is a `View` method and a `PopupWindow` is not a View. A `ColorDrawable`
        // is the shape this backend already uses for a flat fill --
        // `AndroidBackend+List.swift:76` sets its selector the same way.
        //
        // Passing nil restores the platform's own background, which is what
        // "leave it to the platform" means in this protocol. That is NOT merely
        // cosmetic on Android and is worth knowing before anyone "simplifies" it
        // away: a PopupWindow with a null background historically does not
        // dismiss on an outside touch, so clearing it to nothing would silently
        // break light dismissal rather than only change a colour.
        //
        // **本段於 2026-09-09 在 Windows 上寫成,未曾執行。** Mac 那側有模擬器,由他們驗證,與 #117
        // 相同的交接方式。
        //
        // 用 `setBackgroundDrawable` 而非 `setBackgroundColor`:後者是 `View` 的方法,而
        // `PopupWindow` 並不是 View。`ColorDrawable` 是本 backend 既有的「平塗填色」形狀——
        // `AndroidBackend+List.swift:76` 設定其 selector 時用的就是它。
        //
        // 傳入 nil 會還原平台自己的背景,那正是本 protocol 中「交給平台」的意思。**在 Android 上那
        // 不只是外觀問題**,在有人想「順手簡化掉它」之前值得知道:一個背景為 null 的 PopupWindow
        // 在歷史上**不會**因外部觸控而關閉,因此把它清成「沒有」會靜默地弄壞 light dismiss,
        // 而不只是改變一個顏色。
        popover.setBackgroundDrawable(
            AndroidKit.ColorDrawable(backgroundColor?.asColorInt() ?? 0)
        )

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
