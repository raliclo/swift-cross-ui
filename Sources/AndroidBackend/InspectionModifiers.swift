import AndroidKit
@_spi(Backends) import SwiftCrossUI
import SwiftJava

/// The first view at or below `view` that is a `T`, in Java's sense.
///
/// **A view's widget is no longer always the control it names.** `TextField`'s
/// body is `AnyView(style.makeView(...))`, so the widget on its node is a plain
/// container and `widget.into()` as an `EditText` traps. P4 died at launch on
/// Android with "AnyWidget used with incompatible widget type EditText; actual
/// widget type is View" (2026-10-02) -- the defect UIKitBackend and
/// AppKitBackend were fixed for, missed here. Searching is a strict
/// generalisation of casting: a widget that already is the type matches first.
///
/// 在 `view` 或其子樹中，第一個(以 Java 的意義)屬於 `T` 的 view。**一個 view 的 widget 已經不一定是它所
/// 命名的那個控制項了。** `TextField` 的 body 是 `AnyView(style.makeView(...))`,因此它節點上的 widget 是
/// 一般容器，把 `widget.into()` 當成 `EditText` 會 trap。P4 在 Android 上一啟動就死於「AnyWidget used with
/// incompatible widget type EditText; actual widget type is View」(2026-10-02)——UIKitBackend 與
/// AppKitBackend 曾為此修過，這裡漏了。搜尋是轉型的嚴格推廣：本身就是該型別的 widget 第一個就會符合。
@MainActor
private func androidFirstDescendant<T: AnyJavaObject>(_ type: T.Type, in view: AndroidKit.View) -> T? {
    if let match = view.as(T.self) {
        return match
    }
    guard let group = view.as(AndroidKit.ViewGroup.self) else { return nil }
    for index in 0..<group.getChildCount() {
        if let child = group.getChildAt(index),
            let match = androidFirstDescendant(type, in: child)
        {
            return match
        }
    }
    return nil
}

extension SwiftCrossUI.View {
    /// Runs `action` on the first `T` under this view's widget; loud when there
    /// is none, because an `.inspect` that quietly did nothing would be worse
    /// than the trap it replaces.
    /// 在這個 view 的 widget 底下，對第一個 `T` 執行 `action`;找不到時大聲失敗。
    nonisolated func androidInspectFirst<T: AnyJavaObject>(
        _ inspectionPoints: InspectionPoints,
        _ type: T.Type,
        _ action: @escaping @MainActor @Sendable (T) -> Void
    ) -> some SwiftCrossUI.View {
        InspectView(child: self, inspectionPoints: inspectionPoints) { (widget: AndroidKit.View) in
            guard let match = androidFirstDescendant(type, in: widget) else {
                fatalError("inspect: no \(T.self) at or below this view")
            }
            action(match)
        }
    }
}

extension SwiftCrossUI.View {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (AndroidKit.View) -> Void
    ) -> some SwiftCrossUI.View {
        InspectView(child: self, inspectionPoints: inspectionPoints, action: action)
    }
}

extension SwiftCrossUI.Button {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (AndroidKit.Button) -> Void
    ) -> some SwiftCrossUI.View {
        androidInspectFirst(inspectionPoints, AndroidKit.Button.self, action)
    }
}

extension Text {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (TextView) -> Void
    ) -> some SwiftCrossUI.View {
        androidInspectFirst(inspectionPoints, TextView.self, action)
    }
}

extension TextField {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (EditText) -> Void
    ) -> some SwiftCrossUI.View {
        androidInspectFirst(inspectionPoints, EditText.self, action)
    }
}

extension SecureField {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (EditText) -> Void
    ) -> some SwiftCrossUI.View {
        androidInspectFirst(inspectionPoints, EditText.self, action)
    }
}

extension TextEditor {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (EditText) -> Void
    ) -> some SwiftCrossUI.View {
        androidInspectFirst(inspectionPoints, EditText.self, action)
    }
}

extension Image {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (ImageView) -> Void
    ) -> some SwiftCrossUI.View {
        androidInspectFirst(inspectionPoints, ImageView.self, action)
    }
}

extension SwiftCrossUI.WebView {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (AndroidKit.WebView) -> Void
    ) -> some SwiftCrossUI.View {
        androidInspectFirst(inspectionPoints, AndroidKit.WebView.self, action)
    }
}

extension SwiftCrossUI.List {
    public func inspect(
        _ inspectionPoints: InspectionPoints = .onCreate,
        _ action: @escaping @MainActor @Sendable (AndroidKit.ListView) -> Void
    ) -> some SwiftCrossUI.View {
        androidInspectFirst(inspectionPoints, AndroidKit.ListView.self, action)
    }
}

extension Activity {
    @JavaMethod
    public func getWindow() -> AndroidKit.Window?
}

extension SwiftCrossUI.View {
    public func inspectWindow(
        _ action: @escaping @MainActor @Sendable (AndroidKit.Window) -> Void
    ) -> some SwiftCrossUI.View {
        // AndroidBackend.Window is a wrapper around the root view, since that's more useful than
        // the actual Window object for most things. There's not a whole lot you can do with a
        // Window object in Android. So if the user specifically requests it, we need to materialize
        // the window from the activity instead of using the backend's "window".
        InspectWindowView(child: self) { (_: AndroidBackend.Window) in
            action(AndroidBackend.activity.getWindow()!)
        }
    }
}
