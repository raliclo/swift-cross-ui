import AppKit
import Foundation

@_spi(Backends) import SwiftCrossUI

extension AppKitBackend: BackendFeatures.Clipping {
    public func createClippedContainer() -> Widget {
        let container = createContainer()
        // The whole difference between the clipped container and the plain one,
        // and the plain one now has to say so too: `NSView.clipsToBounds`
        // defaulted to false when this was written and defaults to true on a
        // modern macOS SDK, so `createContainer` sets it to false explicitly.
        // Without that these two functions returned the same thing.
        //
        // 這是「已裁切的容器」與「一般容器」之間的全部差異，而現在一般容器也必須把這件事說出來：
        // `NSView.clipsToBounds` 在本段寫下時預設為 false，而在現代的 macOS SDK 上預設為 true，
        // 因此 `createContainer` 會明確地把它設為 false。少了那一步，這兩個函式回傳的是同一種東西。
        // `clipsToBounds` is the same switch `setCornerRadius(of:to:)` sets; the
        // layer's `masksToBounds` is set as well because that is what actually
        // does the clipping once the view is layer-backed, and every view in a
        // window with any layer-backed sibling is.
        container.clipsToBounds = true
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        return container
    }
}

extension AppKitBackend: BackendFeatures.DragAndDrop {
    public func createDropTarget(wrapping child: Widget) -> Widget {
        let target = DropTargetView()
        target.translatesAutoresizingMaskIntoConstraints = false
        insert(child, into: target, at: 0)
        // `OnDropModifier` sizes the target but never positions its child, since
        // on GTK the target *is* the child. Pin it here so the wrapper AppKit
        // needs does not leave the content unconstrained.
        setPosition(ofChildAt: 0, in: target, to: .zero)
        return target
    }

    public func updateDropTarget(
        _ dropTarget: Widget,
        acceptedTypes: [DropType],
        environment: EnvironmentValues,
        onHover: @escaping (Bool) -> Void,
        onDrop: @escaping ([DropItem]) -> Bool
    ) {
        let target = dropTarget as! DropTargetView

        // Map the cross-platform identifiers onto the pasteboard types AppKit
        // negotiates over. An identifier with no mapping is not registered, so a
        // drag of that type is refused rather than mishandled.
        target.setAcceptedTypes(
            fileURLs: acceptedTypes.contains(.fileURL),
            text: acceptedTypes.contains(.plainText)
        )

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

/// An `NSView` that accepts drops.
///
/// A view of its own because `registerForDraggedTypes(_:)` and the
/// `NSDraggingDestination` methods have to be on the view that receives the
/// drag, and the wrapped child can be any widget at all.
final class DropTargetView: NSView {
    private var acceptsFiles = false
    private var acceptsText = false
    var onHover: ((Bool) -> Void)?
    var onDrop: (([DropItem]) -> Bool)?

    func setAcceptedTypes(fileURLs: Bool, text: Bool) {
        acceptsFiles = fileURLs
        acceptsText = text

        var types: [NSPasteboard.PasteboardType] = []
        if fileURLs { types.append(.fileURL) }
        if text { types.append(.string) }
        registerForDraggedTypes(types)
    }

    /// The format this target will read a drag as, or `nil` to refuse it.
    ///
    /// Files win over text when a drag carries both, matching what the GTK drop
    /// target negotiates, so an app sees the same item type on every platform.
    /// A file dragged from Finder puts a string on the pasteboard as well as a
    /// URL, so without an order here the same drag would arrive as text on macOS
    /// and as a file everywhere else.
    private func format(of pasteboard: NSPasteboard) -> DropType? {
        let available = pasteboard.types ?? []
        if acceptsFiles, available.contains(.fileURL) {
            return .fileURL
        }
        if acceptsText, available.contains(.string) {
            return .plainText
        }
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard format(of: sender.draggingPasteboard) != nil else { return [] }
        onHover?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHover?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        // Also fired when a drop is completed, which is what the protocol asks
        // for: hover ends when the drag leaves *or* lands.
        onHover?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard let type = format(of: pasteboard) else { return false }

        switch type {
            case .fileURL:
                let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
                guard !urls.isEmpty else { return false }
                // ``DropType/fileURL`` is `text/uri-list` and ``DropItem/urls``
                // parses the payload as one, so the URLs are rendered back into
                // that form rather than handed over as an AppKit object graph.
                // The alternative is a payload only macOS can read, which is the
                // silent platform-specific difference this conformance exists to
                // avoid.
                let list = urls.map(\.absoluteString).joined(separator: "\r\n")
                return onDrop?([DropItem(type: .fileURL, data: Data(list.utf8))]) ?? false
            default:
                guard let text = pasteboard.string(forType: .string) else { return false }
                return onDrop?([DropItem(type: .plainText, data: Data(text.utf8))]) ?? false
        }
    }
}
