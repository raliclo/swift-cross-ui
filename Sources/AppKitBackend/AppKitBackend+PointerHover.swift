import AppKit
@_spi(Backends) import SwiftCrossUI

extension AppKitBackend: BackendFeatures.PointerHover {
    public func createPointerHoverTarget(wrapping child: Widget) -> Widget {
        let container = NSPointerHoverContainer()
        container.addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        child.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        child.topAnchor.constraint(equalTo: container.topAnchor).isActive = true
        return container
    }

    public func updatePointerHoverTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        action: @escaping (PointerHoverPhase) -> Void
    ) {
        let container = target as! NSPointerHoverContainer
        let isEnabled = environment.isEnabled
        container.handler = { phase in
            guard isEnabled else { return }
            action(phase)
        }
    }
}

/// The tracking area is on this plain container rather than on a view laid
/// over the child, which is what the `onHover` target does: an overlay
/// receives the mouse-down, and a drag on a `Mesh3DView` underneath would
/// never start.
///
/// tracking area 掛在這個普通容器上，而不是像 `onHover` 的目標那樣掛在一個蓋在子 view 上方的 view:
/// 覆蓋層會收到 mouse-down,底下 `Mesh3DView` 的拖曳就永遠不會開始。
final class NSPointerHoverContainer: NSView {
    var handler: ((PointerHoverPhase) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var flagsMonitor: Any?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func report(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        handler?(
            .active(
                location: SIMD2(Double(point.x), Double(point.y)),
                modifiers: NSKeyEventTarget.modifiers(from: event.modifierFlags)))
    }

    override func mouseEntered(with event: NSEvent) {
        report(event)
        // A modifier pressed while the pointer is still: the event goes to the
        // first responder, so watch for it here, and only while inside.
        // 指標不動時按下的修飾鍵：那個事件送往 first responder,所以在這裡監看，而且只在指標在內時。
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            guard let self, let window = self.window else { return event }
            let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if self.bounds.contains(point) {
                self.handler?(
                    .active(
                        location: SIMD2(Double(point.x), Double(point.y)),
                        modifiers: NSKeyEventTarget.modifiers(from: event.modifierFlags)))
            }
            return event
        }
    }

    override func mouseMoved(with event: NSEvent) {
        report(event)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        stopWatchingFlags()
        handler?(.ended)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopWatchingFlags() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func stopWatchingFlags() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
    }
}
