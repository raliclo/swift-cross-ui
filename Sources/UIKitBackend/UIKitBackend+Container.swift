@_spi(Backends) import SwiftCrossUI
import UIKit

final class ScrollWidget: ContainerWidget {
    var scrollView = UIScrollView()
    private var childWidthConstraint: NSLayoutConstraint?
    private var childHeightConstraint: NSLayoutConstraint?

    private lazy var contentLayoutGuideConstraints: [NSLayoutConstraint] = [
        scrollView.contentLayoutGuide.leadingAnchor.constraint(equalTo: child.view.leadingAnchor),
        scrollView.contentLayoutGuide.trailingAnchor.constraint(equalTo: child.view.trailingAnchor),
        scrollView.contentLayoutGuide.topAnchor.constraint(equalTo: child.view.topAnchor),
        scrollView.contentLayoutGuide.bottomAnchor.constraint(equalTo: child.view.bottomAnchor),
    ]

    override func loadView() {
        view = scrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    override func updateViewConstraints() {
        NSLayoutConstraint.activate(contentLayoutGuideConstraints)
        super.updateViewConstraints()
    }

    func setScrollBars(
        hasVerticalScrollBar: Bool,
        hasHorizontalScrollBar: Bool
    ) {
        switch (hasVerticalScrollBar, childHeightConstraint?.isActive) {
            case (true, true):
                childHeightConstraint!.isActive = false
            case (false, nil):
                childHeightConstraint = child.view.heightAnchor.constraint(
                    equalTo: scrollView.heightAnchor
                )
                fallthrough
            case (false, false):
                childHeightConstraint!.isActive = true
            default:
                break
        }

        switch (hasHorizontalScrollBar, childWidthConstraint?.isActive) {
            case (true, true):
                childWidthConstraint!.isActive = false
            case (false, nil):
                childWidthConstraint = child.view.widthAnchor.constraint(
                    equalTo: scrollView.widthAnchor
                )
                fallthrough
            case (false, false):
                childWidthConstraint!.isActive = true
            default:
                break
        }

        scrollView.showsVerticalScrollIndicator = hasVerticalScrollBar
        scrollView.showsHorizontalScrollIndicator = hasHorizontalScrollBar
    }

    public func updateScrollContainer(environment: EnvironmentValues) {
        #if os(iOS)
            scrollView.keyboardDismissMode =
                switch environment.scrollDismissesKeyboardMode {
                    case .automatic:
                        .interactive
                    case .immediately:
                        .onDrag
                    case .interactively:
                        .interactive
                    case .never:
                        .none
                }
        #endif
    }
}

#if os(visionOS)
    // UIToolTipInteractionDelegate isn't available on visionOS for some reason.
    // Thankfully, UIToolTipInteraction is available since visionOS 1.0, so it can
    // be a stored property.
    final class TooltipWidget: ContainerWidget {
        private let interaction = UIToolTipInteraction()

        var text = "" {
            didSet {
                child.accessibilityHint = text
                interaction.defaultToolTip = text
            }
        }

        override init(child: some WidgetProtocol) {
            super.init(child: child)
            child.view.addInteraction(interaction)
        }
    }
#elseif os(tvOS)
    // tvOS gives linker errors for even attempting to reference
    // UIToolTipInteraction or UIToolTipInteractionDelegate, regardless of the
    // #available/@available guards.
    final class TooltipWidget: ContainerWidget {
        var text = "" {
            didSet {
                child.accessibilityHint = text
            }
        }
    }
#else
    // Because stored properties cannot be conditionally available, there's no good
    // way to update interaction.defaultToolTip after initialization, so this has to
    // implement UIToolTipInteractionDelegate instead.
    final class TooltipWidget: ContainerWidget {
        var text = "" {
            didSet {
                child.accessibilityHint = text
            }
        }

        override init(child: some WidgetProtocol) {
            super.init(child: child)

            if #available(iOS 15, macCatalyst 15, *) {
                let interaction = UIToolTipInteraction()
                child.view.addInteraction(interaction)
                interaction.delegate = self
            }
        }
    }

    @available(iOS 15, macCatalyst 15, *)
    extension TooltipWidget: UIToolTipInteractionDelegate {
        func toolTipInteraction(
            _ interaction: UIToolTipInteraction,
            configurationAt point: CGPoint
        ) -> UIToolTipConfiguration? {
            let rect = view.bounds
            if rect.contains(point) {
                return UIToolTipConfiguration(toolTip: text, in: rect)
            }
            return nil
        }
    }
#endif

extension UIKitBackend {
    public func createContainer() -> Widget {
        BaseViewWidget()
    }

    public func removeAllChildren(of container: Widget) {
        container.childWidgets.forEach { $0.removeFromParentWidget() }
    }

    public func insert(_ child: Widget, into container: Widget, at index: Int) {
        (container as! BaseViewWidget).insert(child, at: index)
    }

    public func swap(childAt firstIndex: Int, withChildAt secondIndex: Int, in container: Widget) {
        container.view.exchangeSubview(at: firstIndex, withSubviewAt: secondIndex)
        container.childWidgets.swapAt(firstIndex, secondIndex)
    }

