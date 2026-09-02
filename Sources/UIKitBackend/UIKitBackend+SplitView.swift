import UIKit

#if os(iOS) || targetEnvironment(macCatalyst)
    final class SplitWidget: WrapperControllerWidget<UISplitViewController>,
        UISplitViewControllerDelegate
    {
        private final class ColumnView: UIView {
            unowned var splitWidget: SplitWidget!

            @available(*, unavailable)
            required init?(coder: NSCoder) {
                fatalError("init(coder:) is not used for this view")
            }

            init() {
                super.init(frame: .zero)
            }

            override func layoutSubviews() {
                super.layoutSubviews()
                if !splitWidget.hasCalledResizeHandler {
                    splitWidget.resizeHandler?()
                    splitWidget.hasCalledResizeHandler = true
                }
            }
        }

        private final class ColumnWidget: ContainerWidget {
            let columnView = ColumnView()

            override func loadView() {
                view = columnView
            }
        }

        var resizeHandler: (() -> Void)? {
            didSet {
                hasCalledResizeHandler = false
            }
        }

        // This is just a flag so that we don't call resizeHandler twice in one pass through the run loop.
        var hasCalledResizeHandler = false {
            willSet {
                if newValue {
                    DispatchQueue.main.async { [weak self] in
                        self?.hasCalledResizeHandler = false
                    }
                }
            }
        }

        private let sidebarContainer: ColumnWidget
        private let mainContainer: ColumnWidget

        init(sidebarWidget: some WidgetProtocol, mainWidget: some WidgetProtocol) {
            // UISplitViewController requires its children to be controllers, not views
            sidebarContainer = ColumnWidget(child: sidebarWidget)
            mainContainer = ColumnWidget(child: mainWidget)

            super.init(child: UISplitViewController())

            sidebarContainer.parentWidget = self
            mainContainer.parentWidget = self
            childWidgets = [sidebarContainer, mainContainer]
            sidebarContainer.columnView.splitWidget = self
            mainContainer.columnView.splitWidget = self

            child.delegate = self

            child.preferredDisplayMode = .oneBesideSecondary
            child.preferredPrimaryColumnWidthFraction = 0.3

            child.viewControllers = [sidebarContainer, mainContainer]
        }

        override func viewDidLoad() {
            NSLayoutConstraint.activate([
                sidebarContainer.view.leadingAnchor.constraint(
                    equalTo: sidebarContainer.child.view.leadingAnchor
                ),
                sidebarContainer.view.trailingAnchor.constraint(
                    equalTo: sidebarContainer.child.view.trailingAnchor
                ),
                sidebarContainer.view.topAnchor.constraint(
                    equalTo: sidebarContainer.child.view.topAnchor
                ),
                sidebarContainer.view.bottomAnchor.constraint(
                    equalTo: sidebarContainer.child.view.bottomAnchor
                ),
                mainContainer.view.leadingAnchor.constraint(
                    equalTo: mainContainer.child.view.leadingAnchor
                ),
                mainContainer.view.trailingAnchor.constraint(
                    equalTo: mainContainer.child.view.trailingAnchor
                ),
                mainContainer.view.topAnchor.constraint(
                    equalTo: mainContainer.child.view.topAnchor
                ),
                mainContainer.view.bottomAnchor.constraint(
                    equalTo: mainContainer.child.view.bottomAnchor
                ),
            ])

            super.viewDidLoad()
        }
    }

    extension UIKitBackend {
        /// `UISplitViewController` where it can show two columns, and
        /// ``PhoneSplitWidget`` where it cannot.
        ///
        /// This was a `precondition` that the idiom is not `.phone`, with the
        /// message "NavigationSplitView is currently unsupported on iPhone and
        /// iPod touch." Measured on the simulator 2026-09-02: P13 died within a
        /// second of launch on every run, before drawing anything, and the
        /// crash carried no app-level log line -- the trap fires inside
        /// `createSplitView`, so nothing the app itself prints ever runs.
        ///
        /// A compact-width `UISplitViewController` collapses to a navigation
        /// stack no matter what `preferredDisplayMode` asks for, so making it
        /// show two columns on a phone is not available. Laying the two panes
        /// out side by side is, and that is what the layout system already
        /// expects: it asks for ``sidebarWidth(ofSplitView:)`` and gives the
        /// trailing pane the rest.
        ///
        /// 能顯示兩欄的地方使用 `UISplitViewController`，不能的地方使用 ``PhoneSplitWidget``。
        ///
        /// 此處原本是一個「idiom 不是 `.phone`」的 `precondition`，訊息為「NavigationSplitView is
        /// currently unsupported on iPhone and iPod touch.」。2026-09-02 於模擬器上實測：P13 每一次
        /// 都在啟動一秒內死亡、什麼都還沒畫出來，而該次崩潰沒有任何 app 層級的 log——trap 發生在
        /// `createSplitView` 之內，因此 app 自己要印的東西根本沒機會執行。
        ///
        /// 緊湊寬度下的 `UISplitViewController` 無論 `preferredDisplayMode` 要求什麼都會收合成一個
        /// navigation stack，所以「讓它在手機上顯示兩欄」這條路並不存在。「把兩個窗格並排放置」則存在，
        /// 而那正是版面系統原本就預期的做法：它詢問 ``sidebarWidth(ofSplitView:)``，並把其餘寬度交給
        /// trailing 窗格。
        public func createSplitView(
            leadingChild: any WidgetProtocol,
            trailingChild: any WidgetProtocol
        ) -> any WidgetProtocol {
            if UIDevice.current.userInterfaceIdiom == .phone {
                return PhoneSplitWidget(
                    sidebarWidget: leadingChild,
                    mainWidget: trailingChild
                )
            }

            return SplitWidget(sidebarWidget: leadingChild, mainWidget: trailingChild)
        }

        public func setResizeHandler(
            ofSplitView splitView: Widget,
            to action: @escaping () -> Void
        ) {
            if let phone = splitView as? PhoneSplitWidget {
                phone.resizeHandler = action
                return
            }
            let splitWidget = splitView as! SplitWidget
            splitWidget.resizeHandler = action
        }

        public func sidebarWidth(ofSplitView splitView: Widget) -> Int {
            if let phone = splitView as? PhoneSplitWidget {
                return phone.resolvedSidebarWidth
            }
            let splitWidget = splitView as! SplitWidget
            return Int(splitWidget.child.primaryColumnWidth.rounded(.toNearestOrEven))
        }

        public func setSidebarWidthBounds(
            ofSplitView splitView: Widget,
            minimum minimumWidth: Int,
            maximum maximumWidth: Int
        ) {
            if let phone = splitView as? PhoneSplitWidget {
                phone.setSidebarWidthBounds(minimum: minimumWidth, maximum: maximumWidth)
                return
            }
            let splitWidget = splitView as! SplitWidget
            splitWidget.child.minimumPrimaryColumnWidth = CGFloat(minimumWidth)
            splitWidget.child.maximumPrimaryColumnWidth = CGFloat(maximumWidth)
        }
    }
#else
    extension UIKitBackend {
        public func createSplitView(
            leadingChild: Widget,
            trailingChild: Widget
        ) -> Widget {
            PhoneSplitWidget(sidebarWidget: leadingChild, mainWidget: trailingChild)
        }

        public func setResizeHandler(
            ofSplitView splitView: Widget,
            to action: @escaping () -> Void
        ) {
            (splitView as! PhoneSplitWidget).resizeHandler = action
        }

        public func sidebarWidth(ofSplitView splitView: Widget) -> Int {
            (splitView as! PhoneSplitWidget).resolvedSidebarWidth
        }

        public func setSidebarWidthBounds(
            ofSplitView splitView: Widget,
            minimum minimumWidth: Int,
            maximum maximumWidth: Int
        ) {
            (splitView as! PhoneSplitWidget).setSidebarWidthBounds(
                minimum: minimumWidth,
                maximum: maximumWidth
            )
        }
    }
#endif
