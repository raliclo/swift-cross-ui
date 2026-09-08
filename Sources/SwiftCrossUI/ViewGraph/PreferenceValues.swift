import Foundation

public struct PreferenceValues: Sendable {
    /// The default preferences.
    public static let `default` = PreferenceValues(
        onOpenURL: nil,
        presentationDetents: nil,
        presentationCornerRadius: nil,
        presentationDragIndicatorVisibility: nil,
        presentationBackground: nil,
        interactiveDismissDisabled: nil,
        windowDismissBehavior: nil,
        preferredWindowMinimizeBehavior: nil,
        windowResizeBehavior: nil,
        layoutPriority: defaultLayoutPriority
    )

    static let defaultLayoutPriority = 0.0

    public var onOpenURL: (@Sendable @MainActor (URL) -> Void)?

    /// The available detents for a sheet presentation. Applies to enclosing sheets.
    public var presentationDetents: [PresentationDetent]?

    /// The corner radius for a sheet presentation. Applies to enclosing sheets.
    public var presentationCornerRadius: Double?

    /// The drag indicator visibility for a sheet presentation. Applies to enclosing sheets.
    public var presentationDragIndicatorVisibility: Visibility?

    /// The background color for enclosing sheets.
    public var presentationBackground: Color?

    /// Sets the preferred color scheme for the nearest enclosing presentation.
    public var preferredColorScheme: ColorScheme?

    /// The title of the nearest enclosing navigation container or window.
    ///
    /// Set by ``View/navigationTitle(_:)``. Read by
    /// ``WindowReference`` and applied through
    /// ``BackendFeatures/CoreWindowing/setTitle(ofWindow:to:)``, which is a
    /// ``BackendFeatures/Core`` requirement -- so every backend that can open a
    /// window at all can already honour it, and no backend gains a requirement
    /// from the modifier.
    ///
    /// Not in the memberwise call that builds ``PreferenceValues/default``,
    /// because an optional `var` already defaults to `nil` there. It *is* in
    /// ``init(merging:)``, which has no such shortcut: a property left out of
    /// that initialiser silently reverts to `nil` at every merge point, which
    /// reads as "the title stopped working above two levels of nesting" rather
    /// than as a missing line.
    ///
    /// 最接近的外層導覽容器或視窗的標題。
    ///
    /// 由 ``View/navigationTitle(_:)`` 設定。由 ``WindowReference`` 讀取，並透過
    /// ``BackendFeatures/CoreWindowing/setTitle(ofWindow:to:)`` 套用；後者是
    /// ``BackendFeatures/Core`` 的要求，因此凡是能開出視窗的 backend 就已經能遵守它，
    /// 沒有任何 backend 因這個 modifier 而多出要求。
    ///
    /// 它不出現在建構 ``PreferenceValues/default`` 的 memberwise 呼叫中，因為 optional 的 `var`
    /// 在該處本來就預設為 `nil`。但它**確實**出現在 ``init(merging:)`` 中——那裡沒有這種捷徑：
    /// 若某個屬性在該初始化器中被遺漏，它會在每一個合併點靜默地退回 `nil`，其症狀讀起來會像
    /// 「標題在超過兩層巢狀後就失效了」，而不像少寫了一行。
    public var navigationTitle: String?

    /// Controls whether the user can interactively dismiss enclosing sheets.
    public var interactiveDismissDisabled: Bool?

    /// Controls whether the user can close the enclosing window.
    public var windowDismissBehavior: WindowInteractionBehavior?

    /// Controls whether the user can minimize the enclosing window.
    public var preferredWindowMinimizeBehavior: WindowInteractionBehavior?

    /// Controls whether the user can resize the enclosing window.
    public var windowResizeBehavior: WindowInteractionBehavior?

    /// The layout priority of the view.
    var layoutPriority: Double

    /// Returns a copy of the preferences with the specified property set to the
    /// provided new value.
    ///
    /// - Parameters:
    ///   - keyPath: A key path to the property to set.
    ///   - newValue: The new value of the property.
    /// - Returns: A copy of the preferences with the specified property set to
    ///   `newValue`.
    public func with<T>(_ keyPath: WritableKeyPath<Self, T>, _ newValue: T) -> Self {
        var preferences = self
        preferences[keyPath: keyPath] = newValue
        return preferences
    }
}

extension PreferenceValues {
    init(merging children: [PreferenceValues]) {
        let handlers = children.compactMap(\.onOpenURL)

        if !handlers.isEmpty {
            onOpenURL = { url in
                for handler in handlers {
                    handler(url)
                }
            }
        }

        // For presentation modifiers, take the outer-most value (using child ordering to break ties).
        presentationDetents = children.compactMap(\.presentationDetents).first
        presentationCornerRadius = children.compactMap(\.presentationCornerRadius).first
        presentationDragIndicatorVisibility =
            children.compactMap(\.presentationDragIndicatorVisibility).first
        presentationBackground = children.compactMap(\.presentationBackground).first
        preferredColorScheme = children.compactMap(\.preferredColorScheme).first
        interactiveDismissDisabled = children.compactMap(\.interactiveDismissDisabled).first

        // Same outer-most-wins rule as the presentation values above, and for
        // the same reason: `PreferenceModifier` overwrites the key on the way
        // up, so an outer `.navigationTitle` already replaced any inner one
        // before this merge ever sees it. `.first` only breaks ties between
        // siblings, and it breaks them by child order.
        // 與上方各項 presentation 值採相同的「最外層優先」規則，理由也相同：`PreferenceModifier`
        // 在向上傳遞時會覆寫該 key，因此外層的 `.navigationTitle` 早在這次合併看到它之前，就已經
        // 取代了任何內層的值。`.first` 只用來在兄弟節點之間決勝，且依子節點順序決勝。
        navigationTitle = children.compactMap(\.navigationTitle).first

        windowDismissBehavior = children.compactMap(\.windowDismissBehavior).first
        preferredWindowMinimizeBehavior =
            children.compactMap(\.preferredWindowMinimizeBehavior).first
        windowResizeBehavior = children.compactMap(\.windowResizeBehavior).first

        if let firstChild = children.first, children.count == 1 {
            layoutPriority = firstChild.layoutPriority
        } else {
            layoutPriority = Self.defaultLayoutPriority
        }
    }
}
