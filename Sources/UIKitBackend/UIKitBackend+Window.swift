import DebugFeatures
@_spi(Backends) import SwiftCrossUI
import UIKit

final class RootViewController: UIViewController {
    unowned var backend: UIKitBackend
    var resizeHandler: ((CGSize) -> Void)?
    private var childWidget: (any WidgetProtocol)?
    private let scrollHost = RootScrollHost()
    private var viewModeButton: ViewModeButton?

    /// The toolbar's bar, and the targets its buttons point at.
    ///
    /// `UIBarButtonItem.target` is unowned, so a button whose target has been
    /// deallocated does nothing when pressed and says nothing about it. Held
    /// here, beside the bar they belong to.
    ///
    /// 工具列的那條 bar,以及其按鈕所指向的 target。
    ///
    /// `UIBarButtonItem.target` 是 unowned 的,因此一個 target 已被釋放的按鈕,按下去不會有任何作用,
    /// 也不會為此說任何話。與它們所屬的那條 bar 一起持有於此。
    var navigationBar: UINavigationBar?
    var toolbarTargets: [ToolbarActionTarget] = []

    /// The two constraints the toolbar moves, so the bar does not sit on top of
    /// the content. Held because a constraint that has been activated can only
    /// be found again by searching `view.constraints` by anchor, and a search
    /// that matches nothing silently adjusts nothing.
    ///
    /// 工具列會調整的那兩個 constraint,好讓那條列不要壓在內容上。之所以持有它們,是因為一個已啟用的
    /// constraint 只能靠在 `view.constraints` 中依 anchor 搜尋才找得回來,而一次沒有命中的搜尋會
    /// 靜默地什麼都不調整。
    var scrollHostTopConstraint: NSLayoutConstraint?
    var scrollHostHeightConstraint: NSLayoutConstraint?

