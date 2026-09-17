@_spi(Backends) import SwiftCrossUI
import WinUI

/// The first element of the requested type at or below `element`.
///
/// **A view's widget is no longer always the control it names**, and on this
/// backend that trapped at launch. Measured 2026-09-17: P4 on WinUI died with
/// "AnyWidget used with incompatible widget type TextBox; actual widget type is
/// Canvas" (exit 132) from `TextField(...).inspect(.afterUpdate) { ... }`.
/// `TextField`'s body goes through `TextFieldStyle`, so the widget on its node
/// is the Canvas container every widget here is wrapped in, and the TextBox is
/// inside it. AppKitBackend and UIKitBackend had the same defect and the same
/// fix (queue M8); this was the one machine that could not be checked from there.
///
/// Logical children first, then the visual tree. `.onCreate` runs before the
/// widget is attached, when VisualTreeHelper can still report no children for a
/// Panel, so a Panel's `children`, a Border's `child` and a ContentControl's
/// `content` are walked directly. Controls such as ListView keep their parts in
/// a template, which only the visual tree reaches. A Panel or Border is not ALSO
/// walked visually, since its visual children are the same elements and each
/// level would be searched twice. The `as?` casts on elements read back this way
/// are the ones WinUIBackend+Focus.swift already relies on, driven in P70.
///
/// 在 `element` 或其子樹中,第一個屬於所要求型別的元素。
///
/// **一個 view 的 widget 已經不一定是它所命名的那個控制項了**,而在這個 backend 上,那會在啟動時 trap。
/// 2026-09-17 實測:P4 在 WinUI 上死於「AnyWidget used with incompatible widget type TextBox;
/// actual widget type is Canvas」(exit 132),來源是 `TextField(...).inspect(.afterUpdate) { ... }`。
/// `TextField` 的 body 經過 `TextFieldStyle`,因此它節點上的 widget 是本 backend 包住每個 widget 的
/// Canvas 容器,TextBox 在它裡面。AppKitBackend 與 UIKitBackend 有同一個缺陷、同一個修法(queue M8);
/// 這是那邊唯一檢查不到的機器。
///
/// 先走邏輯子節點,再走 visual tree。`.onCreate` 在 widget 掛上之前執行,那時 VisualTreeHelper 對 Panel
/// 可能還回報沒有子節點,所以 Panel 的 `children`、Border 的 `child`、ContentControl 的 `content` 直接走。
/// ListView 之類的控制項把零件放在 template 裡,只有 visual tree 走得到。Panel 或 Border **不會再**走一次
/// visual tree,因為它的 visual 子節點就是同一批元素,每一層都會被搜兩次。以這種方式讀回的元素做 `as?`
/// 轉型,與 WinUIBackend+Focus.swift 已經依賴、並在 P70 驅動過的是同一種。
private func scuiFirstDescendant<T: WinUI.UIElement>(
    _ type: T.Type,
    in element: WinUI.UIElement
) -> T? {
    if let match = element as? T {
        return match
    }
    for child in scuiChildren(of: element) {
        if let match = scuiFirstDescendant(type, in: child) {
            return match
        }
    }
    return nil
}

private func scuiChildren(of element: WinUI.UIElement) -> [WinUI.UIElement] {
    if let panel = element as? WinUI.Panel {
        return (0..<panel.children.size).compactMap { panel.children.getAt($0) }
    }
    if let border = element as? WinUI.Border {
        return border.child.map { [$0] } ?? []
    }
    var children: [WinUI.UIElement] = []
    if let dependencyObject = element as? WinUI.DependencyObject {
        let count = VisualTreeHelper.getChildrenCount(dependencyObject)
        for index in 0..<count {
            if let child = VisualTreeHelper.getChild(dependencyObject, index) as? WinUI.UIElement {
                children.append(child)
            }
        }
    }
    if children.isEmpty, let control = element as? WinUI.ContentControl,
        let content = control.content as? WinUI.UIElement
    {
        children.append(content)
    }
    return children
}

/// The tree under `element`, for the failure message.
/// 找不到時,`element` 底下那棵樹的樣子。
private func scuiDescribe(_ element: WinUI.UIElement, depth: Int = 0) -> String {
    let indent = String(repeating: "  ", count: depth)
    return ([indent + "\(type(of: element))"]
        + scuiChildren(of: element).map { scuiDescribe($0, depth: depth + 1) })
        .joined(separator: "\n")
}

extension View {
    /// Runs `action` on the first `T` under this view's widget.
    ///
    /// Searching rather than casting is a strict generalisation: a widget that
    /// already is a `T` is found by the first comparison, so the stack and shape
    /// overloads, whose widget really is the requested type, behave as before.
    /// Loud when it finds nothing -- an `.inspect` that quietly did nothing would
    /// be worse than the trap it replaces.
    ///
    /// 在這個 view 的 widget 底下,對第一個 `T` 執行 `action`。
    ///
    /// 用「搜尋」而非「轉型」是嚴格的推廣:本身就是 `T` 的 widget 在第一次比較就會被找到,因此 widget
    /// 確實就是所要求型別的 stack 與 shape overload,行為不變。找不到時大聲失敗——一個安靜地什麼都不做的
    /// `.inspect`,會比它所取代的那次 trap 更糟。
    nonisolated func scuiInspectFirst<T: WinUI.UIElement>(
        _ inspectionPoints: InspectionPoints,
        _ type: T.Type,
        _ action: @escaping @MainActor @Sendable (T) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints) {
            (widget: WinUI.FrameworkElement) in
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
        _ action: @escaping @MainActor @Sendable (WinUI.Window) -> Void
    ) -> some View {
        InspectWindowView(child: self, action: action)
    }
}

extension View {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.FrameworkElement) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
    }
}

extension SwiftCrossUI.Button {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.Button) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, WinUI.Button.self, action)
    }
}

extension Text {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.TextBlock) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, WinUI.TextBlock.self, action)
    }
}

extension SwiftCrossUI.Slider {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.Slider) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, WinUI.Slider.self, action)
    }
}

// TODO(stackotter): Repair Picker.inspect implementations post PickerStyle refactor
// extension Picker {
//     public func inspect(
//         _ inspectionPoints: InspectionPoints = .onCreate,
//         _ action: @escaping @MainActor @Sendable (WinUI.ComboBox) -> Void
//     ) -> some View {
//         InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
//     }
// }

extension TextField {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.TextBox) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, WinUI.TextBox.self, action)
    }
}

extension SwiftCrossUI.ScrollView {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.ScrollViewer) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, WinUI.ScrollViewer.self, action)
    }
}

extension List {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.ListView) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, WinUI.ListView.self, action)
    }
}

extension NavigationSplitView {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.SplitView) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, WinUI.SplitView.self, action)
    }
}

extension SwiftCrossUI.Image {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.Image) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints) {
            (_: WinUI.FrameworkElement, children: ImageChildren) in
            action(children.imageWidget.into())
        }
    }
}

extension HStack {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.Canvas) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
    }
}

extension VStack {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.Canvas) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
    }
}

extension ZStack {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.Canvas) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
    }
}

extension Group {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.Canvas) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
    }
}

extension SwiftCrossUI.Shape {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (WinUI.Path) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, WinUI.Path.self, action)
    }
}
