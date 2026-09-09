@_spi(Backends) import SwiftCrossUI
import UIKit

/// A `UINavigationBar` pinned to the top of the window.
///
/// **How `Placement` is mapped, which the protocol asks each backend to state.**
/// A navigation bar has two regions and iOS users read them: `.leading` goes
/// left, `.trailing` and `.primary` go right, and `.automatic` goes right --
/// which is where a single action lands in almost every stock iOS screen.
/// Within each side, declaration order is kept.
///
/// A bar rather than a `UIToolbar`, which on iOS sits at the BOTTOM of the
/// screen. Both are real answers, and the bar was chosen because a
/// `ToolbarItem` carries a label as well as a symbol and a navigation bar shows
/// labels; a bottom toolbar with three labelled items reads as a tab bar, which
/// is a different control with different meaning.
///
/// 一條固定在視窗頂端的 `UINavigationBar`。
///
/// **`Placement` 的對應方式——協定要求每個 backend 說明這一點。** 導覽列有兩個區域，而 iOS 使用者
/// 讀得懂它們:`.leading` 靠左，`.trailing` 與 `.primary` 靠右，而 `.automatic` 也靠右——那正是
/// 幾乎每一個內建 iOS 畫面上「單一動作」所在的位置。同一側之內，維持宣告順序。
///
/// 使用導覽列而非 `UIToolbar`,後者在 iOS 上位於螢幕**底部**。兩者都是真實的答案,而此處選擇導覽列,
/// 是因為 `ToolbarItem` 除了符號之外還帶著標籤、而導覽列會顯示標籤;一條底部工具列若放三個帶標籤的
/// 項目,讀起來會像 tab bar——那是另一個控制項,意思也不同。
// `SwiftCrossUI.ToolbarItem` throughout, qualified. Unqualified, `ToolbarItem`
// resolves to something else in this file's scope and the error arrives as
// "value of type 'any ToolbarItem' has no member 'action'", which points at the
// member rather than at the name. Same shape as P46Model's ObservableObject
// clashing with Combine's.
// 全檔使用限定寫法 `SwiftCrossUI.ToolbarItem`。不加限定時,`ToolbarItem` 在本檔的作用域中會解析到
// 別的東西,而錯誤訊息是「value of type 'any ToolbarItem' has no member 'action'」——它指向的是那個
// 成員,而不是那個名稱。與 P46Model 的 ObservableObject 和 Combine 撞名是同一種形狀。
extension UIKitBackend: BackendFeatures.Toolbars {
    public func setToolbar(
        ofWindow window: Window,
        to items: [SwiftCrossUI.ToolbarItem],
        title: String?
    ) {
        guard let controller = window.rootViewController as? RootViewController else { return }
        controller.setToolbar(to: items, title: title)
    }
}

/// Carries one item's action across the Objective-C selector boundary.
///
/// `UIBarButtonItem`'s target is unowned, exactly as `NSToolbarItem`'s is, so
/// these are held by the bar's owner. An item whose target has gone does
/// nothing when pressed and reports nothing.
///
/// 把單一項目的動作帶過 Objective-C selector 的邊界。
///
/// `UIBarButtonItem` 的 target 是 unowned 的,與 `NSToolbarItem` 完全相同,因此這些物件由該列的擁有者
/// 持有。一個 target 已消失的項目,按下去不會有任何作用,也不會回報任何事。
final class ToolbarActionTarget: NSObject {
    private let action: @MainActor @Sendable () -> Void

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    // `@MainActor` on the method rather than `assumeIsolated` inside it. Under
    // Swift 6 the closure form is `sending 'self' risks causing data races`:
    // `assumeIsolated` takes a closure that captures `self`, and the compiler
    // cannot see that a UIKit target-action only ever arrives on the main
    // thread. `@objc` and `@MainActor` compose, so saying it directly is both
    // true and checkable.
    //
    // 把 `@MainActor` 加在方法上,而不是在方法內部使用 `assumeIsolated`。在 Swift 6 之下,閉包的寫法
    // 會得到 `sending 'self' risks causing data races`:`assumeIsolated` 收的閉包會捕捉 `self`,而
    // 編譯器看不出「UIKit 的 target-action 只會從主執行緒抵達」。`@objc` 與 `@MainActor` 可以並存,
    // 因此直接說出這件事既為真、也可被檢查。
    @MainActor @objc func fire() {
        action()
    }
}

