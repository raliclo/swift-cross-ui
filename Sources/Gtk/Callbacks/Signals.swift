//
//  Copyright © 2015 Tomas Linhart. All rights reserved.
//

import CGtk
import GtkCHelpers

enum ConnectFlags {
    case after
    case swapped

    func toGConnectFlags() -> GConnectFlags {
        switch self {
            case .after:
                return SHIM_G_CONNECT_AFTER
            case .swapped:
                return SHIM_G_CONNECT_SWAPPED
        }
    }
}

// Handler ids stay in `gulong`, the type GLib actually uses, instead of being
// converted to `UInt`. The two are the same width on LP64 systems such as Linux
// and macOS, which is why converting worked there, but Windows is LLP64: `long`
// is 32 bits, so `gulong` is `UInt32` while `UInt` is 64. Converting on the way
// out then failed to convert back on the way in, and every call that takes an
// id -- disconnect, block, unblock -- stopped compiling. Keeping the native
// type needs no platform conditionals and is correct on both models.
@discardableResult
func connectSignal<T>(
    _ instance: UnsafeMutablePointer<T>?,
    name: String,
    data: UnsafeRawPointer,
    connectFlags: ConnectFlags = .after,
    handler: @escaping GCallback
) -> gulong {
    return g_signal_connect_data(
        instance,
        name,
        handler,
        data.cast(),
        nil,
        connectFlags.toGConnectFlags()
    )
}

@discardableResult
func connectSignal<T>(
    _ instance: UnsafeMutablePointer<T>?,
    name: String,
    connectFlags: ConnectFlags = .after,
    handler: @escaping GCallback
) -> gulong {
    return g_signal_connect_data(
        instance, name, handler, nil, nil, connectFlags.toGConnectFlags()
    )
}

func disconnectSignal<T>(_ instance: UnsafeMutablePointer<T>?, handlerId: gulong) {
    g_signal_handler_disconnect(instance, handlerId)
}
