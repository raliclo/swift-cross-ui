import Gtk
@_spi(Backends) import SwiftCrossUI

/// The first widget of the requested type at or below `widget`.
///
/// **The same defect queue M8 recorded for AppKit, UIKit and WinUI, on a fourth
/// backend M8 did not list.** Measured 2026-09-17 on Windows -gtk4: P4 died at
/// launch with "AnyWidget used with incompatible widget type Entry; actual
/// widget type is PassthroughFixed" (exit 132), from a `TextField(...).inspect`
/// whose closure body is empty on this backend. `TextField` renders through
/// `TextFieldStyle`, so the widget on its node is a container and the Entry is
/// inside it.
///
/// Walked through the child records the Gtk module keeps on the Swift side --
/// `Fixed.children`, `Box.children`, the single child of ScrolledWindow and
/// Viewport, and both panes of a Paned -- rather than GTK's own
/// first-child/next-sibling list. Those are the Swift wrapper objects, so `as?`
/// answers the type question directly, which a raw GtkWidget pointer cannot.
///
/// 在 `widget` 或其子樹中,第一個屬於所要求型別的 widget。
///
/// **這是 queue M8 為 AppKit、UIKit、WinUI 記下的同一個缺陷,出現在 M8 沒有列到的第四個 backend。**
/// 2026-09-17 於 Windows -gtk4 實測:P4 一啟動就死於「AnyWidget used with incompatible widget type
/// Entry; actual widget type is PassthroughFixed」(exit 132),來源是一個在本 backend 上 closure 內容為
/// **空**的 `TextField(...).inspect`。`TextField` 經由 `TextFieldStyle` 繪製,因此節點上的 widget 是
/// 容器,Entry 在它裡面。
///
/// 走訪的是 Gtk 模組在 Swift 端保存的子節點紀錄——`Fixed.children`、`Box.children`、ScrolledWindow 與
/// Viewport 的單一子節點、Paned 的兩側——而不是 GTK 自己的 first-child/next-sibling 清單。那些是 Swift
/// 包裝物件,`as?` 能直接回答型別問題,而原始的 GtkWidget 指標做不到。
private func scuiFirstDescendant<T: Gtk.Widget>(_ type: T.Type, in widget: Gtk.Widget) -> T? {
    if let match = widget as? T {
        return match
    }
    for child in scuiChildren(of: widget) {
        if let match = scuiFirstDescendant(type, in: child) {
            return match
        }
    }
    return nil
}

private func scuiChildren(of widget: Gtk.Widget) -> [Gtk.Widget] {
    if let fixed = widget as? Gtk.Fixed {
        return fixed.children
    }
    if let box = widget as? Gtk.Box {
        return box.children
    }
    if let scrolled = widget as? Gtk.ScrolledWindow {
        return scrolled.getChild().map { [$0] } ?? []
    }
    if let viewport = widget as? Gtk.Viewport {
        return viewport.getChild().map { [$0] } ?? []
    }
    if let paned = widget as? Gtk.Paned {
        return [paned.startChild, paned.endChild].compactMap { $0 }
    }
    return []
}

/// The tree under `widget`, for the failure message.
/// 找不到時,`widget` 底下那棵樹的樣子。
private func scuiDescribe(_ widget: Gtk.Widget, depth: Int = 0) -> String {
    let indent = String(repeating: "  ", count: depth)
    return ([indent + "\(type(of: widget))"]
        + scuiChildren(of: widget).map { scuiDescribe($0, depth: depth + 1) })
        .joined(separator: "\n")
}

extension View {
    /// Runs `action` on the first `T` under this view's widget. Loud when it
    /// finds nothing: an `.inspect` that quietly did nothing would be worse
    /// than the trap it replaces.
    /// 在這個 view 的 widget 底下,對第一個 `T` 執行 `action`。找不到時大聲失敗:安靜地什麼都不做的
    /// `.inspect`,會比它所取代的 trap 更糟。
    nonisolated func scuiInspectFirst<T: Gtk.Widget>(
        _ inspectionPoints: InspectionPoints,
        _ type: T.Type,
        _ action: @escaping @MainActor @Sendable (T) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints) { (widget: Gtk.Widget) in
            guard let match = scuiFirstDescendant(type, in: widget) else {
                fatalError(
                    "inspect: no \(T.self) at or below this view. The tree is:\n"
                        + scuiDescribe(widget)
                )
            }
            action(match)
        }
    }
}

