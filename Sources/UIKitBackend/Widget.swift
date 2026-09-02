import UIKit

public protocol WidgetProtocol: UIResponder {
    var x: Int { get set }
    var y: Int { get set }
    var width: Int { get set }
    var height: Int { get set }

    var view: UIView! { get }
    /// The widget's enclosing controller. Could be the widget's own controller,
    /// or that of a parent view. `WidgetProtocolHelpers` implements this on
    /// your behalf by walking up the responder chain until it finds a controller.
    var controller: UIViewController? { get }

    var childWidgets: [any WidgetProtocol] { get set }
    var parentWidget: (any WidgetProtocol)? { get set }

    func removeFromParentWidget()
}

extension UIKitBackend {
    public typealias Widget = any WidgetProtocol
}

private protocol WidgetProtocolHelpers: WidgetProtocol {
    var leftConstraint: NSLayoutConstraint? { get set }
    var topConstraint: NSLayoutConstraint? { get set }
    var widthConstraint: NSLayoutConstraint? { get set }
    var heightConstraint: NSLayoutConstraint? { get set }
}

extension WidgetProtocolHelpers {
    func updateLeftConstraint() {
        guard let superview = view.superview else {
            leftConstraint?.isActive = false
            return
        }

        if let leftConstraint,
           leftConstraint.secondAnchor === superview.safeAreaLayoutGuide.leftAnchor
        {
            leftConstraint.constant = CGFloat(x)
            leftConstraint.isActive = true
        } else {
            self.leftConstraint?.isActive = false
            let leftConstraint = view.leftAnchor.constraint(
                equalTo: superview.safeAreaLayoutGuide.leftAnchor,
                constant: CGFloat(x)
            )
            self.leftConstraint = leftConstraint
            // Set the constraint priority for leftConstraint (and topConstraint) to just
            // under "required" so that we don't get warnings about unsatisfiable constraints
            // from scroll views, which position relative to their contentLayoutGuide instead.
            // This *should* be high enough that it won't cause any problems unless there was
            // a constraint conflict anyways.
            leftConstraint.priority = .init(UILayoutPriority.required.rawValue - 1.0)
            leftConstraint.isActive = true
        }
    }

    func updateTopConstraint() {
        guard let superview = view.superview else {
            topConstraint?.isActive = false
            return
        }

        if let topConstraint,
           topConstraint.secondAnchor === superview.safeAreaLayoutGuide.topAnchor
        {
            topConstraint.constant = CGFloat(y)
            topConstraint.isActive = true
        } else {
            self.topConstraint?.isActive = false
            let topConstraint = view.topAnchor.constraint(
                equalTo: superview.safeAreaLayoutGuide.topAnchor,
                constant: CGFloat(y)
            )
            self.topConstraint = topConstraint
            topConstraint.priority = .init(UILayoutPriority.required.rawValue - 1.0)
            topConstraint.isActive = true
        }
    }

    func updateWidthConstraint() {
        if let widthConstraint {
            widthConstraint.constant = CGFloat(width)
        } else {
            let widthConstraint = view.widthAnchor.constraint(equalToConstant: CGFloat(width))
            self.widthConstraint = widthConstraint
            widthConstraint.isActive = true
        }
    }

    func updateHeightConstraint() {
        if let heightConstraint {
            heightConstraint.constant = CGFloat(height)
        } else {
            let heightConstraint = view.heightAnchor.constraint(equalToConstant: CGFloat(height))
            self.heightConstraint = heightConstraint
            heightConstraint.isActive = true
        }
    }
}

