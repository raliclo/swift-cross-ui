import Foundation
@_spi(Backends) import SwiftCrossUI
import UWP
import WinUI
import WindowsFoundation

extension WinUIBackend: BackendFeatures.DragAndDrop {
    public func createDropTarget(wrapping child: Widget) -> Widget {
        DropTargetCanvas(child: child)
    }

    public func updateDropTarget(
        _ dropTarget: Widget,
        acceptedTypes: [DropType],
        environment: EnvironmentValues,
        onHover: @escaping (Bool) -> Void,
        onDrop: @escaping ([DropItem]) -> Bool
    ) {
        let target = dropTarget as! DropTargetCanvas

        // Map the cross-platform identifiers onto the two clipboard formats
        // Windows negotiates over. An identifier with no mapping is not offered,
        // so a drag of that type is refused rather than mishandled.
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

/// A `Canvas` that accepts drops.
///
/// The container exists because the drop flags and events live on `UIElement`,
/// and the wrapped child may be any widget at all -- including one whose own
/// `AllowDrop` the rest of the backend sets for other reasons.
///
/// Two Windows-specific details drive the shape of this:
///
/// - A `Panel` with a nil `Background` is not hit-testable, so a transparent
///   brush is set explicitly. Without it the drag events never fire anywhere the
///   child does not itself paint, which reads as "drop does nothing" over most
///   of the target.
/// - `DragOver` must set `AcceptedOperation` on *every* call, not once on
///   `DragEnter`. Windows re-asks as the pointer moves and treats a missing
///   answer as a refusal, so the cursor flickers between copy and no-drop if the
///   answer is only given at entry.
final class DropTargetCanvas: WinUI.Canvas {
    var child: WinUI.FrameworkElement
    var acceptsFiles = false
    var acceptsText = false
    var onHover: ((Bool) -> Void)?
    var onDrop: (([DropItem]) -> Bool)?

    init(child: WinUI.FrameworkElement) {
        self.child = child

        super.init()

        children.append(child)
        allowDrop = true

        let transparent = WinUI.SolidColorBrush()
        transparent.color = UWP.Color(a: 0, r: 0, g: 0, b: 0)
        background = transparent

        dragEnter.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            let accepted = self.answer(args)
            if accepted {
                self.onHover?(true)
            }
        }

        dragOver.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            _ = self.answer(args)
        }

        dragLeave.addHandler { [weak self] _, _ in
            self?.onHover?(false)
        }

        drop.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            self.receive(args)
        }
    }

    /// Tells Windows whether this target will take the drag currently over it,
    /// and reports back whether it said yes.
    private func answer(_ args: WinUI.DragEventArgs) -> Bool {
        let accepted = format(of: args.dataView) != nil
        args.acceptedOperation = accepted ? .copy : .none
        args.handled = true
        return accepted
    }

    /// The format this target will read the drag as, or `nil` to refuse it.
    ///
    /// Files win over text when a drag carries both, matching what the GTK drop
    /// target negotiates, so an app sees the same item type on both platforms.
    private func format(of dataView: UWP.DataPackageView?) -> DropType? {
        guard let dataView else { return nil }
        if acceptsFiles, (try? dataView.contains(StandardDataFormats.storageItems)) == true {
            return .fileURL
        }
        if acceptsText, (try? dataView.contains(StandardDataFormats.text)) == true {
            return .plainText
        }
        return nil
    }

    /// Reads the payload and hands it to the drop handler.
    ///
    /// Every way of reading a `DataPackageView` is asynchronous, and the view is
    /// only guaranteed valid for the duration of the `Drop` handler, so a
    /// deferral holds the operation open until the read finishes. The deferral is
    /// completed on both paths below; leaking one leaves the source application
    /// waiting on a drop that never resolves.
    private func receive(_ args: WinUI.DragEventArgs) {
        onHover?(false)

        guard let type = format(of: args.dataView), let dataView = args.dataView else {
            args.acceptedOperation = .none
            args.handled = true
            return
        }

        args.acceptedOperation = .copy
        args.handled = true

        let deferral = try? args.getDeferral()

        func finish(_ items: [DropItem]) {
            // The completion handlers below are called by WinRT, not necessarily
            // on the UI thread, and the drop handler runs SwiftCrossUI view code.
            Task { @MainActor in
                // An empty payload means the read failed after the drag had
                // already been accepted. The handler is not called for it -- it
                // is documented as receiving the dropped items, and calling it
                // with none would look to an app like a drop of nothing rather
                // than a drop that could not be read.
                if items.isEmpty || self.onDrop?(items) != true {
                    args.acceptedOperation = .none
                }
                try? deferral?.complete()
            }
        }

        switch type {
            case .fileURL:
                guard let operation = try? dataView.getStorageItemsAsync() else {
                    finish([])
                    return
                }
                operation.completed = { operation, status in
                    guard status == .completed, let items = try? operation?.getResults() else {
                        finish([])
                        return
                    }
                    let paths = Array(items).compactMap { $0?.path }
                    finish([DropItem(type: .fileURL, data: Self.uriList(of: paths))])
                }
            default:
                guard let operation = try? dataView.getTextAsync() else {
                    finish([])
                    return
                }
                operation.completed = { operation, status in
                    guard status == .completed, let text = try? operation?.getResults() else {
                        finish([])
                        return
                    }
                    finish([DropItem(type: .plainText, data: Data(text.utf8))])
                }
        }
    }

    /// Renders file paths as an RFC 2483 `text/uri-list`.
    ///
    /// Windows hands over paths (`C:\dir\file.txt`), not URIs, but ``DropType``
    /// identifies a file drop as `text/uri-list` and ``DropItem/urls`` parses the
    /// payload as one. Handing back raw paths would leave `urls` empty on Windows
    /// while working on Linux -- the silent, platform-specific no-op this
    /// conformance exists to avoid. The conversion is the backend's job precisely
    /// because the platform difference is the backend's.
    private static func uriList(of paths: [String]) -> Data {
        let lines = paths.map { URL(fileURLWithPath: $0).absoluteString }
        return Data(lines.joined(separator: "\r\n").utf8)
    }
}
