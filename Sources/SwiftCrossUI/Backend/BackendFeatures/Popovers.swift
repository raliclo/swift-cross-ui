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

        /// `backgroundColor` is what ``SwiftCrossUI/View/presentationBackground(_:)``
        /// resolved to, or `nil` when the app asked for nothing.
        ///
        /// **`nil` means "leave it to the platform", NOT "make it transparent".**
        /// The distinction is the whole design, and it was chosen against a
        /// measurement rather than from taste. On GTK 4 / Windows a popover is
        /// its own opaque top-level surface: clearing the theme's fill was tried
        /// on 2026-09-09 and produced OPAQUE BLACK, and `rgba(255,0,0,0.5)` on
        /// the same nodes produced OPAQUE RED with the window's text behind it
        /// invisible. So that surface has no per-pixel alpha, and a
        /// "transparent by default" contract would have shipped a black
        /// rectangle on that backend while the API said otherwise.
        ///
        /// The second experiment is the one that settled it. A failed
        /// transparency looks exactly like a black background, and a black
        /// background looks exactly like a dark theme -- three states wearing
        /// each other's clothes. A half-opaque RED cannot be mistaken for any of
        /// them.
        ///
        /// A backend that cannot honour a colour must say so where a reader will
        /// find it, not fall back silently.
        ///
        /// `backgroundColor` 是 ``SwiftCrossUI/View/presentationBackground(_:)`` 解析後的結果;
        /// 若 app 未指定則為 `nil`。
        ///
        /// **`nil` 的意思是「交給平台」,不是「弄成透明」。** 這個區別就是整個設計,而它是依據量測、
        /// 而非依據品味所決定的。在 GTK 4 / Windows 上,popover 是它自己的**不透明** top-level
        /// surface:2026-09-09 試過清掉主題的填色,得到的是**不透明的黑**;在相同節點上設
        /// `rgba(255,0,0,0.5)`,得到的是**不透明的紅**,而其背後視窗的文字完全看不見。可見該 surface
        /// 沒有 per-pixel alpha,因此「預設透明」這個約定會在那個 backend 上交付一個黑色矩形,
        /// 而 API 卻宣稱是別的東西。
        ///
        /// 真正定案的是第二個實驗。**一次失敗的透明,看起來與黑色背景一模一樣;而黑色背景又與深色主題
        /// 一模一樣**——三種狀態互相穿著對方的衣服。一個半透明的**紅**,則無法被誤認為其中任何一個。
        ///
        /// 無法遵守某個顏色的 backend,必須在讀者找得到的地方說明,而不是靜默退回。
        func updatePopover(
            _ popover: Popover,
            environment: EnvironmentValues,
            size: SIMD2<Int>,
            backgroundColor: Color.Resolved?,
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

    /// A popover that can be asked which side of its anchor to appear on (#109).
    ///
    /// **A PREFERENCE, not a placement, and the distinction is the feature.**
    /// Every one of these platforms moves a popover that would not fit: GTK
    /// flips a `GtkPopover` to the opposite side when the anchor is near a
    /// screen edge, and WinUI's `Flyout` does the same. Promising an edge would
    /// mean fighting that, and winning would mean drawing a popover half off
    /// the screen. So this says which side to prefer and the platform keeps its
    /// own rules -- the same contract SwiftUI's `arrowEdge` has.
    ///
    /// **This is why the anchor stays a widget** rather than becoming a point
    /// plus an edge: ``Popovers/presentPopover(_:relativeTo:window:)`` already
    /// explains that each platform positions from a rectangle it is given and
    /// each has its own rules about edges. An edge preference rides alongside
    /// that; it does not replace it.
    ///
    /// Separate from ``Popovers`` and conformance-checked, like
    /// ``Containers/LazyListRows`` and ``TableSelection``: a backend that does
    /// not implement it draws exactly the popover it draws today, on whichever
    /// side the platform picks. Adding a parameter to `presentPopover` instead
    /// would have broken all five conformances at once, and four of those five
    /// cannot be compiled from here -- the shape mistakes.md entry 10 is about.
    ///
    /// 一種「可以被詢問要出現在錨點哪一側」的 popover(#109)。
    ///
    /// **這是一個偏好,不是一個位置,而這個區別正是這項功能的本質。** 這些平台每一個都會移動
    /// 「放不下的」popover:錨點靠近螢幕邊緣時,GTK 會把 `GtkPopover` 翻到對側,WinUI 的 `Flyout`
    /// 也一樣。**承諾某一側**等於要去對抗那個行為,而「贏了」的結果是畫出一個有一半在螢幕外的 popover。
    /// 因此這裡說的是「偏好哪一側」,平台保有自己的規則——與 SwiftUI 的 `arrowEdge` 是同一個約定。
    ///
    /// **這也是錨點維持為 widget 的原因**,而不是改成「一個點加一個邊」:
    /// ``Popovers/presentPopover(_:relativeTo:window:)`` 已經說明各平台是**由所給定的矩形**來定位、
    /// 且各有自己的邊緣規則。邊的偏好是**伴隨**它,而不是取代它。
    ///
    /// 與 ``Popovers`` 分開並採 conformance 檢查,做法同 ``Containers/LazyListRows`` 與
    /// ``TableSelection``:未實作它的 backend,畫出來的 popover 與今天完全相同、由平台自行決定側邊。
    /// 若改成在 `presentPopover` 上加參數,則會**一次弄壞五個 conformance**,而其中四個在此處根本
    /// 編不動——那正是 mistakes.md 第 10 條所講的形狀。
    @MainActor
    public protocol PopoverArrowEdges<Popover>: Popovers {
        /// Asks for `popover` to appear on `edge` of its anchor, if it fits.
        ///
        /// nil restores the platform's own choice, which is what a popover
        /// given no preference has always had.
        ///
        /// Called before ``Popovers/presentPopover(_:relativeTo:window:)``, so
        /// an implementation that stores a placement on the native object has
        /// it set by the time the popover is shown.
        ///
        /// 要求 `popover` 出現在其錨點的 `edge` 側——**如果放得下的話**。
        ///
        /// nil 會恢復平台自己的選擇,而那正是「沒有給偏好的 popover」一直以來的行為。
        ///
        /// 在 ``Popovers/presentPopover(_:relativeTo:window:)`` **之前**呼叫,因此把 placement
        /// 存在原生物件上的實作,在該 popover 被顯示時該值已經設好。
        func setPreferredArrowEdge(ofPopover popover: Popover, to edge: Edge?)
    }
}