extension RootViewController {
    func setToolbar(to items: [SwiftCrossUI.ToolbarItem], title: String?) {
        // The bar exists when EITHER was asked for.
        //
        // Before this, `.navigationTitle` drew nothing on iOS: the title reached
        // `UINavigationItem` correctly, and the navigation item was only built
        // inside the `!items.isEmpty` path, so a view with a title and no
        // toolbar got no bar to put it in. Nothing failed -- the string was
        // computed, assigned to `rootViewController.title`, and displayed by
        // nobody.
        //
        // 只要**其中之一**被要求了,那條列就存在。
        //
        // 在此之前,`.navigationTitle` 在 iOS 上什麼都不畫:標題確實正確地抵達了 `UINavigationItem`,
        // 而那個 navigation item 只在 `!items.isEmpty` 的路徑中被建立,因此一個「有標題、沒有工具列」
        // 的 view 根本沒有一條列可以放它。沒有任何東西失敗——那個字串被算了出來、被指派給
        // `rootViewController.title`,然後沒有任何人顯示它。
        let heading = (title?.isEmpty ?? true) ? nil : title
        guard !items.isEmpty || heading != nil else {
            navigationBar?.removeFromSuperview()
            navigationBar = nil
            toolbarTargets = []
            setContentTopInset(0)
            return
        }

        let bar = navigationBar ?? {
            let bar = UINavigationBar()
            bar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            ])
            navigationBar = bar
            // The content starts below the bar rather than under it.
            //
            // Measured on the simulator before this line existed: the app's
            // first line was invisible and the second was cut through the
            // middle of its glyphs. A bar drawn over the top of the content is
            // not a bar that failed -- it renders perfectly -- so the failure
            // reads as "the app is missing a line", which is the wrong thing to
            // go looking for.
            //
            // `intrinsicContentSize` rather than a constant: a navigation bar
            // is 44pt tall in the usual case and taller with a prompt, and
            // hard-coding 44 would put the content back under it the first time
            // anything changed that.
            //
            // 內容從那條列的下方開始,而不是從它的底下穿過去。
            //
            // 在這一行存在之前於模擬器上實測:app 的第一行完全看不見,第二行則被從字符中間切斷。
            // 一條畫在內容上方的列並不是一條「失敗的」列——它繪製得完美無缺——因此那個失敗讀起來
            // 像是「這支 app 少了一行」,而那是完全錯誤的追查方向。
            //
            // 使用 `intrinsicContentSize` 而非常數:導覽列在一般情況下高 44pt,帶有 prompt 時更高,
            // 而寫死 44 會在任何改變它的情況第一次發生時,就把內容重新塞回它底下。
            setContentTopInset(bar.intrinsicContentSize.height)
            return bar
        }()

        var targets: [ToolbarActionTarget] = []
        func barButton(for item: SwiftCrossUI.ToolbarItem) -> UIBarButtonItem {
            let target = ToolbarActionTarget(action: item.action)
            targets.append(target)

            // The symbol goes through the same table `Image(systemName:)` uses,
            // so a toolbar and a button asking for "trash" get one glyph. With
            // no symbol, or an unrecognised name, the label is shown instead --
            // which a navigation bar does natively, unlike a macOS toolbar item
            // that already shows its label underneath.
            // 符號走的是與 `Image(systemName:)` 相同的那張表,因此「工具列」與「按鈕」要求 "trash"
            // 時會得到同一個字符。若沒有符號、或名稱無法辨識,則改為顯示標籤——導覽列原生就會這麼做,
            // 這一點與「本來就會在下方顯示標籤」的 macOS 工具列項目不同。
            let button: UIBarButtonItem
            if let name = item.systemImage,
                let symbol = SystemSymbol.named(name),
                !symbol.sfSymbol.isEmpty,
                let image = UIImage(systemName: symbol.sfSymbol)
            {
                button = UIBarButtonItem(
                    image: image,
                    style: .plain,
                    target: target,
                    action: #selector(ToolbarActionTarget.fire)
                )
                button.accessibilityLabel = item.label
            } else {
                button = UIBarButtonItem(
                    title: item.label,
                    style: .plain,
                    target: target,
                    action: #selector(ToolbarActionTarget.fire)
                )
            }
            button.isEnabled = item.isEnabled
            return button
        }

        let navigationItem = UINavigationItem(title: heading ?? "")
        navigationItem.leftBarButtonItems =
            items.filter { $0.placement == .leading }.map(barButton(for:))
        navigationItem.rightBarButtonItems =
            items.filter { $0.placement != .leading }.map(barButton(for:))
        bar.setItems([navigationItem], animated: false)

        toolbarTargets = targets
        view.setNeedsLayout()
    }
}