    /// Moves the content down by `inset` and shortens it by the same amount.
    /// 把內容往下移 `inset`,並等量縮短它。
    func setContentTopInset(_ inset: CGFloat) {
        scrollHostTopConstraint?.constant = inset
        scrollHostHeightConstraint?.constant = -inset
        view.setNeedsLayout()
    }

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
            let scrollHostTop = scrollHost.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            )
            scrollHostTopConstraint = scrollHostTop
            // The height gives back what the top constraint takes. Pinning only
            // the top would push an equal-height view down by the bar and off
            // the bottom of the screen, and a scroll view whose content runs
            // past its own frame scrolls -- so the loss shows up as a stripe
            // that will not stay put rather than as anything obviously wrong.
            //
            // 高度要把 top constraint 拿走的還回來。若只釘住頂端,一個等高的 view 會被工具列往下推、
            // 推出畫面底端;而一個內容超出自身框架的捲動視圖是會捲的——於是這份損失呈現出來的樣子,
            // 是一條「按不住、會滑動」的邊條,而不是任何一眼看得出的錯誤。
            let scrollHostHeight = scrollHost.heightAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.heightAnchor
            )
            scrollHostHeightConstraint = scrollHostHeight
            NSLayoutConstraint.activate([
                scrollHost.leadingAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.leadingAnchor
                ),
                scrollHostTop,
                scrollHost.widthAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.widthAnchor
                ),
                scrollHostHeight,
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

    /// Shown by default in a debug build, and in a release build only when
    /// `-allow-rootscroll` is passed. A shipped application does not float a
    /// control over its own content, which is the difference between a test
    /// affordance and a feature; the flag exists because a release build is
    /// where rebuilding to see it is not an option.
    /// 在 debug 建置中預設顯示；在 release 建置中，僅當傳入 `-allow-rootscroll` 時才顯示。
    /// 已出貨的應用程式不會在自己的內容之上浮著一個控制項——那正是「測試用輔助」與「產品功能」
    /// 之間的分別；而該旗標之所以存在，是因為 release 建置正是「重新建置以看見它」這條路走不通的
    /// 那種建置。
    private func installViewModeButtonIfDebugging() {
        // `allowsRootScrollControl`, not `isEnabled`.
        //
        // `isEnabled` also requires `--debug` on the command line, and an iOS
        // app is launched by `simctl launch`, so that argument has to survive
        // the harness, simctl and the app's own startup to arrive. Measured:
        // the button did not appear with `-- --debug` passed, while action-file
        // replay -- which is gated on `isCompiledIn` -- worked in the same run.
        //
        // The default follows the build: a debug build is a build made for
        // looking at, and having to remember a flag to see the control is
        // friction with nothing on the other side of it; a release build has no
        // floating control over its content. But the release default is the one
        // that needs an override, because a release build is exactly where you
        // cannot rebuild to see the control -- hence `-allow-rootscroll`, which
        // ``DebugFeatures/allowsRootScrollControl`` reads in every build.
        //
        // 使用 `allowsRootScrollControl` 而非 `isEnabled`。
        //
        // `isEnabled` 還要求命令列上有 `--debug`，而 iOS app 是由 `simctl launch` 啟動的，該引數
        // 必須一路通過 harness、simctl 與 app 自身的啟動流程才會抵達。實測：傳入 `-- --debug` 時
        // 按鈕並未出現，而同一次執行中、以 `isCompiledIn` 為條件的動作檔重放卻正常運作。
        //
        // 預設值隨建置而定：debug 建置本就是為了觀看而做的建置，若還要記得加一個旗標才看得到該控制項，
        // 那是只有摩擦、沒有收穫的設計；而 release 建置的內容之上不會浮著任何控制項。但需要覆寫手段
        // 的正是 release 這個預設值，因為 release 建置恰恰是你無法靠重新建置來看見該控制項的那種
        // 建置——因此有了 `-allow-rootscroll`，由
        // ``DebugFeatures/allowsRootScrollControl`` 在所有建置中讀取。
        guard DebugFeatures.allowsRootScrollControl, viewModeButton == nil else { return }
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

    /// Shows a window, asking for a scene of its own when it has none.
    ///
    /// A window after the first is created without a scene, and a sceneless
    /// `UIWindow` is never drawn. Where the app can have several scenes (iPad,
    /// Mac Catalyst, visionOS) a new scene session is requested and
    /// `SceneDelegate` hands it this window when it connects -- a real,
    /// separately managed window, as a second window is on the desktop. Where
    /// it cannot (iPhone), the window joins the main window's scene and is
    /// shown over it.
    ///
    /// 顯示一個視窗,在它沒有 scene 時為它要求一個。第一個之後的視窗建立時沒有 scene,而沒有 scene 的
    /// `UIWindow` 永遠不會被畫出來。在 app 可以擁有多個 scene 之處(iPad、Mac Catalyst、visionOS),
    /// 會要求一個新的 scene session,並由 `SceneDelegate` 在它連上時把這個視窗交給它——一個真正、獨立
    /// 管理的視窗,就如桌面上的第二個視窗。做不到之處(iPhone),該視窗加入主視窗的 scene,顯示在它之上。
    public func show(window: Window) {
        if window.windowScene == nil, window !== Self.mainWindow {
            if UIApplication.shared.supportsMultipleScenes {
                if !Self.pendingSceneWindows.contains(where: { $0 === window }) {
                    Self.pendingSceneWindows.append(window)
                    UIApplication.shared.requestSceneSessionActivation(
                        nil,
                        userActivity: nil,
                        options: nil
                    ) { error in
                        logger.error(
                            "could not open a scene for a new window",
                            metadata: ["error": "\(error)"]
                        )
                    }
                }
                return
            }
            window.windowScene = Self.mainWindow?.windowScene
        }
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

        // Applied, no longer "ignoring resizability change". A window that must
        // not be resized has its scene's size restrictions pinned to its current
        // size -- the way UIKit expresses it on iPadOS, where windows are resized
        // in Stage Manager, and on Mac Catalyst. On iPhone there are no
        // restrictions to set (`sizeRestrictions` is nil) and nothing a user can
        // resize, so this changes nothing there.
        // 真的套用,不再「忽略可調整大小的改變」。不可調整大小的視窗,其 scene 的尺寸限制會被釘在目前的尺寸——這正是
        // UIKit 在 iPadOS(Stage Manager 中可調整視窗大小)與 Mac Catalyst 上表達它的方式。iPhone 上沒有限制可設
        // (`sizeRestrictions` 為 nil),也沒有使用者能調整的東西,所以這在那裡不改變任何事。
        WindowSizePolicy.of(window).resizable = resizable
        WindowSizePolicy.of(window).apply(to: window)
    }

    public func setSize(ofWindow window: Window, to newSize: SIMD2<Int>) {
        #if os(visionOS)
            window.bounds.size = CGSize(width: CGFloat(newSize.x), height: CGFloat(newSize.y))
        #else
            #if targetEnvironment(macCatalyst)
                // Mac Catalyst: a geometry request with the new frame.
                // Mac Catalyst:以新的框架發出幾何請求。
                if #available(macCatalyst 16, *), let scene = window.windowScene {
                    let frame = CGRect(
                        origin: window.frame.origin,
                        size: CGSize(width: CGFloat(newSize.x), height: CGFloat(newSize.y))
                    )
                    scene.requestGeometryUpdate(.Mac(systemFrame: frame)) { error in
                        logger.notice(
                            "window size request declined",
                            metadata: ["reason": "\(error.localizedDescription)"]
                        )
                    }
                }
            #else
                // iOS and iPadOS have no programmatic window size, and that was
                // checked, not assumed (2026-09-29): in the iOS 27 SDK
                // `UIWindowSceneGeometryPreferencesIOS` has exactly one property,
                // `interfaceOrientations`, and its only initialisers are `init` and
                // `initWithInterfaceOrientations:`; the frame-taking preferences are
                // the Mac and visionOS ones. A window's size there belongs to the
                // user (Stage Manager) or the device -- which is why
                // `isWindowProgrammaticallyResizable` is false on iOS and the
                // framework does not ask for this.
                //
                // `sizeRestrictions` was tried as the way round it on 2026-10-02
                // (iPad Pro 11-inch Simulator, iOS 27, Windowed Apps on):
                // pinning minimumSize and maximumSize to 480 x 380 left the
                // window at 834 x 1210 a second later, and three runs out of
                // four the Simulator's render server (backboardd) aborted in
                // Metal texture validation and took the XCUITest session with
                // it. A window is sized on iPad by its resize grip, which is how
                // the iPad action files do it.
                // 2026-10-02 曾以 `sizeRestrictions` 作為替代途徑(iPad Pro 11-inch 模擬器、iOS 27、Windowed
                // Apps 開啟):把 minimumSize 與 maximumSize 釘在 480 x 380,一秒後視窗仍是 834 x 1210;四次中
                // 有三次模擬器的渲染伺服器(backboardd)在 Metal 貼圖驗證中中止，並連帶結束 XCUITest 工作階段。
                // iPad 上視窗的大小由它的縮放把手決定，iPad 動作檔就是那樣做的。
                // iOS 與 iPadOS 沒有以程式設定視窗大小的方法,而且這是查證過的,不是假設(2026-09-29):iOS 27 SDK
                // 的 `UIWindowSceneGeometryPreferencesIOS` 只有一個屬性 `interfaceOrientations`,初始化方法也只有
                // `init` 與 `initWithInterfaceOrientations:`;能帶框架的是 Mac 與 visionOS 那兩個。那裡的視窗大小屬於
                // 使用者(Stage Manager)或裝置——所以 iOS 上 `isWindowProgrammaticallyResizable` 為 false。
                logger.notice(
                    "\(#function): iOS has no programmatic window size",
                    metadata: [
                        "currentWindowSize": "\(window.bounds.width) x \(window.bounds.height)",
                        "proposedWindowSize": "\(newSize.x) x \(newSize.y)",
                    ]
                )
            #endif
        #endif
    }

    public func setSizeLimits(
        ofWindow window: Window,
        minimum minimumSize: SIMD2<Int>,
        maximum maximumSize: SIMD2<Int>?
    ) {
        // Stored and applied together with resizability, so a later limit does
        // not undo "not resizable". 與可調整大小一起存下並套用,讓之後的限制不會把「不可調整」蓋掉。
        let policy = WindowSizePolicy.of(window)
        policy.minimum = CGSize(width: minimumSize.x, height: minimumSize.y)
        policy.maximum = maximumSize.map { CGSize(width: $0.x, height: $0.y) }
        policy.apply(to: window)
    }
}

