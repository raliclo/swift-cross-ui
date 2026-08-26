import CGtk

/// The GTK settings for the default display.
///
/// Settings are per-display, not per-window: GTK has no per-window theme
/// variant, so an app that asks two windows for opposite colour schemes cannot
/// have both.
///
/// GTK 的預設 display 設定。
///
/// 設定為 per-display 而非 per-window：GTK 沒有 per-window 的主題變體，因此若 app 要求兩個視窗
/// 使用相反的配色，無法同時滿足。
public class Settings: GObject {
    /// The wrapper handed out by ``default``, kept so that repeated accesses
    /// return the same object rather than a fresh one each time.
    ///
    /// A subscription registered through ``registerNotification(named:handler:)``
    /// lives on the wrapper, and ``GObject/deinit`` disconnects every handler
    /// the wrapper registered (added for issue #588). A wrapper that nobody
    /// stores is released at the end of the statement that made it, so
    /// `Settings.default?.registerNotification(...)` used to connect and
    /// disconnect in the same expression and could never fire. Caching removes
    /// that trap for every caller instead of asking each one to remember it.
    private static var cachedDefault: Settings?

    /// The settings object for the default display, or `nil` if there is no
    /// display yet.
    public static var `default`: Settings? {
        guard let pointer = gtk_settings_get_default() else {
            return nil
        }

        // Re-wrap if GTK handed back a different settings object, which happens
        // when the default display changes.
        if let cached = cachedDefault, cached.opaquePointer == pointer {
            return cached
        }

        let settings = Settings(pointer)
        cachedDefault = settings
        return settings
    }

    /// Whether to use the dark variant of the current theme.
    ///
    /// Note that this is a request, not a reading: it does not report whether
    /// the theme in effect is dark. A theme selected with `GTK_THEME=Adwaita:dark`
    /// leaves this `false` while drawing everything dark, so code that needs to
    /// know the ambient scheme has to look at a colour instead.
    ///
    /// 注意這是「要求」而非「讀數」：它並不回報目前生效的主題是否為深色。以
    /// `GTK_THEME=Adwaita:dark` 選定的主題會讓此值維持 `false`，卻把一切繪製成深色，因此需要知道
    /// 環境配色的程式必須改看顏色。
    @GObjectProperty(named: "gtk-application-prefer-dark-theme")
    public var preferDarkTheme: Bool

    /// Calls `handler` whenever the named property changes, e.g.
    /// `notify::gtk-theme-name`.
    ///
    /// The subscription lives on this object and is disconnected when it is
    /// released. ``default`` caches its wrapper, so a subscription made through
    /// it lasts for the life of the process.
    ///
    /// 每當具名屬性變更時呼叫 `handler`，例如 `notify::gtk-theme-name`。
    ///
    /// 該訂閱寄生於此物件，並於其被釋放時中斷連線。``default`` 會快取其 wrapper，因此透過它建立
    /// 的訂閱可存續至行程結束。
    public func registerNotification(named name: String, handler: @escaping () -> Void) {
        // Not addSignal: `notify` passes a GParamSpec ahead of the user data,
        // so the parameterless form would take the GParamSpec for its box.
        addNotificationSignal(name: name, callback: handler)
    }
}
