import AndroidKit
@_spi(Backends) import SwiftCrossUI
import SwiftJava

extension AndroidKit.PopupWindow {
    @JavaMethod
    func setContentView(_ contentView: AndroidKit.View?)

    @JavaMethod
    func showAsDropDown(_ anchor: AndroidKit.View?)

    /// The offset form, which is the only way to ask for a side on Android.
    ///
    /// `PopupWindow` has no placement property: `showAsDropDown(anchor)` means
    /// below, and every other side is that same call with an offset computed
    /// from the anchor's and the popup's own measurements. AndroidKit binds
    /// neither overload, so both are bound here beside the only code that calls
    /// them.
    ///
    /// 帶位移的那一種——在 Android 上,那是唯一能要求某一側的方式。
    ///
    /// `PopupWindow` 沒有表示位置的屬性:`showAsDropDown(anchor)` 的意思就是「下方」,而其餘每一側
    /// 都是同一個呼叫,加上一個由錨點與 popup 自身量測算出的位移。AndroidKit 兩個多載都沒有綁,
    /// 因此兩個都綁在此處——就放在唯一會呼叫它們的程式旁邊。
    @JavaMethod
    func showAsDropDown(_ anchor: AndroidKit.View?, _ xoff: Int32, _ yoff: Int32)

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
    public typealias Popover = CustomPopupWindow

