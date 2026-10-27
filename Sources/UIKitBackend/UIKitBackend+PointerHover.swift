@_spi(Backends) import SwiftCrossUI
import UIKit

#if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
    extension UIKitBackend: BackendFeatures.PointerHover {
        public func createPointerHoverTarget(wrapping child: Widget) -> Widget {
            PointerHoverWidget(child: child)
        }

        public func updatePointerHoverTarget(
            _ target: any WidgetProtocol,
            environment: EnvironmentValues,
            action: @escaping (PointerHoverPhase) -> Void
        ) {
            let isEnabled = environment.isEnabled
            (target as! PointerHoverWidget).handler = { phase in
                guard isEnabled else { return }
                action(phase)
            }
        }
    }

    /// A `UIHoverGestureRecognizer` on the child: it only observes, so taps and
    /// drags still reach the child. It fires for a pointer -- a trackpad or
    /// mouse on iPad, the pointer in the simulator, Mac Catalyst -- and never
    /// for a finger.
    ///
    /// A finger hovers by holding still for 0.5 s (UIKit's default long-press
    /// duration); from then on, until it lifts, every move is reported, and the
    /// lift ends it. That is the touch form of hover on this backend:
    /// an iPhone has no pointer, and without this `onContinuousHover` reported
    /// nothing there. The long press takes only direct touches, so a pointer on
    /// iPad is not reported twice, and it cancels no touches in the child.
    /// 掛在子 view 上的 `UIHoverGestureRecognizer`:它只觀察，因此點擊與拖曳仍送到子 view。它只對指標觸發——
    /// iPad 上的觸控板或滑鼠、模擬器裡的指標、Mac Catalyst——手指不會觸發。
    /// 手指則是靜止按住 0.5 秒(UIKit 長按的預設時長)即開始 hover;此後到放開為止，每次移動都回報，放開即結束。
    /// 這是本 backend 上 hover 的觸控形式:iPhone 沒有指標，少了它 `onContinuousHover` 在那裡什麼都不回報。
    /// 長按只接受直接觸控，因此 iPad 上的指標不會被回報兩次，而且它不取消子 view 的任何觸控。
    final class PointerHoverWidget: ContainerWidget, UIGestureRecognizerDelegate {
        private var recognizer: UIHoverGestureRecognizer?
        private var pressRecognizer: UILongPressGestureRecognizer?

        var handler: ((PointerHoverPhase) -> Void)? {
            didSet {
                guard handler != nil, recognizer == nil else { return }
                let gesture = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
                child.view.addGestureRecognizer(gesture)
                recognizer = gesture

                let press = UILongPressGestureRecognizer(target: self, action: #selector(hovered(_:)))
                press.minimumPressDuration = 0.5
                press.cancelsTouchesInView = false
                press.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                press.delegate = self
                child.view.addGestureRecognizer(press)
                pressRecognizer = press
            }
        }

        @objc func hovered(_ gesture: UIGestureRecognizer) {
            switch gesture.state {
                case .began, .changed:
                    let point = gesture.location(in: child.view)
                    var modifiers: EventModifiers = []
                    if #available(iOS 13.4, macCatalyst 13.4, *) {
                        modifiers = KeyEventWidget.modifiers(from: gesture.modifierFlags)
                    }
                    handler?(
                        .active(
                            location: SIMD2(Double(point.x), Double(point.y)), modifiers: modifiers))
                case .ended, .cancelled, .failed:
                    handler?(.ended)
                default:
                    break
            }
        }

        /// The hold must not take the touch from the child's own drags and taps.
        /// 按住不得搶走子 view 自己的拖曳與點擊。
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
#endif
