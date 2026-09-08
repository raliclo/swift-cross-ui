import AppKit
@_spi(Backends) import SwiftCrossUI

extension AppKitBackend {
    public typealias Popover = NSCustomPopover

    public func createPopover(content: NSView) -> NSCustomPopover {
        let popover = NSCustomPopover()

        // `.transient` is what makes it a popover rather than a small window:
        // it closes when the user clicks anywhere outside it, which is the
        // behaviour every platform's popover has and the reason a caller
        // reaches for one.
        // `.transient` 正是讓它成為 popover、而非一個小視窗的關鍵:使用者點擊它以外的任何地方時它
        // 就會關閉,而那是每個平台的 popover 都具備的行為,也是呼叫端會選用它的理由。
        popover.behavior = .transient

        let controller = NSViewController()
        // A container rather than the content view itself. NSPopover sizes its
        // content from the controller's view, and handing it a view that the
        // layout system also owns means two things setting the same frame.
        // 使用容器而非內容 view 本身。NSPopover 是依 controller 的 view 來決定其內容尺寸的,而把一個
        // 版面系統同時擁有的 view 交給它,會變成兩邊都在設定同一個 frame。
        let container = NSView()
        container.addSubview(content)
        controller.view = container
        popover.contentViewController = controller
        popover.customContent = content

        return popover
    }

    public func updatePopover(
        _ popover: NSCustomPopover,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        onDismiss: @escaping () -> Void
    ) {
        let contentSize = NSSize(width: size.x, height: size.y)
        popover.contentSize = contentSize
        popover.contentViewController?.view.frame = NSRect(
            origin: .zero,
            size: contentSize
        )
        popover.customContent?.frame = NSRect(origin: .zero, size: contentSize)
        popover.onDismiss = onDismiss
    }

    public func presentPopover(
        _ popover: NSCustomPopover,
        relativeTo anchor: NSView,
        window: NSCustomWindow
    ) {
        // `.maxY` puts it below the anchor, which is where a popover opened
        // from a button belongs. AppKit moves it to another edge by itself when
        // there is no room, which is the rule this backend is being left to
        // keep.
        // `.maxY` 會把它放在錨點下方,而那正是由按鈕開啟的 popover 該在的位置。空間不足時,AppKit
        // 會自行把它移到另一側——那正是此處刻意讓這個 backend 保有的規則。
        popover.show(
            relativeTo: anchor.bounds,
            of: anchor,
            preferredEdge: .maxY
        )
    }

    public func dismissPopover(_ popover: NSCustomPopover, window: NSCustomWindow) {
        // `performClose` rather than `close`: it runs the delegate callbacks,
        // and this backend's dismissal bookkeeping hangs off them. `close`
        // would take the popover off screen and leave the modifier believing it
        // was still up.
        // 使用 `performClose` 而非 `close`:前者會執行 delegate 回呼,而本 backend 的關閉記錄正是掛在
        // 那些回呼上。`close` 會把 popover 移出畫面,卻讓 modifier 以為它仍然開著。
        popover.performClose(nil)
    }

    public func size(ofPopover popover: NSCustomPopover) -> SIMD2<Int> {
        SIMD2(Int(popover.contentSize.width), Int(popover.contentSize.height))
    }
}

/// An `NSPopover` that reports its own dismissal.
///
/// Needed because a popover is `.transient`: the user closes it by clicking
/// somewhere else, and nothing in the view tree hears about that. Without the
/// callback the modifier's `isPresented` stays true, the next press does
/// nothing because it is already "presented", and the popover never comes back.
///
/// 一個會回報自身關閉的 `NSPopover`。
///
/// 之所以需要它,是因為 popover 是 `.transient` 的:使用者是靠點擊別處來關閉它的,而 view 樹中沒有
/// 任何東西會聽到這件事。少了這個回呼,modifier 的 `isPresented` 會維持為真,下一次按下也不會有任何
/// 反應——因為它「已經呈現了」——而該 popover 再也不會出現。
public final class NSCustomPopover: NSPopover, NSPopoverDelegate {
    var onDismiss: (() -> Void)?
    var customContent: NSView?

    override public init() {
        super.init()
        delegate = self
    }

    // Required by NSPopover and unreachable here: this backend never
    // unarchives a popover, it constructs them. Trapping says so rather than
    // returning something half-built that would fail later and elsewhere.
    // NSPopover 要求提供,而此處不可能被觸及:本 backend 從不從封存還原 popover,它是建構它們的。
    // 此處直接中止是為了把這件事說清楚,而不是回傳一個「半成品」讓它稍後在別處失敗。
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NSCustomPopover cannot be created from a coder")
    }

    public func popoverDidClose(_ notification: Notification) {
        onDismiss?()
    }
}