    public func createPopover(content: Widget) -> CustomPopupWindow {
        // A subclass, for one field: which side was asked for. See
        // `CustomPopupWindow.kt` -- `PopupWindow` has no placement property, so
        // the preference has to be remembered from when it is set until the
        // popup is shown.
        // 用一個子類別,只為了一個欄位:被要求的是哪一側。見 `CustomPopupWindow.kt`
        // ——`PopupWindow` 沒有表示位置的屬性,因此那個偏好必須從「被設定時」一路記到「popup 被顯示時」。
        let popup = CustomPopupWindow(Self.activity, environment: Self.env)
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
        _ popover: CustomPopupWindow,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        backgroundColor: SwiftCrossUI.Color.Resolved?,
        onDismiss: @escaping () -> Void
    ) {
        // The colour goes on the CONTENT VIEW, which is a `View` and binds
        // `setBackgroundColor(Int32)`. A `PopupWindow` is not a View, and
        // AndroidKit's `PopupWindow` binding has no `setBackgroundDrawable`
        // (checked by listing the binding's own methods, 2026-09-10).
        //
        // The popup's own background is never cleared, and that is NOT merely
        // cosmetic on Android: a PopupWindow with a null background
        // historically does not dismiss on an outside touch, so clearing it
        // would silently break light dismissal rather than only change a colour.
        //
        // `nil` paints transparent rather than restoring a platform default,
        // and that IS a difference from the other four backends: there is no
        // "unset" for a view's background colour, only a colour. The window
        // beneath still supplies the popup's own background, so the panel does
        // not become a hole.
        //
        // 顏色設在**內容 view** 上:那是一個 `View`,而它綁定了 `setBackgroundColor(Int32)`。
        // `PopupWindow` 不是 View,而 AndroidKit 的 `PopupWindow` 綁定中沒有 `setBackgroundDrawable`
        // (2026-09-10 以列出該 binding 自身的方法查證)。
        //
        // popup 自身的背景從不被清掉，而**在 Android 上那不只是外觀問題**:一個背景為 null 的
        // PopupWindow 在歷史上**不會**因外部觸控而關閉，因此把它清掉會靜默地弄壞 light dismiss,
        // 而不只是改變一個顏色。
        //
        // `nil` 會畫成透明，而不是還原平台預設值；這**確實**是與另外四個 backend 的差異：一個 view 的
        // 背景色沒有「未設定」這種狀態，只有顏色。其下的視窗仍然提供 popup 自身的背景，因此這塊面板
        // 不會變成一個洞。
        popover.as(PopupWindowContent.self)?.getContentView()?
            .setBackgroundColor(backgroundColor?.asColorInt() ?? 0)

        // The same colour again, on the popup itself, because the tail is drawn
        // by the popup's background and has to be the panel's colour rather
        // than a window colour behind it. `nil` leaves the popup to resolve the
        // theme's own background, which is what the panel shows in that case.
        // 同一個顏色再設一次,設在 popup 自己身上,因為尾巴是由 popup 的背景繪製的,它必須是**面板的**
        // 顏色,而不是它背後那個視窗的顏色。`nil` 時交由 popup 去解析主題自己的背景色——那也正是該情況下
        // 面板所顯示的顏色。
        popover.setPanelColor(backgroundColor?.asColorInt() ?? 0, backgroundColor != nil)

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
        _ popover: CustomPopupWindow,
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
        //
        // **The offsets are measured from the anchor and the popup, not
        // guessed.** `showAsDropDown(anchor)` puts the popup's top-left at the
        // anchor's bottom-left, so `top` has to lift it by the anchor's height
        // AND its own, and the two sideways placements have to lift it by the
        // anchor's height alone to sit beside the anchor rather than under it.
        // The popup's own width and height are the pixel values
        // ``updatePopover(_:environment:size:backgroundColor:onDismiss:)`` set a
        // moment ago, so they are known here rather than pending a measure
        // pass.
        //
        // **Android still moves a popup that does not fit**, which is what the
        // protocol asks for: `showAsDropDown` shifts the popup on screen and
        // will place it above the anchor itself when there is no room below.
        //
        // **那些位移是由錨點與 popup 量出來的,不是猜的。** `showAsDropDown(anchor)` 會把 popup 的
        // 左上角放在錨點的左下角,因此 `top` 必須把它抬起「錨點的高度**加上**它自己的高度」,
        // 而兩個側向的位置則只需抬起錨點的高度,好讓它落在錨點**旁邊**而不是下方。popup 自己的寬高就是
        // ``updatePopover(_:environment:size:backgroundColor:onDismiss:)`` 片刻前設定的像素值,
        // 因此在此處是已知的,不必等待一次 measure。
        //
        // **放不下時 Android 仍會移動它**,而那正是協定所要求的:`showAsDropDown` 會把 popup 移進
        // 畫面內,而下方沒有空間時它會自行把 popup 放到錨點上方。
        let anchorWidth = anchor.getWidth()
        let anchorHeight = anchor.getHeight()

        // **The side is resolved against the room around the anchor, not taken
        // as given, and the tail is drawn before anything is measured.**
        //
        // Both of those are alignments with the other backends rather than
        // Android's own behaviour. `showAsDropDown` SHIFTS a popup that does
        // not fit until it clears the screen edge, which can leave the panel
        // covering the control it was opened from; UIKitBackend measures the
        // room and takes the opposite side instead, and `resolveEdge` is that
        // same measurement. And Android draws no arrow on a `PopupWindow`
        // at all, where the other four point at the anchor -- so
        // `applyArrow` draws one and grows the popup to hold it, which is why
        // the sizes are read AFTER it rather than before.
        //
        // **那一側是對著錨點四周的空間解析出來的,不是照單全收;而尾巴在任何量測之前就已畫好。**
        //
        // 這兩件都是向其他 backend 對齊、而非 Android 自己的行為。
        // `showAsDropDown` 會把放不下的 popup **推**到離開螢幕邊緣為止,那可能讓面板蓋住當初開啟它的
        // 那個控制項;UIKitBackend 則是「量出空間、改取相反的一側」,而 `resolveEdge` 就是同一個量測。
        // 至於 Android,它根本不會在 `PopupWindow` 上畫任何箭頭,而另外四個都會指向錨點——因此
        // `applyArrow` 會畫一條,並把 popup 放大以容納它;這正是尺寸要在它**之後**才讀取的原因。
        // 8dp of tail, in pixels. Read here rather than passed in: this method
        // is handed a widget and a window and no environment, and the one
        // conversion between points and pixels in this backend happens at the
        // last moment, as it does in the synthesiser.
        // 8dp 的尾巴,換算成像素。在此處讀取而非由外傳入:本方法只拿到一個 widget 與一個 window、
        // 沒有 environment;而本 backend 中「點與像素之間的唯一換算」發生在最後一刻,與 synthesiser 相同。
        let density = Self.activity?.getResources()?.getDisplayMetrics()?.density ?? 1
        let arrowPixels = Int32((8.0 * Double(density)).rounded())
        let resolved = popover.resolveEdge(anchor, popover.getPreferredEdge(), arrowPixels)
        popover.applyArrow(resolved, arrowPixels, anchorWidth, anchorHeight)

        let popupHeight = popover.getHeight()

        switch Self.edge(forPreference: resolved) {
            case .top:
                popover.showAsDropDown(anchor, 0, -(anchorHeight + popupHeight))
            case .bottom:
                popover.showAsDropDown(anchor, 0, 0)
            case .leading, .trailing:
                // Placed and clamped in Kotlin, with the arrow following --
                // see CustomPopupWindow.showBeside.
                // 在 Kotlin 中定位並夾住，箭頭跟著走——見 CustomPopupWindow.showBeside。
                popover.showBeside(anchor, resolved, arrowPixels)
            case nil:
                popover.showAsDropDown(anchor)
        }
    }

