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
        layoutPriority: defaultLayoutPriority,
        gridCellColumns: defaultGridCellColumns,
        gridRowCells: []
    )

    static let defaultLayoutPriority = 0.0
    static let defaultGridCellColumns = 1

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

    /// The items a view asked to put in its window's toolbar.
    ///
    /// A list rather than a single value, and merged by concatenation rather
    /// than by outermost-wins. A window's toolbar is the sum of what its
    /// content asked for -- two sections each contributing a button is the
    /// ordinary case -- whereas a window has exactly one title, which is why
    /// ``navigationTitle`` takes the first and this does not.
    ///
    /// 某個 view 要求放進其視窗工具列的項目。
    ///
    /// 這是一個清單而非單一值,合併方式是串接而非「最外層優先」。一個視窗的工具列是「其內容所要求
    /// 之物的總和」——兩個區段各貢獻一個按鈕是再普通不過的情況——而一個視窗只有一個標題,那正是
    /// ``navigationTitle`` 取第一個、而此處不取的原因。
    public var toolbarItems: [ToolbarItem] = []

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

    /// How many of a ``Grid``'s columns this cell occupies.
    ///
    /// Travels up exactly the way ``layoutPriority`` does -- inherited through a
    /// wrapper that has one child, reset otherwise -- because it means the same
    /// kind of thing: an attribute of ONE view that has to survive being wrapped
    /// in a `.padding` or a `.frame`, and must not leak sideways to a sibling.
    ///
    /// 這個儲存格佔據 ``Grid`` 的幾個欄。
    ///
    /// 它向上傳遞的方式與 ``layoutPriority`` 完全相同——經過「只有一個子節點的包裝層」時被繼承，
    /// 其餘情況重設——因為它表達的是同一類東西:**單一**一個 view 的屬性，必須能在被 `.padding`
    /// 或 `.frame` 包起來之後存活，而且絕不可以橫向洩漏給兄弟節點。
    var gridCellColumns: Int

    /// One entry per ``GridRow``, in declaration order, each listing that row's
    /// cells.
    ///
    /// **Concatenated rather than overwritten, the way ``toolbarItems`` is.**
    /// A ``Grid`` needs every row's cells at once -- that is the whole of what
    /// makes columns line up -- and the `.first`-wins rule the presentation
    /// values use would give it exactly one row.
    ///
    /// 每一個 ``GridRow`` 一項，依宣告順序排列，每一項列出該列的儲存格。
    ///
    /// **採串接而非覆寫，與 ``toolbarItems`` 相同。** 一個 ``Grid`` 需要同時拿到每一列的儲存格
    /// ——那正是「讓各欄對齊」的全部內容——而各 presentation 值所採用的「`.first` 勝出」規則，
    /// 只會交給它其中一列。
    var gridRowCells: [GridRowMeasurement]

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

        // Concatenated in child order, so a toolbar reads left to right in the
        // order the view tree declares it.
        // 依子節點順序串接,如此工具列的閱讀順序便與 view 樹宣告它的順序一致。
        toolbarItems = children.flatMap(\.toolbarItems)

        windowDismissBehavior = children.compactMap(\.windowDismissBehavior).first
        preferredWindowMinimizeBehavior =
            children.compactMap(\.preferredWindowMinimizeBehavior).first
        windowResizeBehavior = children.compactMap(\.windowResizeBehavior).first

        gridRowCells = children.flatMap(\.gridRowCells)

        if let firstChild = children.first, children.count == 1 {
            layoutPriority = firstChild.layoutPriority
            gridCellColumns = firstChild.gridCellColumns
        } else {
            layoutPriority = Self.defaultLayoutPriority
            gridCellColumns = Self.defaultGridCellColumns
        }
    }
}