    public func setPosition(
        ofChildAt index: Int,
        in container: Widget,
        to position: SIMD2<Int>
    ) {
        guard index < container.childWidgets.count else {
            assertionFailure("Attempting to set position of nonexistent subview")
            return
        }

        let child = container.childWidgets[index]
        child.x = position.x
        child.y = position.y
    }

    public func remove(childAt index: Int, from container: Widget) {
        container.childWidgets[index].removeFromParentWidget()
    }

    public func createColorableRectangle() -> Widget {
        ColorableRectangleWidget()
    }

    public func setColor(ofColorableRectangle widget: Widget, to color: Color.Resolved) {
        widget.view.backgroundColor = color.uiColor
    }

    public func createCornerRadiusContainer(wrapping child: Widget) -> Widget {
        child
    }

    public func setCornerRadius(of widget: Widget, to radius: Int) {
        widget.view.layer.cornerRadius = CGFloat(radius)
        widget.view.layer.masksToBounds = true
    }

    public func naturalSize(of widget: Widget) -> SIMD2<Int> {
        let size = widget.view.intrinsicContentSize
        return SIMD2(
            Int(size.width.rounded(.awayFromZero)),
            Int(size.height.rounded(.awayFromZero))
        )
    }

    public func setSize(of widget: Widget, to size: SIMD2<Int>) {
        widget.width = size.x
        widget.height = size.y
    }

    public func createScrollContainer(for child: Widget) -> Widget {
        ScrollWidget(child: child)
    }

    public func updateScrollContainer(
        _ scrollView: Widget,
        environment: EnvironmentValues,
        bounceHorizontally: Bool,
        bounceVertically: Bool,
        hasHorizontalScrollBar: Bool,
        hasVerticalScrollBar: Bool
    ) {
        let scrollViewWidget = scrollView as! ScrollWidget
        scrollViewWidget.updateScrollContainer(environment: environment)
        scrollViewWidget.setScrollBars(
            hasVerticalScrollBar: hasVerticalScrollBar,
            hasHorizontalScrollBar: hasHorizontalScrollBar
        )
    }

    public func createTooltipContainer(wrapping child: Widget) -> Widget {
        TooltipWidget(child: child)
    }

    public func updateTooltipContainer(_ widget: Widget, tooltip: String) {
        let widget = widget as! TooltipWidget
        widget.text = tooltip
    }
}

/// A colour rectangle that a fully transparent colour does not make clickable.
///
/// #454: "the ZStack's upper layer is a transparent colour. It covers the
/// button but should not take its clicks." A plain `UIView` takes them --
/// `hitTest` returns any view whose bounds contain the point, whatever its
/// background alpha -- so `Color.clear` over a button swallowed every tap.
///
/// Measured on the iOS Simulator 2026-09-02 against P10: "Covered clicks"
/// stayed at 0 while the overlay was present, and rose as soon as the app's
/// own toggle removed it. AppKit, measured the same day, reports Direct 2,
/// Covered 2, Hidden 2 -- all three land, which is the behaviour to match.
///
/// This is also SwiftUI's rule, and the reason `.contentShape` exists: a clear
/// colour is not hit-testable, so making one tappable is something you ask for
/// rather than something you get.
///
/// The test is the background's alpha, not the view's. A rectangle inside a
/// faded parent is still a rectangle someone can see and aim at; only a colour
/// that is itself transparent is one they cannot.
///
/// 一個「完全透明的顏色不會使其可被點擊」的顏色矩形。
///
/// #454：「ZStack 的上層是透明顏色。它覆蓋著按鈕，但不應取走它的點擊。」而純粹的 `UIView` 會取走
/// ——`hitTest` 會回傳任何 bounds 包含該點的 view，無論其背景 alpha 為何——因此覆蓋在按鈕上的
/// `Color.clear` 吞掉了每一次點擊。
///
/// 2026-09-02 於 iOS 模擬器上針對 P10 實測：overlay 存在期間「Covered clicks」始終為 0，而在 app
/// 自己的開關把它移除後隨即上升。同日量測的 AppKit 回報 Direct 2、Covered 2、Hidden 2——三者皆命中，
/// 那才是應該對齊的行為。
///
/// 這同時也是 SwiftUI 的規則，以及 `.contentShape` 存在的理由：透明顏色不參與 hit test，因此要讓它
/// 可點擊是你主動要求的，而非預設就有的。
///
/// 判斷依據是背景的 alpha，而非 view 的 alpha。位於已淡出父層之中的矩形，仍然是一個看得見、瞄得準
/// 的矩形；唯有顏色本身透明時，才是看不見的。
final class ColorableRectangleWidget: BaseViewWidget {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        var alpha: CGFloat = 0
        if backgroundColor?.getRed(nil, green: nil, blue: nil, alpha: &alpha) != true {
            backgroundColor?.getWhite(nil, alpha: &alpha)
        }
        guard alpha > 0 else { return nil }
        return super.hitTest(point, with: event)
    }
}
