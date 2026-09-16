import AppKit
@_spi(Backends) import SwiftCrossUI

/// The first view of the requested type at or below `view`.
///
/// **A view's widget is no longer always the control it names.** `TextField`
/// stopped being an elementary view when `TextFieldStyle` was opened up: its
/// body is now `AnyView(style.makeView(...))`, so the widget on its view-graph
/// node is a container and `widget.into()` as an `NSTextField` traps. P4 died
/// at launch on macOS with "AnyWidget used with incompatible widget type
/// NSTextField; actual widget type is AppKitHitTestingContainer" -- and the
/// app's own `.inspect` closure is empty on this platform, so the crash came
/// from a modifier that had nothing to do.
///
/// Searching rather than casting is a strict generalisation: a widget that IS
/// the requested type is returned by the first line, so nothing that worked
/// before changes.
///
/// 在 `view` 或其子樹中,第一個屬於所要求型別的 view。
///
/// **一個 view 的 widget 已經不一定是它所命名的那個控制項了。** 當 `TextFieldStyle` 被開放出來時,
/// `TextField` 就不再是 elementary view:它的 body 現在是 `AnyView(style.makeView(...))`,
/// 因此它 view graph 節點上的 widget 是一個容器,而把 `widget.into()` 當成 `NSTextField` 會 trap。
/// P4 在 macOS 上一啟動就死於「AnyWidget used with incompatible widget type NSTextField;
/// actual widget type is AppKitHitTestingContainer」——而那支 app 自己的 `.inspect` closure 在這個
/// 平台上是**空的**,所以那次崩潰來自一個根本沒事要做的 modifier。
///
/// 用「搜尋」而非「轉型」是一種嚴格的推廣:一個**本身就是**所要求型別的 widget 會在第一行就被回傳,
/// 因此先前能用的東西沒有任何改變。
private func scuiFirstDescendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let match = view as? T {
        return match
    }
    for subview in view.subviews {
        if let match = scuiFirstDescendant(type, in: subview) {
            return match
        }
    }
    return nil
}

/// The view tree under `view`, for when the search finds nothing.
/// 找不到時,`view` 底下那棵樹的樣子。
private func scuiDescribe(_ view: NSView, depth: Int = 0) -> String {
    let indent = String(repeating: "  ", count: depth)
    return ([indent + "\(type(of: view))"]
        + view.subviews.map { scuiDescribe($0, depth: depth + 1) }).joined(separator: "\n")
}

/// Runs `action` on the first `T` under this view's widget.
///
/// Loud when it finds nothing, not silent. An `.inspect` that quietly did
/// nothing would be worse than the trap it replaces: the closure is where an
/// app reaches the native control, and a hook that stops firing looks exactly
/// like a platform that stopped supporting something.
///
/// 在這個 view 的 widget 底下,對第一個 `T` 執行 `action`。
///
/// 找不到時大聲失敗,不沉默。一個「安靜地什麼都不做」的 `.inspect` 會比它所取代的那次 trap 更糟:
/// 那個 closure 正是一個 app 觸及原生控制項的地方,而一個不再觸發的掛鉤,看起來就跟
/// 「一個不再支援某件事的平台」一模一樣。
private func scuiInspecting<Child: View, T: NSView>(
    _ child: Child,
    _ inspectionPoints: InspectionPoints,
    _ type: T.Type,
    _ action: @escaping @MainActor @Sendable (T) -> Void
) -> InspectView<Child> {
    InspectView(child: child, inspectionPoints: inspectionPoints) { (view: NSView) in
        guard let match = scuiFirstDescendant(type, in: view) else {
            fatalError(
                "inspect: no \(T.self) at or below this view. The tree is:\n"
                    + scuiDescribe(view)
            )
        }
        action(match)
    }
}

extension View {
    /// Inspects the native window that backs the window scene enclosing this view.
    public func inspectWindow(
        _ action: @escaping @MainActor @Sendable (NSWindow) -> Void
    ) -> some View {
        InspectWindowView(child: self, action: action)
    }
}

extension View {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (NSView) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
    }
}

extension Button {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (NSButton) -> Void
    ) -> some View {
        scuiInspecting(self, inspectionPoints, NSButton.self, action)
    }
}

extension Text {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (NSTextField) -> Void
    ) -> some View {
        scuiInspecting(self, inspectionPoints, NSTextField.self, action)
    }
}

extension Slider {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (NSSlider) -> Void
    ) -> some View {
        scuiInspecting(self, inspectionPoints, NSSlider.self, action)
    }
}

// TODO(stackotter): Repair Picker.inspect implementations post PickerStyle refactor
// extension Picker {
//     public func inspect(
//         _ inspectionPoints: InspectionPoints = .onCreate,
//         _ action: @escaping @MainActor @Sendable (NSPopUpButton) -> Void
//     ) -> some View {
//         InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
//     }
// }

extension TextField {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (NSTextField) -> Void
    ) -> some View {
        scuiInspecting(self, inspectionPoints, NSTextField.self, action)
    }
}

extension ScrollView {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (NSScrollView) -> Void
    ) -> some View {
        scuiInspecting(self, inspectionPoints, NSScrollView.self, action)
    }
}

extension List {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (NSTableView) -> Void
    ) -> some View {
        scuiInspecting(self, inspectionPoints, NSTableView.self, action)
    }
}

extension NavigationSplitView {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (NSSplitView) -> Void
    ) -> some View {
        scuiInspecting(self, inspectionPoints, NSSplitView.self, action)
    }
}

extension Image {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (NSImageView) -> Void
    ) -> some View {
        scuiInspecting(self, inspectionPoints, NSImageView.self, action)
    }
}

extension Table {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (NSScrollView) -> Void
    ) -> some View {
        scuiInspecting(self, inspectionPoints, NSScrollView.self, action)
    }
}
