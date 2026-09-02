import DebugFeatures
@_spi(Backends) import SwiftCrossUI
import UIKit

final class RootViewController: UIViewController {
    unowned var backend: UIKitBackend
    var resizeHandler: ((CGSize) -> Void)?
    private var childWidget: (any WidgetProtocol)?
    private let scrollHost = RootScrollHost()
    private var viewModeButton: ViewModeButton?

    #if os(visionOS)
        init(backend: UIKitBackend) {
            self.backend = backend
            super.init(nibName: nil, bundle: nil)

            registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
                (self: RootViewController, _: UITraitCollection) in
                self.backend.onTraitCollectionChange?()
            }
        }
    #else
        init(backend: UIKitBackend) {
            self.backend = backend
            super.init(nibName: nil, bundle: nil)
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)

            let previous = previousTraitCollection?.userInterfaceStyle
            if UITraitCollection.current.userInterfaceStyle != previous {
                backend.onTraitCollectionChange?()
            }
        }
    #endif

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used for the root view controller")
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        resizeHandler?(size)
        super.viewWillTransition(to: size, with: coordinator)
    }

    func setChild(to child: some WidgetProtocol) {
        childWidget?.removeFromParentWidget()
        child.removeFromParentWidget()

        let childController = child.controller
        // Hosted in a scroll view rather than added to `view` directly.
        //
        // Fourteen of the forty-six test apps are wider than a phone and were
        // clipped at both edges -- content that cannot be reached cannot be
        // tested. RootScrollHost keeps the content at its natural size and
        // scrolls to it, and carries the rwdView mode that scales it to fit
        // instead. See that file for why scaling is not reflowing.
        //
        // 放進捲動視圖中，而非直接加到 `view` 上。
        //
        // 四十六支測試 app 中有十四支比手機寬，並在左右兩側被裁切——碰不到的內容就是測不到的內容。
        // RootScrollHost 讓內容保持自然尺寸並以捲動觸及，同時帶有「改為縮放以塞入」的 rwdView 模式。
        // 為何「縮放」不等於「重新排版」，見該檔案的說明。
        if scrollHost.superview == nil {
            view.addSubview(scrollHost)
            scrollHost.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scrollHost.leadingAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.leadingAnchor
                ),
                scrollHost.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                scrollHost.widthAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.widthAnchor
                ),
                scrollHost.heightAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.heightAnchor
                ),
            ])
        }
        scrollHost.host(child.view)
        if let childController {
            addChild(childController)
            childController.didMove(toParent: self)
        }
        childWidget = child

        // Position as well as size. A view constrained only in width and height
        // has no defined origin, and Auto Layout resolving an ambiguity is not
        // the same as it being told -- measured on the simulator 2026-09-02,
        // P10's content sat centred and was clipped at both edges, which reads
        // as content too wide for the screen rather than as a missing
        // constraint.
        //
        // Pinned to the safe area rather than to the view, matching
        // `size(ofWindow:)`, which reports `safeAreaLayoutGuide.layoutFrame`.
        // Pinning the size to one guide and the origin to another would place
        // the child by the notch's height on a device that has one.
        //
        // 位置與尺寸都要。只約束寬高的 view 沒有確定的原點，而「Auto Layout 自行解掉一個歧義」與
        // 「它被明確告知」並不相同——2026-09-02 於模擬器上實測，P10 的內容置中並在左右兩側被裁切，
        // 那讀起來像是「內容對螢幕而言太寬」，而非「少了一條約束」。
        //
        // 釘在安全區域而非 view 上，與 `size(ofWindow:)` 一致——後者回報的是
        // `safeAreaLayoutGuide.layoutFrame`。若尺寸釘在一個 guide、原點釘在另一個，在有瀏海的裝置上
        // 會使子元件位移一個瀏海的高度。
        // Sized against the safe area, positioned by RootScrollHost.
        //
        // The size stays as it was: the layout system is told the window is the
        // safe area, `size(ofWindow:)` reports exactly that, and the child is
        // laid out for it. What changes is that overflowing that size is now
        // reachable rather than clipped.
        //
        // The origin is left to `layoutSubviews` rather than constrained,
        // because rwdView applies a transform and a constrained origin fights
        // the transform every pass.
        //
        // 尺寸對齊安全區域，位置則由 RootScrollHost 決定。
        //
        // 尺寸維持原樣：版面系統被告知的視窗即是安全區域，`size(ofWindow:)` 回報的正是它，子元件也
        // 依此排版。改變的是——超出該尺寸的部分現在可以觸及，而不再被裁切。
        //
        // 原點交由 `layoutSubviews` 處理而不加以約束，因為 rwdView 會套用一個 transform，而被約束的
        // 原點會在每一次版面計算中與該 transform 互相拉扯。
        child.view.translatesAutoresizingMaskIntoConstraints = true
        child.view.frame = CGRect(
            origin: .zero,
            size: view.safeAreaLayoutGuide.layoutFrame.size
        )
        child.view.autoresizingMask = []
    }

    /// Installed at layout time, not when the child is set.
    ///
    /// `setChild` runs before the view has ever laid out, so
    /// `safeAreaLayoutGuide.layoutFrame` is still zero there and the button
    /// landed at the origin instead of the top-right corner. Measured: the
    /// button was in the hierarchy and not where it was meant to be.
    ///
    /// 於版面計算時安裝，而非在設定子元件時。
    ///
    /// `setChild` 執行於該 view 首次進行版面計算之前，因此此時 `safeAreaLayoutGuide.layoutFrame`
    /// 仍為零，按鈕會落在原點而非右上角。實測結果：按鈕確實在階層中，只是不在它應在的位置。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installViewModeButtonIfDebugging()
    }

    /// Debug builds only. A release build has no floating control over its
    /// content, which is the difference between a test affordance and a
    /// feature.
    /// 僅限 debug 建置。release 建置的內容之上不會浮著任何控制項——那正是「測試用輔助」與「產品功能」
    /// 之間的分別。
    private func installViewModeButtonIfDebugging() {
        // `isCompiledIn`, not `isEnabled`.
        //
        // `isEnabled` also requires `--debug` on the command line, and an iOS
        // app is launched by `simctl launch`, so that argument has to survive
        // the harness, simctl and the app's own startup to arrive. Measured:
        // the button did not appear with `-- --debug` passed, while action-file
        // replay -- which is gated on `isCompiledIn` -- worked in the same run.
        //
        // The gate that matters is the build. A release build has no floating
        // control over its content; a debug build is a build made for looking
        // at, and having to remember a flag to see the control is friction with
        // nothing on the other side of it.
        //
        // 使用 `isCompiledIn` 而非 `isEnabled`。
        //
        // `isEnabled` 還要求命令列上有 `--debug`，而 iOS app 是由 `simctl launch` 啟動的，該引數
        // 必須一路通過 harness、simctl 與 app 自身的啟動流程才會抵達。實測：傳入 `-- --debug` 時
        // 按鈕並未出現，而同一次執行中、以 `isCompiledIn` 為條件的動作檔重放卻正常運作。
        //
        // 真正該把關的是「建置」。release 建置的內容之上不會浮著任何控制項；而 debug 建置本就是
        // 為了觀看而做的建置，若還要記得加一個旗標才看得到該控制項，那是只有摩擦、沒有收穫的設計。
        guard DebugFeatures.isCompiledIn, viewModeButton == nil else { return }
        let button = ViewModeButton.make(initial: scrollHost.mode) { [weak self] mode in
            self?.scrollHost.setMode(mode)
        }
        view.addSubview(button)
        // Top left by default, and draggable from there. It sits over the
        // content wherever it starts, so the default is a choice about which
        // corner is least likely to matter rather than one that avoids the
        // problem.
        // 預設位於左上角，並可自該處拖曳。無論從哪裡開始，它都會蓋在內容之上；因此這個預設值是
        // 「選一個最不可能造成妨礙的角落」，而不是一個能迴避該問題的位置。
        button.frame.origin = CGPoint(
            x: view.safeAreaLayoutGuide.layoutFrame.minX + 8,
            y: view.safeAreaLayoutGuide.layoutFrame.minY + 8
        )
        viewModeButton = button
    }
}

