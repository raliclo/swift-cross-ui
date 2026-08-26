import Foundation
@_spi(Backends) import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.Clipping {
    public func createClippedContainer() -> Widget {
        let container = createContainer()
        // A `UIView` draws its subviews past its own edge unless told not to.
        // This is the same switch `setCornerRadius(of:to:)` sets on the layer,
        // without the rounding.
        container.view.clipsToBounds = true
        return container
    }
}

extension UIKitBackend: BackendFeatures.HitTesting {
    /// Subtree-wide, as the protocol requires, and for free: UIKit does not
    /// deliver touches to any descendant of a view whose
    /// `isUserInteractionEnabled` is false, so a nested `allowsHitTesting(true)`
    /// cannot undo it. That is the rule SwiftUI applies, so nothing extra is
    /// needed to match it.
    public func setHitTesting(of widget: Widget, to allowsHitTesting: Bool) {
        widget.view.isUserInteractionEnabled = allowsHitTesting
    }
}

// UIDropInteraction does not exist on tvOS, which has no pointer to drag with.
// The same guard the hover gestures above use, for the same reason.
#if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
    extension UIKitBackend: BackendFeatures.DragAndDrop {
        public func createDropTarget(wrapping child: Widget) -> Widget {
            let target = DropTargetWidget(child: child)
            target.attachInteraction()
            return target
        }

        public func updateDropTarget(
            _ dropTarget: Widget,
            acceptedTypes: [DropType],
            environment: EnvironmentValues,
            onHover: @escaping (Bool) -> Void,
            onDrop: @escaping ([DropItem]) -> Bool
        ) {
            let target = dropTarget as! DropTargetWidget

            // Map the cross-platform identifiers onto the two item-provider
            // classes UIKit negotiates over. An identifier with no mapping is not
            // accepted, so a drag of that type is refused rather than mishandled.
            target.acceptsFiles = acceptedTypes.contains(.fileURL)
            target.acceptsText = acceptedTypes.contains(.plainText)

            target.onHover = { hovering in
                guard environment.isEnabled else { return }
                onHover(hovering)
            }

            target.onDrop = { items in
                guard environment.isEnabled else { return false }
                return onDrop(items)
            }
        }
    }

    /// A widget that accepts drops.
    ///
    /// A `ContainerWidget` holding the child, and the interaction goes on the
    /// child's own view -- the same shape `HoverableWidget` uses for hover
    /// gestures, so the wrapper does not change how the content is laid out.
    final class DropTargetWidget: ContainerWidget, UIDropInteractionDelegate {
        var acceptsFiles = false
        var acceptsText = false
        var onHover: ((Bool) -> Void)?
        var onDrop: (([DropItem]) -> Bool)?

        /// Attaches the drop interaction.
        ///
        /// A method rather than an `init` override because `ContainerWidget`'s
        /// initializer is generic over the child, and this only needs to happen
        /// once, right after construction.
        func attachInteraction() {
            child.view.addInteraction(UIDropInteraction(delegate: self))
        }

        /// The format this target will read a drag as, or `nil` to refuse it.
        ///
        /// Files win over text when a session carries both, matching what the GTK
        /// drop target negotiates, so an app sees the same item type on every
        /// platform.
        private func format(of session: UIDropSession) -> DropType? {
            if acceptsFiles, session.canLoadObjects(ofClass: URL.self) {
                return .fileURL
            }
            if acceptsText, session.canLoadObjects(ofClass: String.self) {
                return .plainText
            }
            return nil
        }

        func dropInteraction(
            _ interaction: UIDropInteraction,
            canHandle session: UIDropSession
        ) -> Bool {
            format(of: session) != nil
        }

        func dropInteraction(
            _ interaction: UIDropInteraction,
            sessionDidEnter session: UIDropSession
        ) {
            onHover?(true)
        }

        func dropInteraction(
            _ interaction: UIDropInteraction,
            sessionDidUpdate session: UIDropSession
        ) -> UIDropProposal {
            UIDropProposal(operation: format(of: session) == nil ? .cancel : .copy)
        }

        func dropInteraction(
            _ interaction: UIDropInteraction,
            sessionDidExit session: UIDropSession
        ) {
            onHover?(false)
        }

        func dropInteraction(
            _ interaction: UIDropInteraction,
            sessionDidEnd session: UIDropSession
        ) {
            onHover?(false)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            onHover?(false)
            guard let type = format(of: session) else { return }

            // `loadObjects` is asynchronous and `performDrop` returns nothing, so
            // the handler's Bool has nowhere to go on this platform: UIKit has
            // already told the source the drop was taken by the time the items
            // arrive. Refusing a drag happens earlier, in `sessionDidUpdate`,
            // which is the only stage UIKit lets a target refuse at.
            switch type {
                case .fileURL:
                    _ = session.loadObjects(ofClass: URL.self) { [weak self] urls in
                        guard !urls.isEmpty else { return }
                        // ``DropType/fileURL`` is `text/uri-list` and
                        // ``DropItem/urls`` parses the payload as one, so the URLs
                        // are rendered back into that form rather than handed over
                        // in a shape only UIKit can read.
                        let list = urls.map(\.absoluteString).joined(separator: "\r\n")
                        _ = self?.onDrop?([DropItem(type: .fileURL, data: Data(list.utf8))])
                    }
                default:
                    _ = session.loadObjects(ofClass: String.self) { [weak self] strings in
                        guard let text = strings.first else { return }
                        _ = self?.onDrop?([DropItem(type: .plainText, data: Data(text.utf8))])
                    }
            }
        }
    }
#endif
