import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.ContextMenus {
    public func createContextMenuTarget(wrapping child: Widget) -> Widget {
        NSContextMenuTarget(wrapping: child)
    }

    public func updateContextMenuTarget(
        _ target: Widget,
        menu: ResolvedMenu,
        environment: EnvironmentValues
    ) {
        let target = target as! NSContextMenuTarget
        // **Built with the same renderer `PopoverMenus` uses, not a second one.**
        // `updatePopoverMenu` turns a `ResolvedMenu` into `NSMenuItem`s including
        // toggles, separators and submenus, and it is already the thing this
        // backend is verified on. A context menu that built its own items would
        // be a second place for a submenu to come out slightly different.
        // **用的是 `PopoverMenus` 所用的同一個 renderer,不是第二個。** `updatePopoverMenu` 會把一個
        // `ResolvedMenu` 轉成 `NSMenuItem`(含 toggle、分隔線與子選單),而那正是這個 backend 已經
        // 驗證過的東西。一個自己建項目的 context menu,等於多一個地方讓子選單長得不太一樣。
        let nsMenu = target.menu as? NSMenu ?? NSMenu()
        updatePopoverMenu(nsMenu, content: menu, environment: environment)
        target.menu = nsMenu
    }
}

/// A view that owns a menu raised by a secondary click over it.
///
/// **`NSView.menu` is the whole mechanism, and that is why this class is
/// short.** AppKit walks up from the view under the click asking each for its
/// `menu`, so setting the property is enough -- no gesture recogniser, no
/// `rightMouseDown` override, and no need to pop the menu manually. Overriding
/// `menu(for:)` would allow a different menu per click location, which nothing
/// here asks for and which would put a decision in the backend that belongs in
/// the application.
///
/// A wrapper rather than setting `menu` on the child, for the reason every other
/// target here is a wrapper: the child is whatever the view above produced, and
/// a modifier must not depend on that being a view it is allowed to configure.
///
/// 一個擁有「由次要點擊叫出之選單」的 view。
///
/// **`NSView.menu` 就是全部的機制,而那正是這個類別很短的原因。** AppKit 會從被點擊的那個 view 往上走,
/// 逐一詢問各自的 `menu`,因此只要設好那個屬性就夠了——不需要手勢辨識器、不需要覆寫 `rightMouseDown`、
/// 也不需要自己去彈出選單。覆寫 `menu(for:)` 可以做到「不同點擊位置給不同選單」,而此處沒有任何東西
/// 要求那件事;那也會把一個屬於應用程式的決定,放進 backend 裡。
///
/// 採用包裝、而不是直接對子節點設 `menu`,理由與此處其他每一個 target 相同:子節點是上方那個 view
/// 所產生的任何東西,而一個 modifier 不該假設那是一個它有權去設定的 view。
final class NSContextMenuTarget: NSView {
    init(wrapping child: NSView) {
        super.init(frame: .zero)
        addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
}
