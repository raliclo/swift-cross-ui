import CGtk
import Gtk

/// Whether a Super key (the Windows key; Command on a Mac keyboard) is held,
/// read from the key events themselves.
///
/// On WSLg a pointer move made with Super held reached the app with no
/// modifier: onContinuousHover reported no `.command` (P88, "last with cmd:
/// never"). The X server was not at fault -- xev showed every MotionNotify
/// while Super_L was down with state 0x40, Mod4 (2026-10-21) -- but GDK turns
/// Mod4 into SUPER only when the keymap puts a Super key on Mod4, and the
/// motion state GTK passed on read 0x0. The key press itself does arrive as
/// Super_L. So each window watches Super being pressed and released, and
/// `eventModifiers(from:)` adds `.command` while it is held; where GDK
/// already reports SUPER (macOS, Windows) this changes nothing. Leaving the
/// window inactive clears it, so a release made elsewhere cannot leave it
/// stuck on.
///
/// 是否按住 Super 鍵(Windows 鍵;Mac 鍵盤上的 Command),由按鍵事件本身判斷。WSLg 上按住 Super 移動指標時，事件到了
/// app 卻沒有任何修飾鍵:onContinuousHover 沒有回報 `.command`(P88,「last with cmd: never」)。X 伺服器沒有錯——xev 顯示
/// 按住 Super_L 時每個 MotionNotify 的 state 都是 0x40,也就是 Mod4(2026-10-21)——但 GDK 只在鍵盤對照表把 Super 鍵放在
/// Mod4 上時才把 Mod4 轉成 SUPER,而 GTK 傳出的移動狀態讀到 0x0。按鍵本身則確實以 Super_L 抵達。因此每個視窗都留意
/// Super 的按下與放開,`eventModifiers(from:)` 在按住期間加上 `.command`;GDK 本來就回報 SUPER 的地方(macOS、Windows)
/// 不會有任何改變。視窗變成非作用中時清除，以免在別處放開讓它卡在按住狀態。
enum GtkHeldSuperKey {
    nonisolated(unsafe) private(set) static var isHeld = false

    /// The keys GtkBackend.modifierKey maps to `.command`.
    /// GtkBackend.modifierKey 對應到 `.command` 的那些鍵。
    private static func isSuper(_ keyval: UInt) -> Bool {
        switch Int32(keyval) {
            case GDK_KEY_Super_L, GDK_KEY_Super_R, GDK_KEY_Meta_L, GDK_KEY_Meta_R: true
            default: false
        }
    }

    static func track(_ window: Gtk.Window) {
        let keys = EventControllerKey()
        gtk_event_controller_set_propagation_phase(keys.opaquePointer, GTK_PHASE_CAPTURE)
        keys.keyPressed = { _, keyval, _, _ in
            if isSuper(keyval) { isHeld = true }
            return false
        }
        keys.keyReleased = { _, keyval, _, _ in
            if isSuper(keyval) { isHeld = false }
        }
        window.addEventController(keys)

        let callback:
            @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer?)
                -> Void = { window, _, _ in
                    if gtk_window_is_active(window.assumingMemoryBound(to: GtkWindow.self)) == 0 {
                        GtkHeldSuperKey.isHeld = false
                    }
                }
        g_signal_connect_data(
            UnsafeMutableRawPointer(window.widgetPointer),
            "notify::is-active",
            unsafeBitCast(callback, to: GCallback.self),
            nil,
            nil,
            GConnectFlags(rawValue: 0)
        )
    }
}
