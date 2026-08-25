import CGtk
import GtkCHelpers

/// The kind of payload a drop delivered, distinguishing the two content types a
/// ``DropTarget`` negotiates over.
public enum DropPayloadKind {
    /// A `text/uri-list`: CRLF-separated `file://` URIs.
    case fileURIList
    /// Plain UTF-8 text.
    case text
}

/// A drop target: a `GtkDropTarget` event controller that accepts a copy of
/// dropped content of the types it is told to.
///
/// The controller negotiates over GTypes, not MIME strings, and hands the drop
/// back as a `GValue`; both ends of that are unpacked by the C helpers in
/// GtkCHelpers so this wrapper deals only in ``DropPayloadKind`` and `String`.
///
/// Hover feedback comes from the `current-drop` property rather than the
/// `enter`/`leave` signals: those carry a `GdkDragAction` return that decides
/// whether the drag is accepted, and connecting a plain observer to them would
/// risk clobbering that decision. `notify::current-drop` is a plain
/// notification -- it fires when a drag enters (the property goes non-null) and
/// when it leaves (back to null) -- and reading the property tells us which.
open class DropTarget: EventController {
    // Computed rather than stored, so there is no init to override and no
    // conflict with GObject's generic pointer initialiser; the underlying
    // GtkDropTarget is the same object the GObject base already holds.
    private var dropTargetPointer: OpaquePointer {
        OpaquePointer(gobjectPointer)
    }

    /// Called with `true` when an accepted drag enters the widget, `false` when
    /// it leaves or the drop completes.
    public var onHover: ((Bool) -> Void)?

    /// Called when a drop lands, with the payload kind and its contents.
    /// Returns whether the drop was accepted.
    public var onDrop: ((DropPayloadKind, String) -> Bool)?

    // The drop signal is connected by hand (see registerSignals), so unlike the
    // addSignal-based signals it is not in GObject's auto-disconnected set. Keep
    // its id and drop it in deinit, or a drop delivered to a GtkDropTarget that
    // outlives this wrapper would call takeUnretainedValue on freed memory.
    private var dropHandlerID: gulong?

    /// Creates a drop target that requests a copy action. It accepts nothing
    /// until ``setAcceptedTypes(fileURLs:text:)`` is called.
    public convenience init() {
        // G_TYPE_INVALID up front; the accepted types are set separately, to
        // follow the create/update split the backend uses everywhere.
        self.init(
            gtk_drop_target_new(GType(0), scui_drag_action_copy())
        )
    }

    /// Sets which content types the target accepts. Passing neither makes the
    /// target accept nothing, which reads as a refusal for any drop.
    public func setAcceptedTypes(fileURLs: Bool, text: Bool) {
        var types: [GType] = []
        if fileURLs {
            types.append(scui_gtype_file_list())
        }
        if text {
            types.append(scui_gtype_string())
        }
        types.withUnsafeMutableBufferPointer { buffer in
            gtk_drop_target_set_gtypes(dropTargetPointer, buffer.baseAddress, gsize(buffer.count))
        }
    }

    open override func registerSignals() {
        super.registerSignals()

        // Hover feedback: notify::current-drop fires on enter (null -> drop) and
        // on leave (drop -> null); the property itself says which.
        addSignal(name: "notify::current-drop") { [weak self] () in
            guard let self else { return }
            let hovering = gtk_drop_target_get_current_drop(self.dropTargetPointer) != nil
            self.onHover?(hovering)
        }

        // The drop signal returns gboolean (accept/refuse), which the addSignal
        // helpers cannot express -- they assume a void return -- so connect it
        // directly. Unretained user data: this wrapper is kept alive by the
        // widget's eventControllers for as long as the controller exists, so
        // there is nothing extra to retain and no cycle to create.
        let handler:
            @convention(c) (
                UnsafeMutableRawPointer?,
                UnsafePointer<GValue>?,
                Double,
                Double,
                UnsafeMutableRawPointer?
            ) -> gboolean = { _, valuePointer, _, _, data in
                guard let data else { return false.toGBoolean() }
                let target = Unmanaged<DropTarget>.fromOpaque(data).takeUnretainedValue()
                return target.handleDrop(value: valuePointer).toGBoolean()
            }

        dropHandlerID = g_signal_connect_data(
            UnsafeMutableRawPointer(dropTargetPointer),
            "drop",
            gCallback(handler),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            SHIM_G_CONNECT_AFTER
        )
    }

    deinit {
        // Disconnect the hand-connected drop signal before GObject's deinit
        // releases the object; the addSignal-based signals are handled there.
        if let dropHandlerID {
            g_signal_handler_disconnect(gobjectPointer, dropHandlerID)
        }
    }

    private func handleDrop(value: UnsafePointer<GValue>?) -> Bool {
        guard let onDrop else { return false }
        switch scui_drop_value_kind(value) {
            case 1:
                guard let cString = scui_drop_value_uri_list(value) else { return false }
                defer { g_free(cString) }
                return onDrop(.fileURIList, String(cString: cString))
            case 2:
                guard let cString = scui_drop_value_string(value) else { return false }
                defer { g_free(cString) }
                return onDrop(.text, String(cString: cString))
            default:
                // A type we did not offer. Refuse it rather than swallow it.
                return false
        }
    }
}
