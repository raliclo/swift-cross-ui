@_spi(Backends) import SwiftCrossUI
import UIKit

/// `BackendFeatures.BackNavigation` and `SheetBackNavigation` on iOS: a swipe in
/// from the left edge that follows the finger, as `UINavigationController`'s
/// does, and Command-[ from a hardware keyboard.
///
/// **The swipe** is a `UIScreenEdgePanGestureRecognizer` on the window, and on
/// each sheet's own view. When it begins, the screen is snapshotted and Back
/// runs at once, so the real previous screen renders underneath; the snapshot
/// then moves with the finger while the screen underneath slides in from 30%
/// of the width to the left, as the navigation controller's parallax does. On
/// release the swipe completes when the finger moves right faster than 300
/// points a second, or has passed half the width without moving left faster
/// than that (a finger held still for more than 0.1 s before lifting counts
/// as not moving: UIKit still reports the speed of its last movement);
/// otherwise it cancels, the snapshot slides back and
/// `BackNavigationUndo.undoLastBack()` restores the path. The stack therefore
/// reports one pop and one push for a cancelled swipe.
///
/// Other gestures in the window -- the root scroll view's pan above all -- wait
/// for the edge swipe to fail, which it does as soon as a touch begins away
/// from the edge: the relationship `UINavigationController` sets up between its
/// `interactivePopGestureRecognizer` and scroll views.
///
/// **Sheets.** The window's swipe and Command-[ do nothing while a controller is
/// presented over the window's root, so Back never reaches under a sheet; a
/// sheet with a stack that can pop takes them itself, and a sheet without one
/// keeps UIKit's own behaviour (swiping down to dismiss, when allowed).
///
/// **Command-[** is a `UIKeyCommand` published by `ApplicationDelegate`, which is
/// at the end of every responder chain -- the route `fallbackKeyCommands` takes
/// for menu shortcuts on iPhone. It runs the handler of whatever is in front
/// in the key window: the topmost presented sheet, or the window itself.
///
/// iOS 上的 `BackendFeatures.BackNavigation` 與 `SheetBackNavigation`:跟著手指移動的左緣滑動(與 `UINavigationController`
/// 相同),以及實體鍵盤的 Command-[。
///
/// **滑動**是掛在視窗、以及每個 sheet 自己的 view 上的 `UIScreenEdgePanGestureRecognizer`。開始時先替畫面拍快照，並立刻執行
/// 返回，讓真正的前一個畫面在底下繪出；之後快照跟著手指移動，底下的畫面從左側寬度 30% 處滑入，與 navigation controller 的
/// 視差相同。放開時，若手指正以每秒超過 300 point 的速度向右移動，或已越過一半寬度且沒有以那個速度向左移動，滑動就完成；
/// 否則取消：快照滑回原位,`BackNavigationUndo.undoLastBack()` 還原路徑。因此取消的滑動會讓堆疊回報一次彈出與一次推入。抬起前靜止
/// 超過 0.1 秒的手指視為沒有移動(UIKit 回報的仍是它最後一次移動的速度)。
///
/// 視窗中的其他手勢——尤其是根捲動視圖的 pan——會等邊緣滑動失敗，而只要觸碰從邊緣以外開始，它就立刻失敗：這正是
/// `UINavigationController` 在它的 `interactivePopGestureRecognizer` 與捲動視圖之間建立的關係。
///
/// **sheet。** 視窗的根之上有 controller 被呈現時，視窗的滑動與 Command-[ 什麼都不做，因此返回永遠不會穿到 sheet 底下；
/// 有可彈出堆疊的 sheet 自己接下它們，沒有的 sheet 保留 UIKit 自己的行為(允許時向下滑動關閉)。
///
/// **Command-[** 是由 `ApplicationDelegate` 公布的 `UIKeyCommand`,它位於每條 responder chain 的末端——iPhone 上選單快捷鍵的
/// `fallbackKeyCommands` 所走的路。它執行 key window 中位於前景者的 handler:最上層被呈現的 sheet,或視窗本身。
extension UIKitBackend: BackendFeatures.BackNavigation, BackendFeatures.SheetBackNavigation {
    public func setBackNavigationHandler(
        ofWindow window: Window,
        to action: (@MainActor () -> Bool)?
    ) {
        UIKitBackNavigation.of(window: window).handler = action
    }

    public func setBackNavigationHandler(
        ofSheet sheet: Sheet,
        to action: (@MainActor () -> Bool)?
    ) {
        UIKitBackNavigation.of(sheet: sheet).handler = action
    }
}

/// The Back of one window or one sheet: its handler and the edge swipe that
/// runs it. 一個視窗或一個 sheet 的返回：它的 handler,以及執行它的邊緣滑動。
@MainActor
final class UIKitBackNavigation: NSObject, UIGestureRecognizerDelegate {
    private static var byOwner: [ObjectIdentifier: UIKitBackNavigation] = [:]

    static func of(window: UIWindow) -> UIKitBackNavigation {
        let key = ObjectIdentifier(window)
        if let existing = byOwner[key] { return existing }
        let navigation = UIKitBackNavigation(window: window, sheet: nil)
        window.addGestureRecognizer(navigation.recognizer)
        byOwner[key] = navigation
        return navigation
    }

    static func of(sheet: CustomSheet) -> UIKitBackNavigation {
        let key = ObjectIdentifier(sheet)
        if let existing = byOwner[key] { return existing }
        let navigation = UIKitBackNavigation(window: nil, sheet: sheet)
        sheet.view.addGestureRecognizer(navigation.recognizer)
        byOwner[key] = navigation
        return navigation
    }

