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
    /// 掛在子 view 上的 `UIHoverGestureRecognizer`:它只觀察，因此點擊與拖曳仍送到子 view。它只對指標觸發——
    /// iPad 上的觸控板或滑鼠、模擬器裡的指標、Mac Catalyst——手指不會觸發。
    final class PointerHoverWidget: ContainerWidget {
        private var recognizer: UIHoverGestureRecognizer?

        var handler: ((PointerHoverPhase) -> Void)? {
            didSet {
                guard handler != nil, recognizer == nil else { return }
                let gesture = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
                child.view.addGestureRecognizer(gesture)
                recognizer = gesture
            }
        }

        @objc func hovered(_ gesture: UIHoverGestureRecognizer) {
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
    }
#endif
