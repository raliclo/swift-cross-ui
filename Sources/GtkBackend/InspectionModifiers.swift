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
    /// The signature still hands over a `Gtk.ListBox`, and that is deliberate:
    /// the widget changed, the inspection contract did not.
    ///
    /// Since #117 a `List` is a `GtkScrolledWindow` wrapping the list box, so
    /// this unwraps one level -- the same shape `NavigationSplitView` above has
    /// used since it started returning a `Gtk.Fixed`. Passing the scrolled
    /// window through instead would have been a source break for every caller,
    /// to expose a wrapper nobody asked to inspect.
    ///
    /// 簽章依然交出一個 `Gtk.ListBox`，而那是刻意的：改變的是 widget，不是這份 inspection 的約定。
    ///
    /// 自 #117 起，一個 `List` 是包住 list box 的 `GtkScrolledWindow`，因此此處往內拆一層——與上方
    /// `NavigationSplitView` 自從改為回傳 `Gtk.Fixed` 之後所採用的形狀相同。改為直接把 scrolled
    /// window 傳出去，會為了暴露一個沒有人要求檢視的外包層，而讓每一個呼叫端都編不過。
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.ListBox) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints) {
            (view: Gtk.ScrolledWindow) in
            action(view.getChild() as! Gtk.ListBox)
        }
    }
}

extension NavigationSplitView {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.Paned) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints) { (view: Gtk.Fixed) in
            action(view.children[0] as! Gtk.Paned)
        }
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