/// A window's resizability and size limits, kept together because both become
/// the scene's `sizeRestrictions`.
///
/// If windowScene is nil, either the window isn't shown or it must be
/// fullscreen; if sizeRestrictions is nil, the device doesn't support setting
/// window size bounds (iPhone).
///
/// 視窗的可調整大小與尺寸限制,放在一起是因為兩者都會變成 scene 的 `sizeRestrictions`。
final class WindowSizePolicy {
    var resizable = true
    var minimum = CGSize.zero
    var maximum: CGSize?

    nonisolated(unsafe) private static var key: UInt8 = 0

    @MainActor
    static func of(_ window: UIWindow) -> WindowSizePolicy {
        if let existing = objc_getAssociatedObject(window, &key) as? WindowSizePolicy {
            return existing
        }
        let policy = WindowSizePolicy()
        objc_setAssociatedObject(window, &key, policy, .OBJC_ASSOCIATION_RETAIN)
        return policy
    }

    @MainActor
    func apply(to window: UIWindow) {
        guard let restrictions = window.windowScene?.sizeRestrictions else { return }
        if resizable {
            restrictions.minimumSize = minimum
            restrictions.maximumSize =
                maximum
                    ?? CGSize(
                        width: Double.greatestFiniteMagnitude,
                        height: .greatestFiniteMagnitude
                    )
        } else {
            // Pinned: minimum and maximum both the size the window has now.
            // 釘住:最小與最大都是視窗現在的尺寸。
            let size = window.bounds.size
            restrictions.minimumSize = size
            restrictions.maximumSize = size
        }
    }
}
