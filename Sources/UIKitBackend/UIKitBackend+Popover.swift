@_spi(Backends) import SwiftCrossUI
import UIKit

extension UIKitBackend {
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

    func dismissProgrammatically() {
        dismiss(animated: true)
    }

    // Both paths report, and the programmatic one is NOT suppressed.
    //
    // It was, until 2026-09-08. The reasoning was that a caller who set
    // `isPresented = false` already knows the popover is going away, so telling
    // it again is noise -- which is wrong for the same reason SwiftUI's
    // `onDismiss` fires either way: the closure is where the caller cleans up
    // after the presentation, and whether the user tapped outside or the code
    // asked has nothing to do with whether that cleanup is needed.
    //
    // Suppressing it also made this backend the odd one out. AppKit never
    // suppressed, and the Windows side removed the equivalent flags from GTK
    // and WinUI in the same decision; this was the last of the five still
    // holding one, and it was mine.
    //
    // 兩條路徑都會回報,而程式化關閉的那一條**不再被抑制**。
    //
    // 它原本是被抑制的,直到 2026-09-08。當時的理由是:設定 `isPresented = false` 的呼叫端已經知道
    // popover 要消失了,再告訴它一次只是雜訊——而那是錯的,理由與 SwiftUI 的 `onDismiss` 兩種情況
    // 都會觸發相同:那個 closure 是呼叫端在呈現結束後做清理的地方,而「是使用者點了外面」還是
    // 「程式碼要求的」,與那份清理需不需要做完全無關。
    //
    // 抑制它也讓本 backend 成為五個之中的異類。AppKit 從來沒有抑制過,而 Windows 端在同一項決定中
    // 移除了 GTK 與 WinUI 的對應旗標;這是五個裡最後一個還壓著的,而它是我寫的。
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDismiss?()
    }
}
