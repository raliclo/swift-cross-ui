/// Denotes a fully-featured backend that implements all features of
/// SwiftCrossUI.
///
/// ## Topics
///
/// ### Constituent Protocols
/// - ``BaseAppBackend``
/// - ``BackendFeatures/MenuButtons``
/// - ``BackendFeatures/Paths``
/// - ``BackendFeatures/Alerts``
/// - ``BackendFeatures/Sheets``
/// - ``BackendFeatures/IncomingURLs``
/// - ``BackendFeatures/ExternalURLs``
/// - ``BackendFeatures/RevealFiles``
/// - ``BackendFeatures/ApplicationMenus``
/// - ``BackendFeatures/FileDialogs``
/// - ``BackendFeatures/CornerRadius``
/// - ``BackendFeatures/WebViews``
/// - ``BackendFeatures/Tables``
/// - ``BackendFeatures/Gestures``
/// - ``BackendFeatures/Tooltips``
/// - ``BackendFeatures/Colors``
/// - ``BackendFeatures/DatePickers``
/// - ``BackendFeatures/Windowing``
/// **Adding a requirement here does not make the backends conform to it.**
///
/// This is a protocol composition, and only ``AppKitBackend`` declares itself a
/// `FullAppBackend` (`AppKitBackend.swift:22`). The other four list their
/// features one by one -- `GtkBackend.swift:25`, `WinUIBackend.swift:109`,
/// `UIKitBackend.swift:16`, and for `AndroidBackend` a per-feature
/// `extension AndroidBackend: BackendFeatures.X` in its own file. So a
/// requirement added here is enforced by the compiler on exactly ONE backend.
///
/// Measured 2026-09-08. `Popovers` was added to this list and the five
/// `extension X: BackendFeatures.Popovers` declarations were deleted at the same
/// time, on the reasoning that the composition now covered it. AppKitBackend was
/// covered. The other four silently stopped conforming: the methods were all
/// still there, so every target compiled clean, and `@CastBackend` does a
/// *runtime* cast -- so `P50` launched, rendered nothing, and died with
/// `Fatal error: 'GtkBackend' does not implement 'BackendFeatures.Popovers'`.
/// The sweep reported `launch ok / capture fail`, which reads like a screenshot
/// problem.
///
/// When adding a requirement here, add the conformance to all five backends in
/// the same change, and build at least one that is NOT AppKit.
///
/// **在此處新增一項 requirement，並不會讓各 backend 因此 conform。**
///
/// 這是一個 protocol 組合，而只有 ``AppKitBackend`` 宣告自己是 `FullAppBackend`
/// （`AppKitBackend.swift:22`）。其餘四個是逐項列舉自己的 feature——`GtkBackend.swift:25`、
/// `WinUIBackend.swift:109`、`UIKitBackend.swift:16`，而 `AndroidBackend` 則是在各自的檔案中以
/// `extension AndroidBackend: BackendFeatures.X` 逐項宣告。因此在此處新增的 requirement，編譯器
/// 只會對「恰好一個」backend 強制執行。
///
/// 2026-09-08 實測：`Popovers` 被加進本清單，同時五個 `extension X: BackendFeatures.Popovers`
/// 宣告被一併刪除，理由是這個組合已經涵蓋了它。AppKitBackend 確實被涵蓋了；另外四個則靜默地不再
/// conform——方法全都還在，所以每個 target 都編得乾乾淨淨，而 `@CastBackend` 做的是**執行期**轉型，
/// 於是 `P50` 啟動了、什麼都沒畫，然後以
/// `Fatal error: 'GtkBackend' does not implement 'BackendFeatures.Popovers'` 終止。sweep 回報的是
/// `launch ok / capture fail`，讀起來像是截圖出了問題。
///
/// 在此處新增 requirement 時，請在同一次變更中把 conformance 加到全部五個 backend，並且至少建置一個
/// **不是** AppKit 的 backend。
public typealias FullAppBackend =
    BaseAppBackend
        & BackendFeatures.MenuButtons
        & BackendFeatures.Paths
        & BackendFeatures.Alerts
        & BackendFeatures.Sheets
        & BackendFeatures.Popovers
        & BackendFeatures.IncomingURLs
        & BackendFeatures.ExternalURLs
        & BackendFeatures.RevealFiles
        & BackendFeatures.ApplicationMenus
        & BackendFeatures.FileDialogs
        & BackendFeatures.CornerRadius
        & BackendFeatures.WebViews
        & BackendFeatures.Tables
        & BackendFeatures.Gestures
        & BackendFeatures.Tooltips
        & BackendFeatures.Colors
        & BackendFeatures.DatePickers
        & BackendFeatures.Windowing
        & BackendFeatures.Gradients

/// A typealias for ``FullAppBackend``.
///
/// Long story short, [SwiftCrossUI PR #513](https://github.com/moreSwift/swift-cross-ui/pull/513)
/// completely refactored the monolithic `AppBackend` protocol, splitting it out
/// into around three dozen smaller protocols. This typealias now refers to
/// another typealias that composes all of these protocols together, meaning
/// it should behave just as it used to.
///
/// After SwiftCrossUI 1.0.0, this typealias will be removed and we may choose
/// to reuse the name `AppBackend`.
@available(
    *,
    deprecated,
    renamed: "FullAppBackend",
    message: """
        This is now a composition of many smaller protocols; see SwiftCrossUI \
        PR #513 for details
        """
)
public typealias AppBackend = FullAppBackend
