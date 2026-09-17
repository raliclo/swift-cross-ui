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
        // **ASSUMPTION 1 ABOVE WAS WRONG, AND CHECKING IT WAS THE RIGHT CALL.**
        // AndroidKit's `PopupWindow` binds 45 methods and
        // `setBackgroundDrawable` is not among them, so the line that used to
        // stand here did not compile on the one machine that can build this
        // file. Verified 2026-09-10 by listing the binding's own methods rather
        // than by grepping this tree, which had no precedent either way.
        //
        // The colour goes on the CONTENT VIEW instead, which is a `View` and
        // does bind `setBackgroundColor(Int32)`. That also sidesteps the hazard
        // the note below describes: the popup's own background is never
        // cleared, so light dismissal keeps working whatever the app asks for.
        //
        // `nil` paints transparent rather than restoring a platform default,
        // and that IS a difference from the other four backends: there is no
        // "unset" for a view's background colour, only a colour. The window
        // beneath still supplies the popup's own background, so the panel does
        // not become a hole.
        //
        // **上述第 1 項假設是錯的，而「先去查證」是對的判斷。** AndroidKit 的 `PopupWindow` 綁定了
        // 45 個方法，其中沒有 `setBackgroundDrawable`；因此原本站在這裡的那一行，在唯一建得了本檔的
        // 那台機器上編不過。2026-09-10 以「列出該 binding 自身的方法」查證，而非在本樹中 grep
        // ——本樹在這件事上兩個方向都沒有先例。
        //
        // 改為把顏色設在**內容 view** 上：那是一個 `View`，而它確實綁定了 `setBackgroundColor(Int32)`。
        // 這同時繞開了下方註解所描述的危險：popup 自身的背景從未被清掉，因此無論 app 要求什麼，
        // light dismiss 都繼續有效。
        //
        // `nil` 會畫成透明，而不是還原平台預設值；這**確實**是與另外四個 backend 的差異：一個 view 的
        // 背景色沒有「未設定」這種狀態，只有顏色。其下的視窗仍然提供 popup 自身的背景，因此這塊面板
        // 不會變成一個洞。
        popover.as(PopupWindowContent.self)?.getContentView()?
            .setBackgroundColor(backgroundColor?.asColorInt() ?? 0)

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
        let popupWidth = popover.getWidth()
        let popupHeight = popover.getHeight()

        switch Self.edge(forPreference: popover.getPreferredEdge()) {
            case .top:
                popover.showAsDropDown(anchor, 0, -(anchorHeight + popupHeight))
            case .bottom:
                popover.showAsDropDown(anchor, 0, 0)
            case .leading:
                popover.showAsDropDown(anchor, -popupWidth, -anchorHeight)
            case .trailing:
                popover.showAsDropDown(anchor, anchorWidth, -anchorHeight)
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