extension UIKitBackend: BackendFeatures.WindowBehaviors {
    public typealias Window = UIWindow

    public func createWindow(withDefaultSize _: SIMD2<Int>?, id: String) -> Window {
        let window: UIWindow

        if !Self.hasReturnedAWindow {
            if let mainWindow = Self.mainWindow {
                window = mainWindow
            } else {
                window = UIWindow()
                Self.mainWindow = window
            }
            Self.hasReturnedAWindow = true
        } else {
            window = UIWindow()
        }

        #if !os(tvOS)
            window.backgroundColor = .systemBackground
        #endif

        window.rootViewController = RootViewController(backend: self)
        return window
    }

    public func updateWindow(_ window: Window, environment: EnvironmentValues) {
        // TODO(stackotter): Support preferredColorScheme
        window.backgroundColor = switch environment.colorScheme {
            case .light: .white
            case .dark: .black
        }
    }

    public func setTitle(ofWindow window: Window, to title: String) {
        // I don't think this achieves much of anything but might as well
        window.rootViewController!.title = title
    }

    public func setChild(ofWindow window: Window, to child: Widget) {
        let viewController = window.rootViewController as! RootViewController
        viewController.setChild(to: child)
    }

    public func size(ofWindow window: Window) -> SIMD2<Int> {
        // For now, Views have no way to know where the safe area insets are, and the edges
        // of the screen could be obscured (e.g. covered by the notch). In the future we
        // might want to let users decide what to do, but for now, lie and say that the safe
        // area insets aren't even part of the window.
        // If/when this is updated, ``RootViewController`` and ``WidgetProtocolHelpers`` will
        // also need to be updated.
        let size = window.safeAreaLayoutGuide.layoutFrame.size
        return SIMD2(Int(size.width), Int(size.height))
    }

