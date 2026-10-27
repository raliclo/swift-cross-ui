import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// `.contextMenu { }` on Android.
///
/// **Two listeners, because Android raises a context menu two different ways and
/// keeps them on two different slots.** A finger raises it with a long press
/// (`View.OnLongClickListener`); a mouse or a stylus raises it with a secondary
/// click (`View.OnContextClickListener`, API 23). `registerForContextMenu` is
/// the framework shortcut that installs both, and it is not used here: it routes
/// through `Activity.onCreateContextMenu`, so the items would have to be rebuilt
/// from an activity-wide callback that has no idea which view asked. Installing
/// the two listeners directly keeps the menu next to the view it belongs to, and
/// gives the same `PopupMenu` that ``BackendFeatures/AttachedMenus`` already
/// builds instead of a second menu style.
///
/// **The one conflict, stated rather than hidden.** A view has exactly one
/// long-click slot, and `updateTapGestureTarget` uses it for
/// `.onTapGesture(.longPress)` (`AndroidBackend+TapGestures.swift:37`). A view
/// carrying both that modifier and `.contextMenu` is the one case where the two
/// overwrite each other, and which survives depends on which modifier commits
/// last. The secondary-click slot has no such conflict -- `.onTapGesture(.secondary)`
/// goes through `setOnTouchListener`, not through this one.
///
/// Android 上的 `.contextMenu { }`。
///
/// **兩個 listener,因為 Android 有兩種叫出脈絡選單的方式,而它把它們放在兩個不同的插槽上。**
/// 手指用長按叫出它(`View.OnLongClickListener`);滑鼠或觸控筆用次要點擊叫出它
/// (`View.OnContextClickListener`,API 23)。`registerForContextMenu` 是「一次裝上兩者」的框架捷徑,
/// 而此處沒有用它:它會繞經 `Activity.onCreateContextMenu`,於是那些項目就得從一個「不知道是哪個 view
/// 發問」的 activity 層級 callback 重建。直接裝上那兩個 listener,可以讓選單待在它所屬的 view 旁邊,
/// 並且沿用 ``BackendFeatures/AttachedMenus`` 已經在建的那個 `PopupMenu`,而不是另造一套選單樣式。
///
/// **唯一的衝突,明說而不藏起來。** 一個 view 只有一個 long-click 插槽,而 `updateTapGestureTarget`
/// 把它用在 `.onTapGesture(.longPress)` 上(`AndroidBackend+TapGestures.swift:37`)。一個同時帶有
/// 該 modifier 與 `.contextMenu` 的 view,就是這兩者會互相覆蓋的那唯一情況;最終存活的是哪一個,
/// 取決於哪個 modifier 最後 commit。次要點擊的插槽沒有這個問題——`.onTapGesture(.secondary)` 走的是
/// `setOnTouchListener`,不是這一個。
///
/// **Verified in two halves, because the popup is a separate window.**
/// `testapp/actions/android/P72-context-menu.actions` long-presses the mesh view,
/// and the popup shows **Reset the camera** and **Snapshot**. Pressing an item
/// was checked with a system-level `adb shell input tap`, because `Activity.dispatchTouchEvent`
/// reaches only this activity's window and a `PopupMenu` is a separate one (the
/// synthesiser has since reached popups through `FrontWindows`); P72
/// then logs `CONTEXT MENU reset the camera: dist 3.40 high 1.30`, the item's
/// action having run. The check can fail: with the long press moved to the title
/// text, no popup appears.
///
/// **分成兩半驗證,因為彈出選單是另一個視窗。**
/// `testapp/actions/android/P72-context-menu.actions` 會長按 mesh view,彈出選單顯示 **Reset the camera**
/// 與 **Snapshot**。按下項目是以系統層級的 `adb shell input tap` 查證的,因為 `Activity.dispatchTouchEvent` 只抵達
/// 本 activity 的視窗,而 `PopupMenu` 是另一個(合成器後來已能經由 `FrontWindows` 抵達彈出視窗);接著 P72 印出 `CONTEXT MENU reset the camera: dist 3.40 high 1.30`,
/// 那就是該項目的動作真的跑過了。這項檢查會失敗:把長按移到標題文字上,完全不會有彈出選單。
extension AndroidBackend: BackendFeatures.ContextMenus {
    public func createContextMenuTarget(wrapping child: Widget) -> Widget {
        child
    }

    public func updateContextMenuTarget(
        _ target: Widget,
        menu: ResolvedMenu,
        environment: EnvironmentValues
    ) {
        guard environment.isEnabled else {
            target.setOnLongClickListener(nil)
            target.setOnContextClickListener(nil)
            return
        }

        // **A fresh holder on every commit, and the menu is realized only when
        // it is raised.** `ResolvedMenu.Item` carries the action closures the
        // framework resolved on THIS commit; a holder kept across commits would
        // hand the popup yesterday's closures. Nothing Java-side is built until
        // the closure below runs, so the cost of rebuilding is a Swift object.
        //
        // The holder is captured rather than left to a local: it owns the JNI
        // global reference to the `PopupMenu`, and it has to outlive this call
        // for the popup to still be there when the finger lifts. Capturing it in
        // the listener's closure ties its lifetime to the listener's, which the
        // view owns.
        //
        // **每次 commit 都建一個全新的 holder,而選單只在被叫出時才實際生成。**
        // `ResolvedMenu.Item` 帶的是框架在**這一次** commit 所解析出的 action closure;一個跨 commit
        // 保留的 holder,會把昨天的 closure 交給那個彈出選單。在下面那個 closure 執行之前,Java 端
        // 什麼也不會建立,因此重建的代價只是一個 Swift 物件。
        //
        // 這個 holder 是被**捕捉**的、而不是留成區域變數:它持有 `PopupMenu` 的 JNI global reference,
        // 而它必須活過這次呼叫,手指抬起時那個彈出選單才還在。把它捕捉進 listener 的 closure,
        // 就把它的生命期綁在 listener 上,而 listener 由那個 view 持有。
        let holder = AndroidBackend.Menu()
        holder.content = menu

        let raise: () -> Void = {
            holder.setView(target, environment: environment)
            holder.show()
        }

        target.setOnLongClickListener(
            ViewOnLongClickListener(action: raise, environment: Self.env)
                .as(AndroidKit.View.OnLongClickListener.self)!
        )
        target.setOnContextClickListener(
            ViewOnContextClickListener(action: raise, environment: Self.env)
                .as(AndroidKit.View.OnContextClickListener.self)!
        )
    }
}
