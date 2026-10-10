import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend: BackendFeatures.PointerHover {
    public func createPointerHoverTarget(wrapping child: Widget) -> Widget {
        let motion = EventControllerMotion()
        motion.name = "scui-pointer-hover"
        child.addEventController(motion)
        return child
    }

    public func updatePointerHoverTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        action: @escaping (PointerHoverPhase) -> Void
    ) {
        // The controller this modifier added, not the one onHover may have added.
        // 這個 modifier 加的那個控制器，而不是 onHover 可能加的那個。
        guard
            let motion = target.eventControllers.first(where: {
                ($0 as? EventControllerMotion)?.name == "scui-pointer-hover"
            }) as? EventControllerMotion
        else { return }
        let isEnabled = environment.isEnabled
        let report: (EventControllerMotion, Double, Double) -> Void = { controller, x, y in
            guard isEnabled else { return }
            // The modifiers held with this motion. / 這次移動時按住的修飾鍵。
            let state = gtk_event_controller_get_current_event_state(
                controller.opaquePointer)
            action(.active(location: SIMD2(x, y), modifiers: Self.eventModifiers(from: state)))
        }
        motion.enter = report
        motion.motion = report
        motion.leave = { _ in
            guard isEnabled else { return }
            action(.ended)
        }
    }
}
