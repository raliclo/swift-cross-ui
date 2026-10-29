extension BackendFeatures {
    /// Backend methods for the platform's own Back: the system Back key and
    /// back gesture on Android, the left-edge swipe on iOS, Command-[ and the
    /// mouse's back button on macOS, Alt+Left, the Back key and the mouse's
    /// back button on Linux and Windows.
    ///
    /// These are used by ``NavigationStack``: while any stack in a window has
    /// something pushed, Back pops the innermost such stack, as it does in the
    /// platform's own navigation views. Backends without this feature keep the
    /// stack's drawn back control, which works everywhere.
    ///
    /// **The handler is removed whenever nothing in the window can go back**,
    /// and a backend must then leave Back exactly as it is without a handler.
    /// On Android that is what keeps the system Back finishing the activity (or
    /// reaching the `windowDismissBehavior` interception) at the root of every
    /// stack. A handler that returns `false` asks for the same: the event
    /// continues as if no handler were set.
    ///
    /// 平台自己的「返回」所用的 backend 方法:Android 的系統返回鍵與返回手勢、iOS 的左緣滑動、macOS 的
    /// Command-[ 與滑鼠返回鍵、Linux 與 Windows 的 Alt+Left、返回鍵與滑鼠返回鍵。
    ///
    /// 由 ``NavigationStack`` 使用：只要視窗中有任何堆疊推入了內容，返回就會彈出其中最內層的那個堆疊，與平台自己的
    /// 導覽視圖相同。沒有此 feature 的 backend 仍保有堆疊自己畫出的返回控制項，那在每個 backend 上都可用。
    ///
    /// **只要視窗中沒有任何東西可以返回，handler 就會被移除**,此時 backend 必須讓返回維持沒有 handler 時的原樣。
    /// 在 Android 上，正是這一點讓每個堆疊位於根層時，系統返回仍會結束 activity(或抵達 `windowDismissBehavior`
    /// 的攔截)。handler 回傳 `false` 也是同樣的要求：事件照常繼續，如同沒有設定 handler。
    @MainActor
    public protocol BackNavigation<Window>: Core {
        /// Sets the action the platform's Back runs in `window`, or removes it
        /// when `action` is `nil`.
        ///
        /// - Parameters:
        ///   - window: The window whose Back is handled.
        ///   - action: Goes back one step and returns `true`, or returns
        ///     `false` when there was nothing to go back from, in which case
        ///     the event continues as if no action were set.
        ///
        /// 設定平台的返回在 `window` 中所執行的動作；`action` 為 `nil` 時移除它。`action` 返回一步並回傳 `true`,
        /// 或在沒有東西可返回時回傳 `false`,此時事件照常繼續，如同沒有設定動作。
        func setBackNavigationHandler(
            ofWindow window: Window,
            to action: (@MainActor () -> Bool)?
        )
    }

    /// The same as ``BackNavigation`` for a sheet: Back while the sheet is in
    /// front pops a ``NavigationStack`` inside the sheet.
    ///
    /// A sheet's handler is set only while a stack in that sheet can pop. With
    /// no handler, Back in the sheet must do exactly what it did before -- on
    /// Android, dismissing the sheet only if it is dismissable -- and must not
    /// reach the window under the sheet: a backend whose window handler could
    /// see Back while a sheet is up (a key accelerator on the window, a mouse
    /// button on the parent window) ignores it then.
    ///
    /// sheet 版的 ``BackNavigation``:sheet 在前景時的返回，彈出 sheet 內的 ``NavigationStack``。只在該 sheet 中有堆疊
    /// 可以彈出時才設定 sheet 的 handler。沒有 handler 時,sheet 中的返回必須維持原本的行為——在 Android 上，只在 sheet 可
    /// 關閉時才關閉它——而且不可以抵達 sheet 底下的視窗：視窗 handler 在 sheet 開著時仍可能看到返回的 backend(視窗上的
    /// 加速鍵、父視窗上的滑鼠鍵),此時要忽略它。
    @MainActor
    public protocol SheetBackNavigation<Sheet>: Sheets {
        /// Sets the action Back runs while `sheet` is in front, or removes it
        /// when `action` is `nil`. `action` returns `false` when there was
        /// nothing to go back from.
        /// 設定 `sheet` 在前景時返回所執行的動作；`action` 為 `nil` 時移除它。沒有東西可返回時 `action` 回傳 `false`。
        func setBackNavigationHandler(
            ofSheet sheet: Sheet,
            to action: (@MainActor () -> Bool)?
        )
    }
}
