/// The pointer shape shown over a view.
///
/// **A small set, because the intersection of five platforms is small and a
/// name that means something different on each is worse than an absent one.**
/// Every case here exists on AppKit, GTK, WinUI and Android. The omissions are
/// deliberate and each has a reason:
///
/// - **No `wait`.** GTK, WinUI and Android all have one; AppKit does not expose
///   a public busy cursor (`NSCursor.busyButClickable` is private API and
///   `arrowCursor` is what a well-behaved Mac app shows while working). A case
///   that silently falls back to an arrow on one of five is a case that lies.
/// - **No `grab`/`grabbing`.** AppKit has `closedHand` and `openHand`, GTK and
///   Android have both, WinUI has neither as a system shape. Same reason.
///
/// 在一個 view 上方所顯示的指標形狀。
///
/// **集合很小,因為五個平台的交集就很小;而一個「在每個平台上意思都不同」的名字,比一個不存在的名字更糟。**
/// 此處每一個 case 在 AppKit、GTK、WinUI 與 Android 上都存在。被省略的部分都是刻意的,而且各有理由:
///
/// - **沒有 `wait`。** GTK、WinUI、Android 都有;AppKit **沒有**公開的忙碌游標
///   (`NSCursor.busyButClickable` 是私有 API,而一個規矩的 Mac app 在忙碌時顯示的就是箭頭)。
///   一個「在五個之中有一個會靜默退回箭頭」的 case,是一個會說謊的 case。
/// - **沒有 `grab`/`grabbing`。** AppKit 有 `closedHand` 與 `openHand`,GTK 與 Android 兩者都有,
///   而 WinUI 沒有對應的系統形狀。理由相同。
public enum Cursor: Equatable, Sendable {
    /// The ordinary arrow.
    /// 一般的箭頭。
    case arrow
    /// The hand shown over something that can be clicked through to elsewhere.
    /// 顯示在「可點擊前往別處」之物上方的那隻手。
    case pointingHand
    /// Crosshairs, for picking a point precisely -- a canvas, a plot, a board.
    /// 十字準星,用於精確取點——畫布、圖表、電路板。
    case crosshair
    /// The I-beam shown over editable or selectable text.
    /// 顯示在可編輯或可選取文字上方的 I 形游標。
    case text
    /// A left-right arrow, for a vertical edge that can be dragged.
    /// 左右箭頭,用於可拖曳的垂直邊界。
    case resizeHorizontal
    /// An up-down arrow, for a horizontal edge that can be dragged.
    /// 上下箭頭,用於可拖曳的水平邊界。
    case resizeVertical
    /// The "this will not work" cursor.
    /// 「這樣行不通」的游標。
    case notAllowed
}

extension BackendFeatures {
    /// Choosing the pointer shape over a view.
    ///
    /// **SoftPCB's `plan.md` §10.7 lists this as gap 6, and its note is exact:**
    /// *no cursor API -- `NSCursor` does not appear in SwiftCrossUI at all.* The
    /// case it has in mind is a board that shows crosshairs while picking and a
    /// closed hand while dragging, which is a property of the view under the
    /// pointer and not of anything the framework draws.
    ///
    /// **A cursor is a region, not a widget, on three of the five.** AppKit
    /// wants cursor rects reset on demand, GTK sets a cursor on a widget, WinUI
    /// sets `ProtectedCursor`, and Android sets `pointerIcon`. The protocol
    /// takes a widget because that is the unit the framework has; a backend
    /// whose platform wants a rectangle derives it from the widget's bounds.
    ///
    /// **Conformance-checked, like ``ScrollGestures`` and ``KeyEvents``.**
    ///
    /// 選擇一個 view 上方的指標形狀。
    ///
    /// **SoftPCB `plan.md` §10.7 把它列為第 6 項缺口,而它的註記很精確:** *無游標 API——`NSCursor`
    /// 在 SwiftCrossUI 中完全沒有出現過。* 它心裡想的情況,是一塊「取點時顯示十字、拖曳時顯示握拳」的
    /// 板子;而那是「指標底下那個 view」的性質,不是框架所畫的任何東西的性質。
    ///
    /// **在五個之中有三個上,游標是一塊區域、不是一個 widget。** AppKit 要的是「隨需重設的 cursor rect」,
    /// GTK 是對 widget 設游標,WinUI 是設 `ProtectedCursor`,Android 是設 `pointerIcon`。這個協定取
    /// widget,因為那是框架手上的單位;平台想要矩形的 backend,自己從該 widget 的 bounds 推導。
    ///
    /// **採 conformance 檢查,與 ``ScrollGestures``、``KeyEvents`` 相同。**
    @MainActor
    public protocol Cursors: Core {
        func createCursorTarget(wrapping child: Widget) -> Widget

        func updateCursorTarget(
            _ target: Widget,
            cursor: Cursor,
            environment: EnvironmentValues
        )
    }
}
