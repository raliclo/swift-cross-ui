@_spi(Backends) import SwiftCrossUI
import WinUI

/// `BackendFeatures.ButtonPressState` on WinUI.
///
/// **This file does not touch either button class, and that is not a
/// concession -- it is the better implementation.** WinUIBackend has two, and
/// the note at `WinUIBackend+Button.swift:56` explains why neither may be
/// deleted: `ViewLabelCustomButton` backs `createButton(wrapping:)`, while
/// `CustomButton` in `WinUIBackend.swift:2896` still backs `createSimpleButton`,
/// `updateSimpleButton` and the menu/flyout `updateButton(_:label:menu:_)`. Both
/// kinds can be handed to `updateButtonPressHandler`. Hooking the private
/// `isHighlighted` of the first (`WinUIBackend+Button.swift:83`) would have
/// covered one of the two and left the other silent -- and `ViewLabelCustomButton`
/// is `fileprivate`, so it is not reachable from here in any case.
///
/// Both derive from `WinUI.Button`, which derives from `WinUI.ButtonBase`
/// (`swift-winui/Sources/WinUI/Generated/Microsoft.UI.Xaml.Controls.swift:614`),
/// and `ButtonBase` publishes the press state XAML itself maintains, as a
/// dependency property: `isPressed`
/// (`.../Microsoft.UI.Xaml.Controls.Primitives.swift:124`) and
/// `isPressedProperty` (same file, line 96). `DependencyObject` can report
/// changes to any dependency property through
/// `registerPropertyChangedCallback(_:_:)`
/// (`.../Microsoft.UI.Xaml.swift:797`), whose callback is
/// `(DependencyObject?, DependencyProperty?) -> ()`
/// (`.../Microsoft.UI.Xaml.swift:5501`). One registration, both button classes,
/// and no subclass to keep in step.
///
/// **The abandon case is XAML's own.** `ButtonBase` clears `IsPressed` when the
/// pointer leaves the button while it is captured, and again on
/// `PointerCaptureLost`. That is exactly the behaviour
/// `ViewLabelCustomButton.onPointerMoved` reimplements by hand at
/// `WinUIBackend+Button.swift:129-150` in order to get a hook into it -- the
/// bounds test there is a copy of the framework's, not an improvement on it. So
/// press, drag off, release reports `true` then `false`, and dragging back on
/// reports `true` again.
///
/// WinUI 上的 `BackendFeatures.ButtonPressState`。
///
/// **本檔不碰任何一個按鈕類別，而這並非退讓——它是更好的實作。** WinUIBackend 有兩個按鈕類別，
/// `WinUIBackend+Button.swift:56` 的註記說明了為何兩者都不得刪除：`ViewLabelCustomButton` 支撐
/// `createButton(wrapping:)`，而 `WinUIBackend.swift:2896` 的 `CustomButton` 仍支撐
/// `createSimpleButton`、`updateSimpleButton` 與 menu/flyout 的 `updateButton(_:label:menu:_)`。
/// 兩種都可能被交給 `updateButtonPressHandler`。去掛前者那個私有的 `isHighlighted`
/// （`WinUIBackend+Button.swift:83`）只會涵蓋兩者之一而讓另一者靜默——況且 `ViewLabelCustomButton`
/// 是 `fileprivate`，本來就無法從此處取用。
///
/// 兩者皆衍生自 `WinUI.Button`，而後者衍生自 `WinUI.ButtonBase`
/// （`swift-winui/Sources/WinUI/Generated/Microsoft.UI.Xaml.Controls.swift:614`），
/// 而 `ButtonBase` 以 dependency property 的形式公開了 XAML 自己維護的按下狀態：`isPressed`
/// （`.../Microsoft.UI.Xaml.Controls.Primitives.swift:124`）與 `isPressedProperty`（同檔第 96 行）。
/// `DependencyObject` 可透過 `registerPropertyChangedCallback(_:_:)`
/// （`.../Microsoft.UI.Xaml.swift:797`）回報任何 dependency property 的變化，其 callback 型別為
/// `(DependencyObject?, DependencyProperty?) -> ()`（`.../Microsoft.UI.Xaml.swift:5501`）。
/// 一次註冊、兩個按鈕類別，且沒有任何子類別需要同步維護。
///
/// **放棄的情況由 XAML 自己處理。** `ButtonBase` 會在指標於捕獲期間離開按鈕時清除 `IsPressed`，
/// 並在 `PointerCaptureLost` 時再次清除。那正是 `ViewLabelCustomButton.onPointerMoved` 於
/// `WinUIBackend+Button.swift:129-150` 手工重現的行為——該處的邊界判斷是框架行為的複製品，而非改良。
/// 因此「按下、拖離、放開」會回報 `true` 而後 `false`，再拖回按鈕上則會再次回報 `true`。
///
/// **A bare extension, deliberately.** The conformance is declared on the class
/// itself at `WinUIBackend.swift:131`; naming
/// `BackendFeatures.ButtonPressState` again here would be a redundant
/// conformance and would not compile.
///
/// **刻意採用不帶 conformance 的 extension。** 該 conformance 已宣告於類別本身
/// （`WinUIBackend.swift:131`）；在此再次寫出 `BackendFeatures.ButtonPressState` 會構成重複
/// conformance 而無法編譯。
extension WinUIBackend {
    public func updateButtonPressHandler(
        _ button: Widget,
        handler: @escaping (Bool) -> Void
    ) {
        // Soft, so a widget that is not a button -- which the contract says
        // cannot happen, but which a future caller could still produce -- is
        // ignored rather than trapped. Nothing here is worth taking an
        // application down for.
        // 採柔性轉型，好讓一個並非按鈕的 widget——合約說這不會發生，但未來的呼叫端仍可能產生——被
        // 忽略而非造成中止。此處沒有任何事值得讓整個應用程式倒下。
        guard let buttonBase = button as? WinUI.ButtonBase else { return }
        WinUIButtonPressTracker.install(on: buttonBase, handler: handler)
    }
}

