@_spi(Backends) import SwiftCrossUI
import UIKit

/// `.popover` for UIKit, built on `UIPopoverPresentationController`.
///
/// **The one decision here that is not mechanical.** On iPhone, UIKit adapts a
/// `.popover` presentation into a full-screen `.pageSheet` by default. That is
/// what SwiftUI's `.popover` does on iPhone too. This backend asks for `.none`
/// instead, through `adaptivePresentationStyle(for:traitCollection:)`, and so
/// stays a popover on every device.
///
/// The reason is that SwiftCrossUI already has `sheet`. A caller who wants a
/// sheet writes `sheet`; a caller who writes `popover` and receives a sheet has
/// no way left to ask for a popover, and no way to tell from the code which one
/// they will get. Adapting silently trades an anchored panel for a modal --
/// different dismissal, different position, different everything -- while
/// leaving the source identical on both platforms. Keeping the popover is the
/// behaviour that can be relied on; a caller who prefers the iPhone convention
/// can still write `sheet` and get exactly it.
///
/// 為 UIKit 實作的 `.popover`，建構於 `UIPopoverPresentationController` 之上。
///
/// **此處唯一不是機械式套用的決定。** 在 iPhone 上，UIKit 預設會把 `.popover` 呈現調適成全螢幕的
/// `.pageSheet`。SwiftUI 的 `.popover` 在 iPhone 上也是如此。本 backend 改為透過
/// `adaptivePresentationStyle(for:traitCollection:)` 要求 `.none`，因而在所有裝置上都維持為 popover。
///
/// 理由是 SwiftCrossUI 已經有 `sheet` 了。想要 sheet 的呼叫端會寫 `sheet`；而寫了 `popover` 卻收到
/// sheet 的呼叫端，就再也沒有辦法要求一個 popover，也無從從程式碼看出自己會拿到哪一個。靜默的調適
/// 是把一塊錨定的面板換成一個模態視窗——關閉方式不同、位置不同、一切都不同——而原始碼在兩個平台上
/// 卻一模一樣。維持 popover 才是可被依賴的行為；偏好 iPhone 慣例的呼叫端仍然可以寫 `sheet`，並且
/// 恰好得到它。
extension UIKitBackend: BackendFeatures.Popovers {
    public typealias Popover = CustomPopover

    public func createPopover(content: Widget) -> CustomPopover {
        CustomPopover(content: content)
    }

    public func updatePopover(
        _ popover: CustomPopover,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        attachmentEdge: Edge,
        backgroundColor: SwiftCrossUI.Color.Resolved?,
        onDismiss: @escaping () -> Void
    ) {
        popover.onDismiss = onDismiss
        popover.preferredContentSize = CGSize(width: size.x, height: size.y)

        // `permittedArrowDirections` is where the arrow may point *from* the
        // popover towards the anchor, which is the mirror of the edge the caller
        // named: a popover below its anchor has an arrow pointing up.
        //
        // A single direction rather than a set, deliberately. UIKit falls back
        // to another side on its own when the named one does not fit, and a set
        // would let it choose a side the caller did not ask for even when the
        // named one fits perfectly.
        //
        // `permittedArrowDirections` 指的是箭頭從 popover **指向**錨點的方向，那是呼叫端所指定之邊
        // 的鏡像：位於錨點下方的 popover，其箭頭朝上。
        //
        // 刻意使用單一方向而非集合。當指定的一側放不下時，UIKit 自己就會退到另一側；而使用集合會讓
        // 它即使在指定的一側完全放得下時，也可能選擇呼叫端沒有要求的那一側。
        popover.arrowDirection = switch attachmentEdge {
            case .top: .down
            case .bottom: .up
            case .leading: .right
            case .trailing: .left
        }
        popover.popoverPresentationController?.permittedArrowDirections = popover.arrowDirection

        // A popover's background is the arrow's background too, so it goes on
        // the presentation controller rather than on the view: setting
        // `view.backgroundColor` alone leaves the beak in the default colour and
        // the join visibly wrong.
        // popover 的背景同時也是箭頭的背景，因此它設定在 presentation controller 上而非設定在 view
        // 上：只設定 `view.backgroundColor` 會讓尖角維持預設顏色，接合處看起來明顯不對。
        let color = backgroundColor?.uiColor
        popover.view.backgroundColor = color
        popover.popoverPresentationController?.backgroundColor = color
    }

