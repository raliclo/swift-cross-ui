@_spi(Backends) import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.Popovers {
    public typealias Popover = CustomPopover

    public func createPopover(content: Widget) -> CustomPopover {
        let popover = CustomPopover()

        // `.popover` on every idiom, deliberately. On iPad and Mac Catalyst it
        // is an anchored popover; on iPhone UIKit adapts it into a sheet by
        // itself, because a popover on a phone would cover the thing it points
        // at. That adaptation is the platform's own answer and it is the right
        // one there -- which is a different thing from this backend choosing a
        // sheet on a device that would have drawn a popover.
        //
        // 在每一種 idiom 上都使用 `.popover`,這是刻意的。在 iPad 與 Mac Catalyst 上它是一個有錨點的
        // popover;在 iPhone 上,UIKit 會自行把它調適為 sheet——因為手機上的 popover 會蓋住它所指向的
        // 東西。那項調適是平台自身的答案,而且在那裡是正確的——這與「本 backend 在一個原本會畫出
        // popover 的裝置上選擇了 sheet」是兩回事。
        popover.modalPresentationStyle = .popover

        let contentView = UIView()
        if let childController = content.controller {
            popover.addChild(childController)
        }
        contentView.addSubview(content.view)
        popover.view = contentView
        popover.customContent = content.view

        return popover
    }

    public func updatePopover(
        _ popover: CustomPopover,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        onDismiss: @escaping () -> Void
    ) {
        let contentSize = CGSize(width: size.x, height: size.y)
        popover.preferredContentSize = contentSize
        popover.customContent?.frame = CGRect(origin: .zero, size: contentSize)
        popover.onDismiss = onDismiss
    }

    public func presentPopover(
        _ popover: CustomPopover,
        relativeTo anchor: Widget,
        window: Window
    ) {
        // The anchor is a view in the window, and UIKit positions from a view
        // plus a rect within it. Setting both is what makes this a popover
        // rather than a centred modal.
        // 錨點是視窗中的一個 view,而 UIKit 是以「一個 view 加上其內部的一個矩形」來定位的。
        // 兩者都設定,才使這成為一個 popover,而不是一個置中的 modal。
        if let presentation = popover.popoverPresentationController {
            presentation.sourceView = anchor.view
            presentation.sourceRect = anchor.view.bounds
            presentation.permittedArrowDirections = [.up, .down]
            presentation.delegate = popover
        }

        window.rootViewController?.present(popover, animated: true)
    }

    public func dismissPopover(_ popover: CustomPopover, window: Window) {
        popover.dismissProgrammatically()
    }

    public func size(ofPopover popover: CustomPopover) -> SIMD2<Int> {
        SIMD2(
            Int(popover.preferredContentSize.width),
            Int(popover.preferredContentSize.height)
        )
    }
}

/// A popover that reports its own dismissal.
///
/// A popover is dismissed by tapping outside it, and nothing in the view tree
/// hears that. Without the callback the modifier's `isPresented` stays true,
/// the next press is a no-op because it is already "presented", and the popover
/// never returns. `CustomSheet` carries the same machinery for the same reason.
///
/// 一個會回報自身關閉的 popover。
///
/// popover 是靠點擊它以外的地方來關閉的,而 view 樹中沒有任何東西會聽到。少了這個回呼,modifier 的
/// `isPresented` 會維持為真,下一次按下不會有任何作用——因為它「已經呈現了」——而該 popover 再也不會
/// 回來。`CustomSheet` 基於同樣的理由帶有同樣的機制。
public final class CustomPopover: UIViewController, UIPopoverPresentationControllerDelegate {
    var onDismiss: (() -> Void)?
    var customContent: UIView?
    private var wasDismissedProgrammatically = false

    func dismissProgrammatically() {
        wasDismissedProgrammatically = true
        dismiss(animated: true)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !wasDismissedProgrammatically else {
            wasDismissedProgrammatically = false
            return
        }
        onDismiss?()
    }
}