    /// The handler of whatever is in front in the key window, for Command-[.
    /// key window 中位於前景者的 handler,供 Command-[ 使用。
    static var keyWindowHandler: (@MainActor () -> Bool)? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard let keyWindow, let root = keyWindow.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        if top === root { return byOwner[ObjectIdentifier(keyWindow)]?.handler }
        return byOwner[ObjectIdentifier(top)]?.handler
    }

    private weak var window: UIWindow?
    private weak var sheet: CustomSheet?

    var handler: (@MainActor () -> Bool)? {
        didSet { recognizer.isEnabled = handler != nil || snapshot != nil }
    }

    private let recognizer = UIScreenEdgePanGestureRecognizer()
    /// The popped screen, moving with the finger. 被彈出的畫面，跟著手指移動。
    private var snapshot: UIView?
    /// When the finger last moved, to tell a still finger from a moving one.
    /// 手指上一次移動的時間，用來分辨靜止與移動中的手指。
    private var lastMoveTime: CFTimeInterval = 0
    /// How far left the screen underneath starts, as a fraction of the width.
    /// 底下的畫面起始時向左偏移多少，以寬度的比例表示。
    private static let parallax: CGFloat = 0.3

    private init(window: UIWindow?, sheet: CustomSheet?) {
        self.window = window
        self.sheet = sheet
        super.init()
        recognizer.edges = .left
        recognizer.isEnabled = false
        recognizer.delegate = self
        recognizer.addTarget(self, action: #selector(edgePanned(_:)))
    }

    /// The controller whose view slides: the sheet, or the window's root.
    /// 其 view 會滑動的 controller:sheet,或視窗的根。
    private var controller: UIViewController? {
        sheet ?? window?.rootViewController
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Nothing presented over this window or sheet. 這個視窗或 sheet 之上沒有被呈現的東西。
        handler != nil && snapshot == nil && controller?.presentedViewController == nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func edgePanned(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        guard let host = controller?.view, let container = host.superview else { return }
        let width = max(host.bounds.width, 1)
        let translation = max(0, recognizer.translation(in: container).x)
        switch recognizer.state {
            case .began:
                guard let handler, let content = host.snapshotView(afterScreenUpdates: false) else {
                    return
                }
                // The snapshot of a view with a clear background is see-through;
                // it rides on a card of the window's background colour.
                // 背景透明之 view 的快照是透明的；它放在一張以視窗背景色填滿的卡片上。
                let image = UIView(frame: host.frame)
                image.backgroundColor =
                    host.backgroundColor ?? host.window?.backgroundColor ?? .systemBackground
                content.frame = image.bounds
                image.addSubview(content)
                image.layer.shadowColor = UIColor.black.cgColor
                image.layer.shadowOpacity = 0.25
                image.layer.shadowRadius = 8
                image.layer.shadowOffset = CGSize(width: -2, height: 0)
                container.insertSubview(image, aboveSubview: host)
                guard handler() else {
                    image.removeFromSuperview()
                    return
                }
                snapshot = image
                move(host: host, image: image, by: translation, width: width)
                lastMoveTime = CACurrentMediaTime()
            case .changed:
                guard let image = snapshot else { return }
                move(host: host, image: image, by: translation, width: width)
                lastMoveTime = CACurrentMediaTime()
            case .ended, .cancelled, .failed:
                guard let image = snapshot else { return }
                // A finger held still before lifting reports the speed of its
                // last movement; held for more than 0.1 s it is not moving.
                // 抬起前靜止不動的手指，回報的是它最後一次移動的速度；靜止超過 0.1 秒就是沒有在動。
                let isStill = CACurrentMediaTime() - lastMoveTime > 0.1
                let speed = isStill ? 0 : recognizer.velocity(in: container).x
                let completes =
                    recognizer.state == .ended
                    && (speed > 300 || (translation > width / 2 && speed > -300))
                finish(host: host, image: image, width: width, completes: completes)
            default:
                break
        }
    }

    private func move(host: UIView, image: UIView, by translation: CGFloat, width: CGFloat) {
        image.transform = CGAffineTransform(translationX: translation, y: 0)
        host.transform = CGAffineTransform(
            translationX: -Self.parallax * (width - translation),
            y: 0
        )
    }

    private func finish(host: UIView, image: UIView, width: CGFloat, completes: Bool) {
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                if completes {
                    image.transform = CGAffineTransform(translationX: width, y: 0)
                    host.transform = .identity
                } else {
                    image.transform = .identity
                    host.transform = CGAffineTransform(translationX: -Self.parallax * width, y: 0)
                }
            },
            completion: { [weak self] _ in
                if completes {
                    image.removeFromSuperview()
                    self?.snapshot = nil
                    return
                }
                // The snapshot covers the screen while the path is put back and
                // the pushed screen renders again under it.
                // 路徑放回、被推入的畫面在底下重新繪出的期間，由快照蓋住畫面。
                BackNavigationUndo.undoLastBack()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    host.transform = .identity
                    image.removeFromSuperview()
                    self?.snapshot = nil
                }
            }
        )
    }
}

extension ApplicationDelegate {
    /// Command-[, while whatever is in front in the key window can go back.
    /// Command-[,在 key window 中位於前景者可以返回時提供。
    var backNavigationKeyCommands: [UIKeyCommand] {
        guard UIKitBackNavigation.keyWindowHandler != nil else { return [] }
        let command = UIKeyCommand(
            input: "[",
            modifierFlags: .command,
            action: #selector(scuiNavigateBack(_:))
        )
        command.discoverabilityTitle = "Back"
        return [command]
    }

    @objc func scuiNavigateBack(_ sender: Any?) {
        _ = UIKitBackNavigation.keyWindowHandler?()
    }
}
