import AppKit
@_spi(Backends) import SwiftCrossUI

/// `NSToolbar`, driven from the resolved ``ToolbarItem`` list.
///
/// **How `Placement` is mapped, which the protocol asks each backend to say.**
/// An `NSToolbar` is a single ordered row with no leading or trailing regions
/// -- macOS has no navigation bar -- so `.leading`, `.trailing`, `.primary` and
/// `.automatic` all place the item in that row. What the placement does affect
/// is order: leading items come first, then automatic, then primary, then
/// trailing. That is a reading of the intent rather than an implementation of
/// it, and it is written here rather than left for someone to infer from the
/// result.
///
/// `NSToolbar`，由已解析的 ``ToolbarItem`` 清單驅動。
///
/// **`Placement` 的對應方式——協定要求每個 backend 說明這一點。** `NSToolbar` 是單一有序列，沒有前緣
/// 或後緣區域(macOS 沒有導覽列)，因此 `.leading`、`.trailing`、`.primary` 與 `.automatic` 都會把
/// 項目放進那一列。placement 真正影響的是**順序**:leading 在前，接著 automatic、primary，最後
/// trailing。那是對意圖的一種解讀，而非對它的實作;此處寫明，而不是留給人從結果去推測。
extension AppKitBackend: BackendFeatures.Toolbars {
    public func setToolbar(ofWindow window: Window, to items: [ToolbarItem]) {
        guard !items.isEmpty else {
            window.toolbar = nil
            return
        }

        let ordered = items.sorted { lhs, rhs in
            Self.order(of: lhs.placement) < Self.order(of: rhs.placement)
        }

        let delegate = ToolbarDelegate(items: ordered)
        let toolbar = NSToolbar(identifier: "dev.swiftcrossui.toolbar")
        toolbar.delegate = delegate
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false

        // The delegate is not retained by NSToolbar, and a toolbar whose
        // delegate has been deallocated shows nothing while reporting no error.
        // Held on the window, which outlives the toolbar it owns.
        // NSToolbar 不會持有其 delegate,而一個 delegate 已被釋放的 toolbar 什麼都不會顯示,卻也
        // 不會回報任何錯誤。此處掛在視窗上,而視窗的生命週期長於它所擁有的 toolbar。
        window.toolbarDelegate = delegate
        window.toolbar = toolbar
    }

    private static func order(of placement: ToolbarItem.Placement) -> Int {
        switch placement {
            case .leading: 0
            case .automatic: 1
            case .primary: 2
            case .trailing: 3
        }
    }
}

/// Vends one `NSToolbarItem` per ``ToolbarItem``.
///
/// A class because `NSToolbar` wants a delegate, and the identifiers are the
/// item's index rather than its label: two toolbar buttons may legitimately
/// share a label, and `NSToolbar` treats a repeated identifier as the same
/// item and shows it once.
///
/// 為每一個 ``ToolbarItem`` 產生一個 `NSToolbarItem`。
///
/// 使用 class 是因為 `NSToolbar` 需要一個 delegate;而識別碼採用項目的索引而非其標籤,因為兩個工具列
/// 按鈕合理地可能共用同一個標籤,而 `NSToolbar` 會把重複的識別碼視為同一個項目、只顯示一次。
final class ToolbarDelegate: NSObject, NSToolbarDelegate {
    private let items: [ToolbarItem]
    private let identifiers: [NSToolbarItem.Identifier]

    init(items: [ToolbarItem]) {
        self.items = items
        self.identifiers = items.indices.map {
            NSToolbarItem.Identifier("dev.swiftcrossui.toolbar.item.\($0)")
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let index = identifiers.firstIndex(of: itemIdentifier) else { return nil }
        let model = items[index]

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = model.label
        item.paletteLabel = model.label
        item.isEnabled = model.isEnabled

        // The symbol goes through the same table `Image(systemName:)` uses, so a
        // toolbar and a button asking for "trash" get the same glyph. An
        // unrecognised name draws nothing here rather than its own text: a
        // toolbar item already shows its label, so the fallback would print the
        // name twice.
        // 符號走的是與 `Image(systemName:)` 相同的那張表,因此「工具列」與「按鈕」要求 "trash" 時會
        // 得到同一個字符。無法辨識的名稱在此不繪製任何東西,而非畫出它自己的文字:工具列項目本來就會
        // 顯示它的標籤,若再走退路就會把名稱印兩次。
        if let name = model.systemImage,
           let symbol = SystemSymbol.named(name),
           !symbol.sfSymbol.isEmpty
        {
            item.image = NSImage(
                systemSymbolName: symbol.sfSymbol,
                accessibilityDescription: symbol.name
            )
        }

        let target = ToolbarActionTarget(action: model.action)
        item.target = target
        item.action = #selector(ToolbarActionTarget.fire)
        actionTargets.append(target)

        return item
    }

    /// `NSToolbarItem.target` is unowned, so the target has to be held here or
    /// the button does nothing the moment the item is built.
    /// `NSToolbarItem.target` 是 unowned 的,因此 target 必須被此處持有,否則該按鈕在項目建立完成的
    /// 那一刻起就毫無作用。
    private var actionTargets: [ToolbarActionTarget] = []
}

final class ToolbarActionTarget: NSObject {
    private let action: @MainActor @Sendable () -> Void

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    // `@MainActor` on the method rather than `assumeIsolated` inside it.
    //
    // Under Swift 6 the closure form is `sending 'self' risks causing data
    // races`: `assumeIsolated` takes a closure that captures `self`, and the
    // compiler cannot see that an NSToolbarItem's action only ever arrives on
    // the main thread. Saying so directly is both true and checkable, and
    // `@objc` and `@MainActor` compose.
    //
    // 把 `@MainActor` 加在方法上,而不是在方法內部使用 `assumeIsolated`。
    //
    // 在 Swift 6 之下,閉包的寫法會得到 `sending 'self' risks causing data races`:
    // `assumeIsolated` 收的閉包會捕捉 `self`,而編譯器看不出「NSToolbarItem 的 action 只會從主執行緒
    // 抵達」。直接把這件事說出來既為真、也可被檢查,而 `@objc` 與 `@MainActor` 可以並存。
    @MainActor @objc func fire() {
        action()
    }
}