    public func showPopover(_ popover: CustomPopover, relativeTo widget: Widget, window: Window) {
        let presentationController = popover.popoverPresentationController
        presentationController?.sourceView = widget.view
        presentationController?.sourceRect = widget.view.bounds
        presentationController?.permittedArrowDirections = popover.arrowDirection
        presentationController?.delegate = popover

        // The anchor's own controller, not the window's root. A popover
        // presented from inside a sheet must be presented by the sheet's
        // controller; going to the root would try to present on a controller
        // that already has a presentation and UIKit would refuse it. `controller`
        // walks the responder chain, so it finds the sheet when there is one and
        // the root when there is not.
        // 使用錨點自身的 controller，而非視窗的 root。從 sheet 內部呈現的 popover 必須由該 sheet 的
        // controller 呈現；若改用 root，等於嘗試在一個已有呈現內容的 controller 上再呈現，UIKit 會
        // 拒絕。`controller` 會沿著 responder chain 往上找，因此有 sheet 時找到 sheet，沒有時找到 root。
        let presenter = widget.controller ?? window.rootViewController
        presenter?.present(popover, animated: true)
    }

    public func dismissPopover(_ popover: CustomPopover) {
        popover.dismissProgrammatically()
    }
}

/// The controller presented as a popover.
///
/// It is its own `UIPopoverPresentationControllerDelegate` for the adaptation
/// override described on the extension above, and its own dismissal bookkeeper
/// for the same reason `CustomSheet` is: `viewDidDisappear` cannot tell a user
/// dismissal from a programmatic one, and the
/// ``BackendFeatures/Popovers`` contract distinguishes them.
///
/// 以 popover 形式呈現的 controller。
///
/// 它同時是自己的 `UIPopoverPresentationControllerDelegate`，用於上方 extension 所述的調適覆寫；
/// 也同時是自己的關閉記帳者，理由與 `CustomSheet` 相同：`viewDidDisappear` 無法分辨使用者關閉與
/// 程式關閉，而 ``BackendFeatures/Popovers`` 的約定區分這兩者。
public final class CustomPopover: UIViewController, UIPopoverPresentationControllerDelegate {
    var onDismiss: (() -> Void)?
    var arrowDirection: UIPopoverArrowDirection = .up
    private var wasDismissedProgrammatically = false

    init(content: any WidgetProtocol) {
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .popover

        let contentView = UIView()
        // Fetch the child controller before adding the child to the view
        // hierarchy, for the same reason `createSheet` does: otherwise, if the
        // child has no controller of its own, `controller` walks up to this one
        // and we would add it as a child of itself.
        // 在把子元件加入 view 階層之前先取得其 controller，理由與 `createSheet` 相同：否則若該子元件
        // 沒有自己的 controller，`controller` 會往上找到本 controller，我們就會把它加成自己的子項。
        if let childController = content.controller {
            addChild(childController)
        }
        contentView.addSubview(content.view)

        content.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: content.view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
            contentView.bottomAnchor.constraint(equalTo: content.view.bottomAnchor),
            contentView.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),
        ])

        view = contentView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used for this popover")
    }

    func dismissProgrammatically() {
        wasDismissedProgrammatically = true
        dismiss(animated: true)
    }

    /// Keeps the popover a popover on iPhone. See the extension's documentation.
    /// 讓 popover 在 iPhone 上維持為 popover。見 extension 的文件。
    public func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if !wasDismissedProgrammatically {
            onDismiss?()
        }
        wasDismissedProgrammatically = false
    }
}