extension View {
    /// Inspects the native window that backs the window scene enclosing this view.
    public func inspectWindow(
        _ action: @escaping @MainActor @Sendable (Gtk.ApplicationWindow) -> Void
    ) -> some View {
        InspectWindowView(child: self, action: action)
    }
}

extension View {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.Widget) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
    }
}

extension SwiftCrossUI.Button {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.Button) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, Gtk.Button.self, action)
    }
}

extension Text {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.Label) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, Gtk.Label.self, action)
    }
}

extension Slider {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.Scale) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, Gtk.Scale.self, action)
    }
}

// TODO(stackotter): Repair Picker.inspect implementations post PickerStyle refactor
// extension Picker {
//     public func inspect(
//         _ inspectionPoints: InspectionPoints = .onCreate,
//         _ action: @escaping @MainActor @Sendable (Gtk.DropDown) -> Void
//     ) -> some View {
//         InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
//     }
// }

extension TextField {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.Entry) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, Gtk.Entry.self, action)
    }
}

extension ScrollView {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.ScrolledWindow) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, Gtk.ScrolledWindow.self, action)
    }
}

extension List {
    /// `Gtk.ListView`, not `Gtk.ListBox`, and the old signature TRAPPED.
    ///
    /// It used to hand over a `Gtk.ListBox`, unwrapped from a `ScrolledWindow`
    /// with a forced cast, under a comment saying "the widget changed, the
    /// inspection contract did not". #117 then replaced the list box with GTK's
    /// native lazy `GtkListView`, and nothing ran this overload afterwards.
    /// Driven for the first time on 2026-09-18 by `P4 --inspect-containers`, it
    /// died at launch with "Could not cast value of type 'Gtk.ListView' to
    /// 'Gtk.ListBox'". A contract that cannot be honoured is not a contract:
    /// there is no list box to hand over any more.
    ///
    /// The search shape is the one queue M8 gave every other overload, so a
    /// later change of wrapper does not trap again.
    ///
    /// 交出的是 `Gtk.ListView` 而不是 `Gtk.ListBox`,而舊的簽章會**trap**。
    ///
    /// 它原本以強制轉型從 `ScrolledWindow` 拆出一個 `Gtk.ListBox`,並在註解裡寫著「改變的是 widget,不是這份
    /// inspection 的約定」。其後 #117 以 GTK 原生的 lazy `GtkListView` 取代了 list box,而此後沒有任何東西跑過
    /// 這個 overload。2026-09-18 首次以 `P4 --inspect-containers` 驅動,它一啟動就死於「Could not cast value of
    /// type 'Gtk.ListView' to 'Gtk.ListBox'」。**一個無法被遵守的約定不是約定**:那個 list box 已經不存在了。
    ///
    /// 搜尋的形狀與 queue M8 給其他所有 overload 的相同,好讓外包層日後再變也不會再 trap。
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.ListView) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, Gtk.ListView.self, action)
    }
}

extension NavigationSplitView {
    /// Searched rather than `view.children[0] as! Gtk.Paned`, for the reason the
    /// `List` overload above records: the forced version of that cast trapped
    /// the first time anything ran it.
    /// 改為搜尋而非 `view.children[0] as! Gtk.Paned`,理由見上方 `List` overload:那種強制轉型的版本,在第一次
    /// 真的被執行時就 trap 了。
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.Paned) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, Gtk.Paned.self, action)
    }
}

extension SwiftCrossUI.Image {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.Picture) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints) {
            (_: Gtk.Widget, children: ImageChildren) in
            action(children.imageWidget.into())
        }
    }
}

extension HStack {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.Fixed) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
    }
}

extension VStack {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.Fixed) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
    }
}

extension ZStack {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.Fixed) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
    }
}

extension Group {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.Fixed) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
    }
}

extension Shape {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.DrawingArea) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, Gtk.DrawingArea.self, action)
    }
}