/// Per-button state behind ``WinUIBackend/updateButtonPressHandler(_:handler:)``.
///
/// A table rather than a stored property, because there is no class here to
/// store it on -- see the file comment. Keyed by object identity: the widget
/// SwiftCrossUI hands back is the very `WinUI.Button` instance `createButton`
/// returned, so identity is stable for the button's lifetime.
///
/// `Button.commit` reinstalls on every update
/// (`Sources/SwiftCrossUI/Views/Button.swift:349`), so an existing entry must
/// swap its closure rather than register a second callback; registering per
/// commit would leave a callback per frame attached to the property.
///
/// ``WinUIBackend/updateButtonPressHandler(_:handler:)`` 背後的每按鈕狀態。
///
/// 使用表格而非儲存屬性，因為此處沒有任何類別可供存放——詳見檔案開頭的說明。以物件識別為鍵：
/// SwiftCrossUI 交回來的 widget 就是 `createButton` 當初回傳的那個 `WinUI.Button` 實例，因此在該
/// 按鈕的存活期間，識別是穩定的。
///
/// `Button.commit` 每次更新都會重新安裝（`Sources/SwiftCrossUI/Views/Button.swift:349`），因此既有
/// 項目必須替換它的 closure，而不是再註冊一個 callback；若每次 commit 都註冊，該屬性上便會逐幀累積
/// callback。
@MainActor
final class WinUIButtonPressTracker {
    private static var trackers: [ObjectIdentifier: WinUIButtonPressTracker] = [:]

    /// Weak, so a discarded button does not keep its XAML object alive through
    /// this table, and so `install` can tell dead entries from live ones.
    /// 弱參考，使被丟棄的按鈕不會透過這張表讓它的 XAML 物件續命，也讓 `install` 能分辨死掉與存活的項目。
    private weak var button: WinUI.ButtonBase?
    private var handler: (Bool) -> Void
    private var reported = false

    private init(button: WinUI.ButtonBase, handler: @escaping (Bool) -> Void) {
        self.button = button
        self.handler = handler
    }

    static func install(on button: WinUI.ButtonBase, handler: @escaping (Bool) -> Void) {
        let key = ObjectIdentifier(button)

        if let existing = trackers[key] {
            existing.handler = handler
            return
        }

        // Swept on install rather than on a timer: the only thing that grows
        // this table is installing into it.
        // 於安裝時清掃，而非用計時器：唯一會讓這張表變大的，就是往其中安裝。
        trackers = trackers.filter { $0.value.button != nil }

        let tracker = WinUIButtonPressTracker(button: button, handler: handler)
        trackers[key] = tracker

        // `try?` and not `try!`: the registration is a COM call, and a button
        // that cannot report its press state is a button that draws in one
        // style, not a reason to abort.
        // 使用 `try?` 而非 `try!`：這次註冊是一個 COM 呼叫，而一顆無法回報按下狀態的按鈕，
        // 只是一顆樣式不會變化的按鈕，不構成中止的理由。
        _ = try? button.registerPropertyChangedCallback(WinUI.ButtonBase.isPressedProperty) {
            _, _ in
            MainActor.assumeIsolated {
                tracker.update()
            }
        }
    }

    private func update() {
        guard let button else { return }

        let pressed = button.isPressed
        guard pressed != reported else { return }
        reported = pressed
        handler(pressed)
    }
}
