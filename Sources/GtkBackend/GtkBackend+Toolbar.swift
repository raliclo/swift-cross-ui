import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

/// A `GtkHeaderBar` installed as the window's titlebar, holding one
/// `GtkButton` per ``ToolbarItem``.
///
/// **How `Placement` is mapped, which the protocol asks each backend to say.**
/// A header bar has two packing regions and a centre reserved for the title, so
/// the mapping is by region rather than by order: `.leading` packs to the start,
/// and `.primary`, `.trailing` and `.automatic` pack to the end. Putting
/// `.automatic` at the end is a reading of GNOME's convention, where the start
/// holds navigation (back, sidebar) and actions collect on the right; it is not
/// something GTK enforces. Within a region, items keep the order they were
/// given.
///
/// **This takes over the window's decoration, and that is not free.** GTK draws
/// its own titlebar until something calls `gtk_window_set_titlebar`, and that
/// default is not a widget anyone can query or pack into. Measured 2026-09-04
/// on P16 asking for 900x600: GTK's own decoration costs **39px** and a
/// `GtkHeaderBar` installed in its place measures **47** -- the window becomes
/// 8px taller. ``Gtk/Window/installMeasurableTitlebar()`` exists for the same
/// reason and is deliberately NOT called by default, because paying permanent
/// chrome on every window to fix a 39px shortfall is a decision rather than a
/// patch (see task #79).
///
/// Here that cost is accepted, and the difference is consent: a window only
/// reaches this code because its view asked for a toolbar. A window that asks
/// for no toolbar never has its titlebar replaced.
///
/// 以一個 `GtkHeaderBar` 裝設為視窗的 titlebar，其中每個 ``ToolbarItem`` 對應一個 `GtkButton`。
///
/// **`Placement` 的對應方式——協定要求每個 backend 說明這一點。** header bar 有兩個 packing 區域，
/// 中央則保留給標題，因此此處是「依區域」而非「依順序」對應：`.leading` pack 到 start，而 `.primary`、
/// `.trailing` 與 `.automatic` 都 pack 到 end。把 `.automatic` 放在 end 是對 GNOME 慣例的一種解讀
/// ——start 放的是導覽（返回、側邊欄），動作則集中在右側；那並不是 GTK 強制的規定。同一區域內，項目
/// 維持給定的順序。
///
/// **這會接管視窗的裝飾，而那不是免費的。** 在有東西呼叫 `gtk_window_set_titlebar` 之前，GTK 畫的是
/// 它自己的 titlebar，而那份預設裝飾並不是任何人能查詢、也不能 pack 東西進去的 widget。2026-09-04
/// 在 P16 要求 900x600 的情況下實測：GTK 自身的裝飾為 **39px**，而裝在它位置上的 `GtkHeaderBar`
/// 量得 **47**——視窗因此高了 8px。``Gtk/Window/installMeasurableTitlebar()`` 基於同樣的理由存在，
/// 且刻意不預設呼叫，因為「為了修正 39px 的短少而在每個視窗上永久付出額外裝飾」是一項決策，不是一個
/// 補丁（見 task #79）。
///
/// 在此處這個代價被接受了，差別在於**同意**：一個視窗之所以會走到這段程式碼，是因為它的 view 要求了
/// 工具列。沒有要求工具列的視窗，其 titlebar 永遠不會被替換。
///
/// 本檔為不帶 conformance 的 `extension`：`BackendFeatures.Toolbars` 已列於 `GtkBackend.swift` 的
/// 類別宣告中，兩處都寫會得到 `error: redundant conformance`。
extension GtkBackend {
    public func setToolbar(ofWindow window: Window, to items: [ToolbarItem]) {
        let key = ObjectIdentifier(window)

        // An empty list removes the toolbar AND gives the decoration back to
        // GTK. Passing nil to `gtk_window_set_titlebar` is what restores the
        // platform titlebar; leaving an empty header bar installed would keep
        // the 47px and show a bar with nothing in it.
        // 空清單會移除工具列，**並把裝飾交還給 GTK**。把 nil 傳給 `gtk_window_set_titlebar` 才是
        // 恢復平台 titlebar 的方式；若只是留下一個空的 header bar，那 47px 仍會被計入，而且會顯示
        // 一條什麼都沒有的橫條。
        guard !items.isEmpty else {
            toolbarButtons[key] = nil
            window.setHeaderBar(leading: [], trailing: [])
            return
        }

        var buttons: [Gtk.Button] = []
        var leading: [Gtk.Widget] = []
        var trailing: [Gtk.Widget] = []

        for item in items {
            let button = makeToolbarButton(for: item)
            buttons.append(button)

            switch item.placement {
                case .leading:
                    leading.append(button)
                case .primary, .trailing, .automatic:
                    trailing.append(button)
            }
        }

        // Stored before the bar is installed, not after: installing a titlebar
        // can realise the widget and emit signals, and a handler firing against
        // a table that has not been written yet is a race with no error attached.
        // 在裝上 bar 之前就先存起來，而不是之後：裝設 titlebar 可能會 realise 該 widget 並發出訊號，
        // 而一個對「尚未寫入的表」觸發的 handler，是一場不會伴隨任何錯誤的競態。
        toolbarButtons[key] = buttons
        window.setHeaderBar(leading: leading, trailing: trailing)
    }

