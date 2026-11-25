extension BackendFeatures {
    /// Backend methods for progress spinners.
    ///
    /// These are used by ``ProgressView`` when initialized without a `Progress`
    /// instance.
    @MainActor
    public protocol ProgressSpinners: Core {
        /// Creates an indeterminate progress spinner.
        ///
        /// - Returns: A progress spinner.
        func createProgressSpinner() -> Widget

        /// Updates a progress spinner to reflect the current view environment.
        ///
        /// A backend paints the spinner in ``EnvironmentValues/tint`` when it is
        /// set, and in the platform's own colour when it is `nil`, so a tint that
        /// is removed gives the default back.
        ///
        /// 依目前的 view environment 更新進度轉圈。``EnvironmentValues/tint`` 有值時 backend 以它繪製轉圈，
        /// 為 `nil` 時用平台自己的顏色，所以移除 tint 會還原預設。
        ///
        /// - Parameters:
        ///   - widget: The progress spinner to update.
        ///   - environment: The current environment.
        func updateProgressSpinner(
            _ widget: Widget,
            environment: EnvironmentValues
        )

        /// Sets the size of a progress spinner.
        ///
        /// This method exists because AppKitBackend requires special handling to resize progress spinners.
        ///
        /// The default implementation forwards to ``BackendFeatures/Widgets/setSize(of:to:)``.
        func setSize(
            ofProgressSpinner widget: Widget,
            to size: SIMD2<Int>
        )
    }
}

// MARK: Default Implementations

extension BackendFeatures.ProgressSpinners {
    public func setSize(
        ofProgressSpinner widget: Widget,
        to size: SIMD2<Int>
    ) {
        setSize(of: widget, to: size)
    }
}
