/// How much width a window offers, as SwiftUI's `UserInterfaceSizeClass`:
/// compact on a phone held upright and in a narrow window, regular elsewhere.
///
/// 視窗提供的寬度類別，即 SwiftUI 的 `UserInterfaceSizeClass`:直拿的手機與窄視窗為 compact,
/// 其餘為 regular。
public enum UserInterfaceSizeClass: Hashable, Sendable {
    /// Room for one column. / 只放得下一欄。
    case compact
    /// Room for columns side by side. / 放得下並排的多欄。
    case regular

    /// Widths below this, in points (dp on Android), are compact. 600 is where
    /// Android's window size classes leave compact, and every iPhone held
    /// upright is narrower.
    ///
    /// 低於此寬度(點;Android 為 dp)即為 compact。600 是 Android 視窗尺寸類別離開 compact 之處，
    /// 而每支直拿的 iPhone 都比它窄。
    static let compactWidthLimit = 600

    /// The class of a window `width` wide. / 寬度為 `width` 的視窗所屬的類別。
    static func forWindowWidth(_ width: Int) -> Self {
        width < compactWidthLimit ? .compact : .regular
    }
}

extension EnvironmentValues {
    /// The horizontal size class of the window this view is in. The window sets
    /// it from its width on every update; a value the app sets is kept.
    ///
    /// 此 view 所在視窗的水平尺寸類別。視窗每次更新時依其寬度設定;app 自行設定的值會被保留。
    @Entry public var horizontalSizeClass: UserInterfaceSizeClass? = nil
}