    /// One `GtkButton`, iconed where the symbol table has a name the running
    /// icon theme actually ships.
    ///
    /// The icon is resolved through ``GtkBackend/availableIconName(for:)``, the
    /// same path `Image(systemName:)` uses, so a toolbar and a button asking for
    /// "trash" get the same glyph. That resolver asks `gtk_icon_theme_has_icon`
    /// rather than trusting the name: measured 2026-09-07 against GTK 4.22.4, of
    /// the 36 catalogued names **0 resolve as written and 15 resolve with the
    /// `-symbolic` suffix**, because GTK 4 ships the symbolic family and not the
    /// legacy full-colour set.
    ///
    /// When there is no icon the button falls back to its label rather than to
    /// ``SystemSymbol/textFallback``. That differs from ``updateSymbolView`` on
    /// purpose: a symbol view has nothing but the glyph, so it must draw the
    /// fallback or draw nothing, whereas a toolbar item always carries a label
    /// and drawing both would show the same idea twice.
    ///
    /// 一個 `GtkButton`；當符號表給的名稱確實存在於執行中的 icon theme 時，帶上圖示。
    ///
    /// 圖示透過 ``GtkBackend/availableIconName(for:)`` 解析，與 `Image(systemName:)` 走同一條路，
    /// 因此「工具列」與「按鈕」要求 "trash" 時會得到同一個字符。該解析器會詢問
    /// `gtk_icon_theme_has_icon` 而非信任名稱：2026-09-07 對 GTK 4.22.4 實測，已編目的 36 個名稱中
    /// **純名稱 0 個解析成功、加上 `-symbolic` 後綴則有 15 個**——因為 GTK 4 出貨的是 symbolic 家族，
    /// 而非舊有的全彩集。
    ///
    /// 沒有圖示時，按鈕退回顯示它的**標籤**，而不是 ``SystemSymbol/textFallback``。這與
    /// ``updateSymbolView`` 的做法刻意不同：symbol view 除了字符之外一無所有，因此它只能畫退路、
    /// 否則就是一片空白；而工具列項目本來就帶著標籤，兩者都畫等於把同一個意思顯示兩次。
    private func makeToolbarButton(for item: ToolbarItem) -> Gtk.Button {
        let iconName = item.systemImage
            .flatMap { SystemSymbol.named($0) }
            .flatMap { GtkBackend.availableIconName(for: $0) }

        let button: Gtk.Button
        if let iconName {
            button = Gtk.Button(iconName: iconName)
        } else {
            button = Gtk.Button()
            button.label = item.label
        }

        // The label is set as the tooltip on the iconed path so the control is
        // still identifiable, and is what an accessibility tool reads.
        // 走圖示路徑時把標籤設為 tooltip，讓該控制項仍然可被辨識，也是無障礙工具會讀到的內容。
        if iconName != nil {
            gtk_widget_set_tooltip_text(button.widgetPointer, item.label)
        }

        button.sensitive = item.isEnabled

        let action = item.action
        button.clicked = { _ in MainActor.assumeIsolated { action() } }

        return button
    }
}
