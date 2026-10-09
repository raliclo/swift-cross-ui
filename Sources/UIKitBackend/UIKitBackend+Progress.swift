@_spi(Backends) import SwiftCrossUI
import UIKit

final class ProgressSpinner: WrapperWidget<UIActivityIndicatorView> {
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        child.startAnimating()
    }
}

/// A UIProgressView that also draws the indeterminate state.
///
/// UIProgressView has no indeterminate mode, and `updateProgressBar` used to
/// return early without a value, so an indeterminate bar drew nothing at all:
/// P29's "indeterminate bar" was an empty strip under its label (2026-10-10).
/// Without a value it now shows a segment in the tint, a third of the width,
/// sliding back and forth along the bar at the bar's own thickness --
/// AndroidBackend draws the same (user, 2026-10-10).
///
/// 也畫出不確定狀態的 UIProgressView。UIProgressView 沒有不確定模式，而 `updateProgressBar` 原本在沒有數值時
/// 直接返回，所以不確定的進度條什麼都沒畫:P29 的 "indeterminate bar" 在標籤底下是一片空白(2026-10-10)。
/// 現在沒有數值時，會顯示一段 tint 色、寬度三分之一、與進度條同粗的色段，沿著進度條來回滑動——
/// AndroidBackend 畫的是同一個(使用者,2026-10-10)。
final class ProgressBarWidget: WrapperWidget<UIProgressView> {
    private let segment = CALayer()

    var isIndeterminate = false {
        didSet {
            guard isIndeterminate != oldValue else { return }
            if isIndeterminate { child.setProgress(0, animated: false) }
            setNeedsLayout()
        }
    }

    override init(child: UIProgressView) {
        super.init(child: child)
        segment.isHidden = true
        child.layer.addSublayer(segment)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        segment.removeAnimation(forKey: "slide")
        segment.isHidden = !isIndeterminate
        guard isIndeterminate, child.bounds.width > 0 else { return }
        let width = child.bounds.width / 3
        segment.backgroundColor = child.tintColor.cgColor
        segment.bounds = CGRect(x: 0, y: 0, width: width, height: child.bounds.height)
        segment.position = CGPoint(x: width / 2, y: child.bounds.midY)
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = width / 2
        slide.toValue = child.bounds.width - width / 2
        slide.duration = 1.2
        slide.autoreverses = true
        slide.repeatCount = .infinity
        slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        segment.add(slide, forKey: "slide")
    }
}

extension UIKitBackend {
    public func createProgressSpinner() -> Widget {
        ProgressSpinner()
    }

    public func createProgressBar() -> Widget {
        let style: UIProgressView.Style
        #if os(tvOS)
            style = .default
        #else
            style = .bar
        #endif
        return ProgressBarWidget(child: UIProgressView(progressViewStyle: style))
    }

    public func updateProgressBar(
        _ widget: Widget,
        progressFraction: Double?,
        environment: EnvironmentValues
    ) {
        let wrapper = widget as! ProgressBarWidget
        wrapper.isIndeterminate = progressFraction == nil
        guard let progressFraction else { return }

        wrapper.child.setProgress(Float(progressFraction), animated: true)
    }
}
