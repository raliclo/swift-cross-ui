import Gtk
@_spi(Backends) import SwiftCrossUI

/// The first widget of the requested type at or below `widget`.
///
/// **Searched, not cast.** The widget on a view's node is often a container:
/// `TextField` renders through `TextFieldStyle`, so its node holds a
/// PassthroughFixed with the Entry inside, and a direct cast killed P4 at
/// launch on Windows -gtk4 ("AnyWidget used with incompatible widget type
/// Entry; actual widget type is PassthroughFixed", exit 132, 2026-09-17).
///
/// Walked through the child records the Gtk module keeps on the Swift side --
/// `Fixed.children`, `Box.children`, the single child of ScrolledWindow and
/// Viewport, and both panes of a Paned -- rather than GTK's own
/// first-child/next-sibling list. Those are the Swift wrapper objects, so `as?`
/// answers the type question directly, which a raw GtkWidget pointer cannot.
///
/// 在 `widget` 或其子樹中,第一個屬於所要求型別的 widget。
///
/// **以搜尋取得，而非轉型。** view 節點上的 widget 常是一個容器:`TextField` 經由 `TextFieldStyle` 繪製,
/// 因此節點上是一個 PassthroughFixed,Entry 在它裡面；直接轉型曾讓 P4 在 Windows -gtk4 一啟動就死於
/// 「AnyWidget used with incompatible widget type Entry; actual widget type is PassthroughFixed」
/// (exit 132,2026-09-17)。
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
        InspectView(child: self, inspectionPoints: inspectionPoints) {
            (widget: Gtk.Widget, graph: [Gtk.Widget]) in
            // The view graph too: at `.onCreate` the descendants are not in the
            // widget yet (see `InspectView.init(child:inspectionPoints:searching:)`).
            // 也搜尋 view graph:在 `.onCreate` 時子孫還不在 widget 底下。
            guard
                let match = scuiFirstDescendant(type, in: widget)
                    ?? graph.lazy.compactMap({ scuiFirstDescendant(type, in: $0) }).first
            else {
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

// `Picker.inspect` was commented out upstream when pickers gained styles: the
// native control stopped being one type. Two forms now. The first names the
// control of the `.menu` style, so `.inspect { picker in ... }` keeps the
// meaning it had; the second takes the type, for the other styles --
// `Gtk.Widget` for `.segmented` and `.radioGroup`, whose controls are this
// backend's own boxes.
// Asking for a type the picker's style does not create stops with the widget
// tree, as every other `.inspect` here does.
//
// 上游在 picker 加入樣式時把 `Picker.inspect` 註解掉了：原生控制項不再只有一種型別。現在有兩種形式。
// 第一種給 `.menu` 樣式的控制項，所以 `.inspect { picker in ... }` 維持原意；第二種帶型別參數，
// 給其他樣式用——`.segmented` 與 `.radioGroup` 用 `Gtk.Widget`,它們是本 backend 自己的 box。要求的型別不是該樣式建立的，會印出 widget 樹並停止，與這裡其他 `.inspect` 相同。
extension Picker {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (Gtk.DropDown) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, Gtk.DropDown.self, action)
    }

    public func inspect<Control: Gtk.Widget>(
        _ inspectionPoints: InspectionPoints = .onCreate,
        as type: Control.Type,
        _ action: @escaping @MainActor @Sendable (Control) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, type, action)
    }
}

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
    /// `Gtk.ListView`, the native lazy list #117 put inside the
    /// `ScrolledWindow`; there is no `Gtk.ListBox` to hand over. Searched rather
    /// than unwrapped with a forced cast, which trapped at launch ("Could not
    /// cast value of type 'Gtk.ListView' to 'Gtk.ListBox'", `P4
    /// --inspect-containers`, 2026-09-18) once the wrapper changed.
    ///
    /// 交出的是 `Gtk.ListView`,即 #117 放進 `ScrolledWindow` 的原生 lazy 清單;沒有 `Gtk.ListBox` 可交。以搜尋
    /// 取得，而非以強制轉型拆出——外包層一改變，那種轉型就在啟動時 trap(「Could not cast value of type
    /// 'Gtk.ListView' to 'Gtk.ListBox'」,`P4 --inspect-containers`,2026-09-18)。
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
