import WinUI
import WinAppSDK
@_spi(Backends) import SwiftCrossUI

/// A row of buttons in the window's own grid, built from ``ToolbarItem``.
///
/// **How `Placement` is mapped, which the protocol asks each backend to say.**
/// The row is a single horizontal `StackPanel` with no leading or trailing
/// regions of its own, so placement decides ORDER rather than side: `.leading`
/// first, then `.automatic`, then `.primary`, then `.trailing`. That is the same
/// reading ``AppKitBackend`` records for `NSToolbar`, and it is deliberate that
/// the two agree -- a toolbar written once should not reorder itself when the
/// app is rebuilt for the other desktop.
///
/// **Why this is not a `CommandBar`.** ``ToolbarItem`` names `CommandBar` as the
/// WinUI shape, and it would be the right control -- it is simply not in the
/// bindings this backend compiles against. See ``CustomWindow/toolbar`` for the
/// search that established that, including the positive control that makes the
/// absences real. If a future swift-winui does ship `CommandBar`, the mapping
/// gains a genuine primary/secondary distinction and this comment is the note
/// saying what to change.
///
/// 視窗自身 grid 中的一列按鈕，由 ``ToolbarItem`` 建成。
///
/// **`Placement` 的對應方式——協定要求每個 backend 說明這一點。** 這一列是單一水平 `StackPanel`，
/// 本身沒有前緣或後緣區域，因此 placement 決定的是**順序**而非側邊：`.leading` 在前，接著
/// `.automatic`、`.primary`，最後 `.trailing`。這與 ``AppKitBackend`` 為 `NSToolbar` 所記錄的解讀
/// 相同，而兩者一致是刻意的——一份寫好的工具列，不該因為改為另一個桌面環境重新建置就自行重排。
///
/// **為何不是 `CommandBar`。** ``ToolbarItem`` 把 `CommandBar` 指為 WinUI 的對應形狀，而它確實會是
/// 正確的控制項——它只是不存在於本 backend 所編譯依據的那組綁定中。確立此事的搜尋（含使那些缺席
/// 成立的正對照）記於 ``CustomWindow/toolbar``。若日後的 swift-winui 確實提供了 `CommandBar`，
/// 該對應就會獲得真正的「主要／次要」區分，而本註解即是說明屆時要改什麼的那份備註。
extension WinUIBackend {
    public func setToolbar(ofWindow window: Window, to items: [ToolbarItem], title _: String?) {
        // `title` is ignored here on purpose. This platform puts a heading in
        // the window's title bar, and `setTitle(ofWindow:to:)` has already put
        // it there -- writing it again would be the same string twice.
        // 此處刻意忽略 `title`。這個平台把標題放在視窗的標題列中,而 `setTitle(ofWindow:to:)` 已經把它
        // 放進去了——再寫一次只會是同一個字串出現兩次。
        // Rebuilt wholesale rather than diffed. `ToolbarItem`'s `==` covers
        // everything visible precisely so a caller can decide whether to call
        // this at all; deciding again here would duplicate that judgement in a
        // second place, where it could disagree.
        // 整條重建，而不做差異比對。``ToolbarItem`` 的 `==` 之所以涵蓋所有看得見的部分，正是為了讓
        // 呼叫端能判斷「是否需要呼叫本函式」；在此再判斷一次，等於把同一個判斷複製到第二個地方，
        // 而那兩處可能互相矛盾。
        window.toolbar.children.clear()

        guard !items.isEmpty else {
            window.setToolbarVisible(false)
            return
        }

        let ordered = items.sorted { lhs, rhs in
            Self.order(of: lhs.placement) < Self.order(of: rhs.placement)
        }

        for item in ordered {
            window.toolbar.children.append(makeToolbarButton(for: item))
        }

        window.setToolbarVisible(true)
    }

    private static func order(of placement: ToolbarItem.Placement) -> Int {
        switch placement {
            case .leading: 0
            case .automatic: 1
            case .primary: 2
            case .trailing: 3
        }
    }

    /// One `CustomButton`, iconed from the Segoe column of the symbol table.
    ///
    /// The click handler goes through `internalState.buttonClickActions`, the
    /// same table ``createSimpleButton()`` uses, rather than capturing the
    /// action in the closure directly. That is not incidental: `click.addHandler`
    /// retains what it captures for the lifetime of the button, so capturing the
    /// action would keep the view's closure -- and whatever it closes over --
    /// alive for as long as the toolbar exists.
    ///
    /// The glyph is drawn as TEXT in the icon font, which is what a Segoe icon
    /// is: a Private Use Area code point. ``WinUIBackend/iconFontFamilies``
    /// names two families, not one, because Segoe Fluent Icons ships with
    /// Windows 11 and is absent from a default Windows 10 -- the fallback family
    /// is what stops the button rendering an empty box there.
    ///
    /// When there is no catalogued glyph the button shows its label instead of
    /// ``SystemSymbol/textFallback``, matching what GtkBackend does and for the
    /// same reason: a toolbar item already carries a label, so drawing the
    /// fallback too would say the same thing twice.
    ///
    /// 一個 `CustomButton`，圖示取自符號表的 Segoe 欄。
    ///
    /// 點擊 handler 走的是 `internalState.buttonClickActions`——與 ``createSimpleButton()`` 同一張表
    /// ——而不是直接在 closure 中捕捉該 action。這不是隨意的選擇：`click.addHandler` 會在按鈕的整個
    /// 生命週期內持有它所捕捉之物，因此若直接捕捉 action，就會讓 view 的 closure（以及它所閉包的一切）
    /// 存活到工具列消失為止。
    ///
    /// 字符是以圖示字型繪製的**文字**，而 Segoe 圖示本來就是這樣的東西：一個 Private Use Area 的碼位。
    /// ``WinUIBackend/iconFontFamilies`` 指名兩個家族而非一個，因為 Segoe Fluent Icons 隨 Windows 11
    /// 出貨，在預設安裝的 Windows 10 上並不存在——備援家族正是讓按鈕在該系統上不會畫出空方框的東西。
    ///
    /// 當符號表沒有編目字符時，按鈕顯示的是它的標籤，而非 ``SystemSymbol/textFallback``；這與
    /// GtkBackend 的做法一致，理由也相同：工具列項目本來就帶著標籤，連退路一起畫等於把同一件事說兩次。
    private func makeToolbarButton(for item: ToolbarItem) -> CustomButton {
        let button = CustomButton()
        button.content = button.label

        let symbol = item.systemImage.flatMap { SystemSymbol.named($0) }
        if let symbol, symbol.segoeScalar != 0 {
            button.label.text = symbol.segoeGlyph
            button.label.fontFamily = FontFamily(Self.iconFontFamilies)
        } else {
            button.label.text = item.label
        }

        button.isEnabled = item.isEnabled

        let action = item.action
        internalState.buttonClickActions[ObjectIdentifier(button)] = {
            MainActor.assumeIsolated { action() }
        }
        button.click.addHandler { [weak internalState] _, _ in
            guard let internalState else { return }
            internalState.buttonClickActions[ObjectIdentifier(button)]?()
        }

        return button
    }
}
