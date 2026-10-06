@_spi(Backends) import SwiftCrossUI
import UIKit

/// The first view of the requested type at or below `view`.
///
/// **A view's widget is no longer always the control it names.** `TextField`
/// stopped being an elementary view when `TextFieldStyle` was opened up: its
/// body is `AnyView(style.makeView(...))`, so the widget on its node is a
/// `BaseViewWidget` and `widget.into()` as a `WrapperWidget<UITextField>` traps.
/// P4 died at launch on the simulator with "AnyWidget used with incompatible
/// widget type WrapperWidget<UITextField>; actual widget type is
/// BaseViewWidget", from an `.inspect` closure that is EMPTY on this platform.
///
/// The same defect and the same fix as AppKitBackend's; WinUIBackend has it too
/// and is the one machine that cannot be checked from here.
///
/// 在 `view` 或其子樹中,第一個屬於所要求型別的 view。
///
/// **一個 view 的 widget 已經不一定是它所命名的那個控制項了。** 當 `TextFieldStyle` 被開放出來時,
/// `TextField` 就不再是 elementary view:它的 body 是 `AnyView(style.makeView(...))`,因此它節點上的
/// widget 是 `BaseViewWidget`,而把 `widget.into()` 當成 `WrapperWidget<UITextField>` 會 trap。
/// P4 在模擬器上一啟動就死於「AnyWidget used with incompatible widget type
/// WrapperWidget<UITextField>; actual widget type is BaseViewWidget」——而那個 `.inspect` closure
/// 在這個平台上是**空的**。
///
/// 與 AppKitBackend 是同一個缺陷、同一個修法;WinUIBackend 也有,而那是這裡唯一檢查不到的機器。
private func scuiFirstDescendant<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
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
private func scuiDescribe(_ view: UIView, depth: Int = 0) -> String {
    let indent = String(repeating: "  ", count: depth)
    return ([indent + "\(type(of: view))"]
        + view.subviews.map { scuiDescribe($0, depth: depth + 1) }).joined(separator: "\n")
}

extension View {
    /// Inspects the native window that backs the window scene enclosing this view.
    public func inspectWindow(
        _ action: @escaping @MainActor @Sendable (UIWindow) -> Void
    ) -> some View {
        InspectWindowView(child: self, action: action)
    }
}

extension View {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (UIView) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints) { (view: any WidgetProtocol) in
            action(view.view)
        }
    }

    /// Runs `action` on the first `T` under this view's widget.
    ///
    /// Searching rather than casting is a strict generalisation: a widget that
    /// already holds the requested type is found by the first comparison.
    /// Loud when it finds nothing -- an `.inspect` that quietly did nothing
    /// would be worse than the trap it replaces.
    ///
    /// 在這個 view 的 widget 底下,對第一個 `T` 執行 `action`。
    ///
    /// 用「搜尋」而非「轉型」是一種嚴格的推廣:一個本來就持有所要求型別的 widget,在第一次比較就會
    /// 被找到。找不到時大聲失敗——一個「安靜地什麼都不做」的 `.inspect`,會比它所取代的那次 trap 更糟。
    nonisolated func scuiInspectFirst<T: UIView>(
        _ inspectionPoints: InspectionPoints,
        _ type: T.Type,
        _ action: @escaping @MainActor @Sendable (T) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints) {
            (widget: any WidgetProtocol, graph: [any WidgetProtocol]) in
            // The view graph too: at `.onCreate` the descendants are not in the
            // widget yet (see `InspectView.init(child:inspectionPoints:searching:)`).
            // 也搜尋 view graph:在 `.onCreate` 時子孫還不在 widget 底下。
            guard
                let match = scuiFirstDescendant(type, in: widget.view)
                    ?? graph.lazy.compactMap({ scuiFirstDescendant(type, in: $0.view) }).first
            else {
                fatalError(
                    "inspect: no \(T.self) at or below this view. The tree is:\n"
                        + scuiDescribe(widget.view)
                )
            }
            action(match)
        }
    }
}

extension Button {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (UIButton) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, UIButton.self, action)
    }
}

extension Text {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (UIKitBackend.TextView) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, UIKitBackend.TextView.self, action)
    }
}

extension Slider {
    @available(tvOS, unavailable)
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (UISlider) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, UISlider.self, action)
    }
}

// `Picker.inspect` was commented out upstream when pickers gained styles: the
// native control stopped being one type. Two forms now. The first names the
// control of the `.menu` style, so `.inspect { picker in ... }` keeps the
// meaning it had; the second takes the type, for the other styles --
// `UISegmentedControl` for `.segmented` (the default on tvOS), `UIStackView`
// for `.radioGroup`, `UIPickerView` for `.wheel` (`UITableView` under Mac
// Catalyst with the Mac idiom).
// Asking for a type the picker's style does not create stops with the widget
// tree, as every other `.inspect` here does. Restored 2026-10-06.
//
// 上游在 picker 加入樣式時把 `Picker.inspect` 註解掉了：原生控制項不再只有一種型別。現在有兩種形式。
// 第一種給 `.menu` 樣式的控制項，所以 `.inspect { picker in ... }` 維持原意；第二種帶型別參數，
// 給其他樣式用——`.segmented`(tvOS 的預設)是 `UISegmentedControl`,`.radioGroup` 是 `UIStackView`,`.wheel` 是 `UIPickerView`(Mac Catalyst 的 Mac 介面下是 `UITableView`)。要求的型別不是該樣式建立的，會印出 widget 樹並停止，與這裡其他 `.inspect` 相同。
// 2026-10-06 恢復。
extension SwiftCrossUI.Picker {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (UIButton) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, UIButton.self, action)
    }

    public func inspect<Control: UIView>(
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
        _ action: @escaping @MainActor @Sendable (UITextField) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, UITextField.self, action)
    }
}

extension ScrollView {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (UIScrollView) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, UIScrollView.self, action)
    }
}

extension List {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (UITableView) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, UITableView.self, action)
    }
}

extension NavigationSplitView {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (UISplitViewController) -> Void
    ) -> some View {
        InspectView(child: self, inspectionPoints: inspectionPoints) {
            (view: WrapperControllerWidget<UISplitViewController>) in
            action(view.child)
        }
    }
}

extension Image {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (UIImageView) -> Void
    ) -> some View {
        scuiInspectFirst(inspectionPoints, UIImageView.self, action)
    }
}
