import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.FocusableTargets {
    public func createFocusableTarget(wrapping child: Widget) -> Widget {
        FocusableWidget(child: child)
    }

    public func updateFocusableTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        isFocusable: Bool
    ) {
        (target as! FocusableWidget).focusableView.isFocusable =
            isFocusable && environment.isEnabled
    }
}

/// `.focusable()` on UIKit.
///
/// UIKit has two things called focus and a plain view needs both. The first
/// responder is where key presses go; the focus system (iPadOS and Mac Catalyst
/// with a keyboard) is what Tab moves. The view can become either, and becomes
/// first responder when the focus system lands on it, so Tab and a tap end in
/// the same state.
///
/// UIKit 上的 `.focusable()`。UIKit 有兩樣東西都叫焦點，普通的 view 兩樣都要:first responder 是按鍵的去處;
/// focus system(有鍵盤的 iPadOS 與 Mac Catalyst)是 Tab 移動的東西。這個 view 兩者都能成為，並在 focus system
/// 落到它身上時成為 first responder,所以 Tab 與點擊最後是同一個狀態。
final class FocusableWidget: ContainerWidget {
    let focusableView = FocusableView()

    override func loadView() {
        view = focusableView
    }
}

final class FocusableView: UIView, UIGestureRecognizerDelegate {
    /// Posted with the view as object when it gains or loses first responder:
    /// UIKit announces that only for text views, and `FocusObserver` listens.
    /// 這個 view 取得或失去 first responder 時發出，object 是它自己:UIKit 只替文字 view 宣告這件事，
    /// 而 `FocusObserver` 在聽。
    static let focusDidChange = Notification.Name("SwiftCrossUI.FocusableView.focusDidChange")

    var isFocusable = true {
        didSet {
            guard isFocusable != oldValue else { return }
            if !isFocusable, isFirstResponder { _ = resignFirstResponder() }
            setNeedsFocusUpdate()
        }
    }

    private let ring = CALayer()

    init() {
        super.init(frame: .zero)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        addGestureRecognizer(tap)
        ring.borderWidth = 2
        ring.cornerRadius = 3
        ring.isHidden = true
        ring.zPosition = 1
        layer.addSublayer(ring)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ring.frame = bounds.insetBy(dx: -2, dy: -2)
        ring.borderColor = tintColor.cgColor
    }

    override var canBecomeFirstResponder: Bool { isFocusable }
    override var canBecomeFocused: Bool { isFocusable }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let took = super.becomeFirstResponder()
        if took { focusChanged() }
        return took
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let left = super.resignFirstResponder()
        if left { focusChanged() }
        return left
    }

    private func focusChanged() {
        ring.isHidden = !isFirstResponder
        NotificationCenter.default.post(name: Self.focusDidChange, object: self)
    }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        if context.nextFocusedItem === self { becomeFirstResponder() }
    }

    @objc private func tapped() {
        if isFocusable { becomeFirstResponder() }
    }

    /// Tab and Shift-Tab move the first responder on, here.
    ///
    /// The focus system would do it on iPadOS, but only for a press that reaches
    /// the end of the responder chain, and a `KeyEventWidget` above this view
    /// reports every press it is given and passes none on: Tab from one
    /// focusable view stayed on it and was typed into it (P91 on the iPad
    /// simulator, 2026-10-13). So the next stop is found here -- the focusable
    /// views and text inputs of the window, in reading order, wrapping round.
    /// Tab 與 Shift-Tab 在這裡把 first responder 往下移。iPadOS 的 focus system 本來會做，但只對走到 responder
    /// chain 盡頭的按壓，而這個 view 上方的 `KeyEventWidget` 會回報它收到的每個按壓、一個也不往上傳:從一個可聚焦的
    /// view 按 Tab 會留在原地並被當成輸入。所以下一站在這裡找——視窗內可聚焦的 view 與文字輸入，依閱讀順序，繞回開頭。
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isFirstResponder,
              let tab = presses.first(where: { $0.key?.keyCode == .keyboardTab }),
              let window
        else {
            super.pressesBegan(presses, with: event)
            return
        }
        var stops: [UIView] = []
        func collect(_ view: UIView) {
            guard !view.isHidden, view.isUserInteractionEnabled else { return }
            if view is FocusableView || view is UITextField || view is UITextView {
                if view.canBecomeFirstResponder { stops.append(view) }
                return
            }
            view.subviews.forEach(collect)
        }
        collect(window)
        func origin(_ view: UIView) -> CGPoint { view.convert(CGPoint.zero, to: window) }
        stops.sort {
            let a = origin($0)
            let b = origin($1)
            return abs(a.y - b.y) > 1 ? a.y < b.y : a.x < b.x
        }
        guard let index = stops.firstIndex(of: self), stops.count > 1 else { return }
        let backwards = tab.key?.modifierFlags.contains(.shift) ?? false
        let next = stops[(index + (backwards ? stops.count - 1 : 1)) % stops.count]
        next.becomeFirstResponder()
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // The Tab that was handled above is not reported on its way up either.
        // 上面處理掉的 Tab,放開時也不往上回報。
        if presses.contains(where: { $0.key?.keyCode == .keyboardTab }) { return }
        super.pressesEnded(presses, with: event)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }

    /// Whether `view` holds a focusable view: a key target around one waits for
    /// the focus instead of taking it.
    /// `view` 裡是否有可聚焦的 view:包著它的按鍵 target 會等焦點，而不是自己拿。
    static func isHeld(by view: UIView) -> Bool {
        view.subviews.contains { $0 is FocusableView || isHeld(by: $0) }
    }
}