    /// The stored number, as an ``SwiftCrossUI/Edge``. See `CustomPopupWindow.kt`.
    /// 存下的那個數字,轉回 ``SwiftCrossUI/Edge``。見 `CustomPopupWindow.kt`。
    private static func edge(forPreference value: Int32) -> SwiftCrossUI.Edge? {
        switch value {
            case 1: return .top
            case 2: return .bottom
            case 3: return .leading
            case 4: return .trailing
            default: return nil
        }
    }

    fileprivate static func preference(for edge: SwiftCrossUI.Edge?) -> Int32 {
        switch edge {
            case .top: return 1
            case .bottom: return 2
            case .leading: return 3
            case .trailing: return 4
            case nil: return 0
        }
    }

    public func dismissPopover(_ popover: CustomPopupWindow, window: Window) {
        popover.dismiss()
    }

    public func size(ofPopover popover: CustomPopupWindow) -> SIMD2<Int> {
        SIMD2(Int(popover.getWidth()), Int(popover.getHeight()))
    }
}

extension AndroidBackend: BackendFeatures.PopoverArrowEdges {
    /// Stores the preference on the popup; ``presentPopover(_:relativeTo:window:)``
    /// turns it into the offsets `showAsDropDown` takes.
    ///
    /// **Android is the one backend of the five where this is arithmetic rather
    /// than a property.** GTK sets `GtkPopover.position`, WinUI sets
    /// `Flyout.placement`, AppKit and UIKit each pass an edge to the call that
    /// presents the popover. `PopupWindow` has none of those: it knows how to
    /// drop below an anchor, and every other side is that call with an offset.
    ///
    /// 把這個偏好存在 popup 上;由 ``presentPopover(_:relativeTo:window:)`` 轉換成 `showAsDropDown`
    /// 所需的位移。
    ///
    /// **在五個 backend 之中,Android 是唯一「這件事是算術而不是一個屬性」的那一個。** GTK 設定
    /// `GtkPopover.position`、WinUI 設定 `Flyout.placement`、AppKit 與 UIKit 各自把一個邊傳給呈現
    /// popover 的那個呼叫。`PopupWindow` 三者皆無:它只會「掉在錨點下方」,而其餘每一側都是同一個呼叫
    /// 加上一個位移。
    public func setPreferredArrowEdge(ofPopover popover: CustomPopupWindow, to edge: Edge?) {
        popover.setPreferredEdge(Self.preference(for: edge))
    }
}
