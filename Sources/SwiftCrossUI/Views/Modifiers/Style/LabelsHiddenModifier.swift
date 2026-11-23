extension EnvironmentValues {
    /// Whether controls in this scope leave out their separate labels. Set by
    /// ``View/labelsHidden(_:)``.
    /// 此範圍內的控制項是否省略它們另外的標籤。由 ``View/labelsHidden(_:)`` 設定。
    @Entry public var labelsHidden: Bool = false
}

extension View {
    /// Hides the separate labels of the controls in this view, as SwiftUI's
    /// `labelsHidden()`: toggles, pickers, date and colour pickers, steppers,
    /// gauges, progress views and labeled content show their control alone. A
    /// button-style toggle keeps its label, which is the button itself.
    ///
    /// 隱藏此 view 中控制項另外的標籤，即 SwiftUI 的 `labelsHidden()`:toggle、picker、日期與顏色選擇器、
    /// stepper、gauge、進度 view 與 labeled content 只顯示控制項本身。按鈕樣式的 toggle 保留其標籤，因為
    /// 標籤就是按鈕本身。
    public func labelsHidden(_ hidden: Bool = true) -> some View {
        environment(\.labelsHidden, hidden)
    }
}
