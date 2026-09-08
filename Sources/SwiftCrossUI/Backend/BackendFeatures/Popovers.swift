extension BackendFeatures {
    /// A transient presentation anchored to the view that opened it.
    ///
    /// Shaped like ``Sheets`` because it is the same kind of thing -- a
    /// presentation with its own widget tree, presented and dismissed by the
    /// modifier -- and differs in the one way that matters: it is anchored, so
    /// ``presentPopover(_:relativeTo:window:)`` takes the widget it points at.
    ///
    /// **Every one of the five shipped backends has a native popover, which is
    /// why this is a protocol rather than a sheet with a different name.**
    /// `NSPopover`, `UIPopoverPresentationController`, `GtkPopover`, WinUI's
    /// `Flyout` and Android's `PopupWindow`. Presenting a sheet instead would
    /// work everywhere and look wrong everywhere: a popover points at
    /// something, and a sheet that appears in the middle of the window when the
    /// user pressed a small button in a corner has lost the only information a
    /// popover carries.
    ///
    /// UIKit is the exception worth naming: on iPhone, UIKit itself adapts a
    /// popover into a sheet, because a popover on a phone-sized screen would
    /// cover what it points at. That adaptation is the platform's own and is
    /// the right answer there, which is different from this toolkit choosing a
    /// sheet on a platform that would have drawn a popover.
    ///
    /// 一種錨定在「開啟它的那個 view」上的短暫呈現。
    ///
    /// 形狀比照 ``Sheets``，因為它們是同一類東西——一種擁有自身 widget 樹、由 modifier 呈現與關閉的
    /// 呈現方式——而其差異正在於關鍵的那一點:它是**有錨點的**，因此
    /// ``presentPopover(_:relativeTo:window:)`` 會接收它所指向的那個 widget。
    ///
    /// **五個出貨 backend 每一個都有原生的 popover，這正是此處採用協定、而非「換個名字的 sheet」的
    /// 理由。** `NSPopover`、`UIPopoverPresentationController`、`GtkPopover`、WinUI 的 `Flyout`，
    /// 以及 Android 的 `PopupWindow`。改用 sheet 呈現會在每個地方都能運作、也會在每個地方都不對:
    /// popover 是**指向**某個東西的，而當使用者按下角落一顆小按鈕、卻有個東西出現在視窗正中央時，
    /// popover 所攜帶的唯一資訊就已經丟失了。
    ///
    /// UIKit 是值得指名的例外:在 iPhone 上，UIKit 自己會把 popover 調適為 sheet，因為在手機尺寸的
    /// 螢幕上，popover 會蓋住它所指向的東西。那項調適是平台自身的，而且在那裡是正確答案——這與
    /// 「本工具組在一個原本會畫出 popover 的平台上選擇了 sheet」是兩回事。
    @MainActor
    public protocol Popovers<Popover>: Core {
        associatedtype Popover

        func createPopover(content: Widget) -> Popover

        func updatePopover(
            _ popover: Popover,
            environment: EnvironmentValues,
            size: SIMD2<Int>,
            onDismiss: @escaping () -> Void
        )

        /// Shows `popover` pointing at `anchor`.
        ///
        /// `anchor` is a widget in `window`, not a point: every one of the five
        /// platforms positions a popover from a rectangle it is given, and each
        /// has its own rules about which edge it appears on when the anchor is
        /// near a screen edge. Passing the widget lets each keep its rules.
        ///
        /// 顯示 `popover`，並使其指向 `anchor`。
        ///
        /// `anchor` 是 `window` 中的一個 widget，而不是一個點:五個平台每一個都是由「所給定的一個
        /// 矩形」來定位 popover 的，而當錨點靠近螢幕邊緣時，各平台對於它該出現在哪一側各有規則。
        /// 傳入 widget 可以讓每個平台保有自己的規則。
        func presentPopover(_ popover: Popover, relativeTo anchor: Widget, window: Window)

        func dismissPopover(_ popover: Popover, window: Window)

        func size(ofPopover popover: Popover) -> SIMD2<Int>
    }
}