    public func setResizeHandler(
        ofWindow window: Window,
        to action: @escaping (_ newSize: SIMD2<Int>) -> Void
    ) {
        let viewController = window.rootViewController as! RootViewController
        viewController.resizeHandler = { size in
            action(SIMD2(Int(size.width), Int(size.height)))
        }
    }

    public func show(window: Window) {
        window.makeKeyAndVisible()
    }

    public func activate(window: Window) {
        window.makeKeyAndVisible()
    }

    public func isWindowProgrammaticallyResizable(_ window: Window) -> Bool {
        #if os(visionOS)
            true
        #else
            false
        #endif
    }

    public func setBehaviors(
        ofWindow window: Window,
        closable: Bool,
        minimizable: Bool,
        resizable: Bool
    ) {
        if #available(iOS 16, tvOS 16, macCatalyst 16, *) {
            window.windowScene?.windowingBehaviors?.isClosable = closable
            window.windowScene?.windowingBehaviors?.isMiniaturizable = minimizable
        }

        logger.notice("ignoring resizability change")
    }

    public func setSize(ofWindow window: Window, to newSize: SIMD2<Int>) {
        #if os(visionOS)
            window.bounds.size = CGSize(width: CGFloat(newSize.x), height: CGFloat(newSize.y))
        #else
            logger.notice(
                "ignoring \(#function) call",
                metadata: [
                    "currentWindowSize": "\(window.bounds.width) x \(window.bounds.height)",
                    "proposedWindowSize": "\(newSize.x) x \(newSize.y)",
                ]
            )
        #endif
    }

    public func setSizeLimits(
        ofWindow window: Window,
        minimum minimumSize: SIMD2<Int>,
        maximum maximumSize: SIMD2<Int>?
    ) {
        // if windowScene is nil, either the window isn't shown or it must be fullscreen
        // if sizeRestrictions is nil, the device doesn't support setting window size bounds
        window.windowScene?.sizeRestrictions?.minimumSize =
            CGSize(width: minimumSize.x, height: minimumSize.y)
        window.windowScene?.sizeRestrictions?.maximumSize =
            if let maximumSize {
                CGSize(width: maximumSize.x, height: maximumSize.y)
            } else {
                CGSize(width: Double.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            }
    }
}