class BaseViewWidget: UIView, WidgetProtocolHelpers {
    /// A container is never the target of a touch; only its contents are.
    ///
    /// `UIView.hitTest` returns any view whose bounds contain the point, so a
    /// backend container with nothing interactive in it still swallows every
    /// touch that lands on it. #454 is exactly that case: "the ZStack's upper
    /// layer is a transparent colour. It covers the button but should not take
    /// its clicks."
    ///
    /// Measured on the simulator 2026-09-02, replaying P10: the tap on "Click
    /// me too" left `Covered clicks` at 0 while the overlay was present, and
    /// the overlay is a container, not the colour itself. AppKit reaches the
    /// same behaviour through `AppKitHitTestingContainer`, which returns nil
    /// when no child claims the point; measured the same day it reports
    /// Direct 2, Covered 2, Hidden 2 -- all three land.
    ///
    /// Views with a gesture recogniser keep the default. A container that has
    /// been given something to do with a touch is not a pass-through, and
    /// `onTapGesture` on a `Color` is the case that would otherwise break.
    ///
    /// 容器永遠不是觸控的目標，只有它的內容才是。
    ///
    /// `UIView.hitTest` 會回傳任何 bounds 包含該點的 view，因此一個內部沒有任何可互動元件的 backend
    /// 容器，仍會吞掉每一次落在它身上的觸控。#454 正是這個情況：「ZStack 的上層是透明顏色。它覆蓋著
    /// 按鈕，但不應取走它的點擊。」
    ///
    /// 2026-09-02 於模擬器上重放 P10 實測：overlay 存在期間，對「Click me too」的點擊使
    /// `Covered clicks` 維持在 0，而該 overlay 是一個容器，不是顏色本身。AppKit 透過
    /// `AppKitHitTestingContainer` 達成相同行為——它在沒有任何 child 宣稱該點時回傳 nil；同日量測
    /// 其結果為 Direct 2、Covered 2、Hidden 2，三者皆命中。
    ///
    /// 帶有 gesture recogniser 的 view 維持預設行為。一個已被賦予「對觸控做某件事」的容器並非
    /// pass-through，而 `Color` 上的 `onTapGesture` 正是否則會被弄壞的那個情況。
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        guard hit === self else { return hit }
        if let recognizers = gestureRecognizers, !recognizers.isEmpty { return self }
        return nil
    }

    fileprivate var leftConstraint: NSLayoutConstraint?
    fileprivate var topConstraint: NSLayoutConstraint?
    fileprivate var widthConstraint: NSLayoutConstraint?
    fileprivate var heightConstraint: NSLayoutConstraint?

    var x = 0 {
        didSet {
            if x != oldValue {
                updateLeftConstraint()
            }
        }
    }

    var y = 0 {
        didSet {
            if y != oldValue {
                updateTopConstraint()
            }
        }
    }

    var width = 0 {
        didSet {
            if width != oldValue {
                updateWidthConstraint()
            }
        }
    }

    var height = 0 {
        didSet {
            if height != oldValue {
                updateHeightConstraint()
            }
        }
    }

    var childWidgets: [any WidgetProtocol] = []
    weak var parentWidget: (any WidgetProtocol)?

    var view: UIView! { self }

    /// The widget's enclosing controller. Found by walking up the responder
    /// chain until a controller is found.
    var controller: UIViewController? {
        var responder: UIResponder = self
        while let next = responder.next {
            if let controller = next as? UIViewController {
                return controller
            }
            responder = next
        }
        return nil
    }

    init() {
        super.init(frame: .zero)

        self.translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used for this view")
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()

        updateLeftConstraint()
        updateTopConstraint()
    }

    func add(childWidget: some WidgetProtocol) {
        if childWidget.parentWidget === self { return }
        childWidget.removeFromParentWidget()

        let childController = childWidget.controller

        addSubview(childWidget.view)

        if let controller,
           let childController
        {
            controller.addChild(childController)
            childController.didMove(toParent: controller)
        }

        childWidgets.append(childWidget)
        childWidget.parentWidget = self
    }

    func insert(_ childWidget: some WidgetProtocol, at index: Int) {
        if childWidget.parentWidget === self { return }
        childWidget.removeFromParentWidget()

        let childController = childWidget.controller

        insertSubview(childWidget.view, at: index)

        if let controller, let childController {
            controller.addChild(childController)
            childController.didMove(toParent: controller)
        }

        childWidgets.insert(childWidget, at: index)
        childWidget.parentWidget = self
    }

    func removeFromParentWidget() {
        if let parentWidget {
            parentWidget.childWidgets.remove(
                at: parentWidget.childWidgets.firstIndex { $0 === self }!
            )
            self.parentWidget = nil
        }
        removeFromSuperview()
    }
}

class BaseControllerWidget: UIViewController, WidgetProtocolHelpers {
    fileprivate var leftConstraint: NSLayoutConstraint?
    fileprivate var topConstraint: NSLayoutConstraint?
    fileprivate var widthConstraint: NSLayoutConstraint?
    fileprivate var heightConstraint: NSLayoutConstraint?

    var x = 0 {
        didSet {
            if x != oldValue {
                updateLeftConstraint()
            }
        }
    }

    var y = 0 {
        didSet {
            if y != oldValue {
                updateTopConstraint()
            }
        }
    }

    var width = 0 {
        didSet {
            if width != oldValue {
                updateWidthConstraint()
            }
        }
    }

    var height = 0 {
        didSet {
            if height != oldValue {
                updateHeightConstraint()
            }
        }
    }

    var childWidgets: [any WidgetProtocol]
    weak var parentWidget: (any WidgetProtocol)?

    var controller: UIViewController? { self }

    init() {
        childWidgets = []
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used for this view")
    }

    func add(childWidget: some WidgetProtocol) {
        if childWidget.parentWidget === self { return }
        childWidget.removeFromParentWidget()

        let childController = childWidget.controller

        view.addSubview(childWidget.view)

        if let childController {
            addChild(childController)
            childController.didMove(toParent: self)
        }

        childWidgets.append(childWidget)
        childWidget.parentWidget = self
    }

    func removeFromParentWidget() {
        if let parentWidget {
            parentWidget.childWidgets.remove(
                at: parentWidget.childWidgets.firstIndex { $0 === self }!
            )
            self.parentWidget = nil
        }
        if parent != nil {
            willMove(toParent: nil)
            removeFromParent()
        }
        view.removeFromSuperview()
    }

    override func viewDidLoad() {
        view.translatesAutoresizingMaskIntoConstraints = false
        super.viewDidLoad()
    }
}

class WrapperWidget<View: UIView>: BaseViewWidget {
    init(child: View) {
        super.init()

        self.addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: self.topAnchor),
            child.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            child.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            child.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])
    }

    override convenience init() {
        self.init(child: View(frame: .zero))
    }

    var child: View {
        subviews[0] as! View
    }

    override var intrinsicContentSize: CGSize {
        child.intrinsicContentSize
    }
}

/// The root class for widgets who are passed their children on initialization.
///
/// If a widget is passed an arbitrary child widget on initialization (as opposed to e.g. ``WrapperWidget``,
/// which has a specific non-widget subview), it must be a view controller. If the widget is
/// a view but the child is a controller, that child will not be connected to the parent view
/// controller (as a view can't know what its controller will be during initialization). This
/// widget handles setting up the responder chain during initialization.
class ContainerWidget: BaseControllerWidget {
    let child: any WidgetProtocol

    init(child: some WidgetProtocol) {
        self.child = child
        super.init()
        add(childWidget: child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
    }
}

class WrapperControllerWidget<Controller: UIViewController>: BaseControllerWidget {
    let child: Controller

    init(child: Controller) {
        self.child = child
        super.init()
    }

    override func loadView() {
        super.loadView()

        view.addSubview(child.view)
        addChild(child)

        child.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        child.didMove(toParent: self)
    }
}
