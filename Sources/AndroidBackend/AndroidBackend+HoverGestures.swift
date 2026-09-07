@_spi(Backends) import SwiftCrossUI
import AndroidKit
import SwiftJava

/// `onHover(perform:)` on Android.
///
/// Before this file `AndroidBackend` conformed to `BackendFeatures.TapGestures`
/// and not to `BackendFeatures.HoverGestures`, and `OnHoverModifier` reaches the
/// backend through `@CastBackend`, which expands to `fatalError`
/// (`CastBackendMacro.swift:115`). So `.onHover` did not go unhandled on
/// Android, it killed the process -- the same shape as the `HitTesting` gap next
/// door, and the outcome this repository's rules exist to prevent.
///
/// The work is in `HoverContainer.kt`; that file records which `MotionEvent`
/// actions carry hover, why the wrapper overrides `dispatchHoverEvent` instead
/// of using the `View.OnHoverListener` that is bound and available, and what a
/// device with no mouse and no stylus does.
///
/// The container is a `ViewGroup` here and a `FrameLayout` in Kotlin, matching
/// `VisualEffectContainer` and `GeometricEffectContainer`: `AndroidKit` binds
/// `FrameLayout` as a subclass of `ViewGroup`
/// (`AndroidKit/Sources/AndroidWidget/FrameLayout.swift:8`), and `ViewGroup` is
/// the level everything this file calls lives at.
///
/// Android 上的 `onHover(perform:)`。
///
/// 在本檔存在之前，`AndroidBackend` 實作了 `BackendFeatures.TapGestures` 而未實作
/// `BackendFeatures.HoverGestures`，而 `OnHoverModifier` 是透過 `@CastBackend` 抵達 backend 的，
/// 該 macro 會展開為 `fatalError`（`CastBackendMacro.swift:115`）。因此 `.onHover` 在 Android 上
/// 並不是「未被處理」，而是直接殺掉行程——與隔壁 `HitTesting` 的缺口是同一種形狀，也正是本倉庫規則
/// 所要防止的結果。
///
/// 實作位於 `HoverContainer.kt`；該檔記錄了哪些 `MotionEvent` action 承載懸停、為何該外層選擇覆寫
/// `dispatchHoverEvent` 而非使用已繫結且可用的 `View.OnHoverListener`，以及一台既無滑鼠也無觸控筆
/// 的裝置會發生什麼事。
///
/// 此處的容器宣告為 `ViewGroup`，而 Kotlin 端是 `FrameLayout`，與 `VisualEffectContainer` 和
/// `GeometricEffectContainer` 一致：`AndroidKit` 把 `FrameLayout` 繫結為 `ViewGroup` 的子類別
/// （`AndroidKit/Sources/AndroidWidget/FrameLayout.swift:8`），而 `ViewGroup` 正是本檔所呼叫的一切
/// 所在的層級。
@JavaClass(
    "dev.swiftcrossui.androidbackend.HoverContainer",
    extends: AndroidKit.ViewGroup.self
)
class HoverContainer: AndroidKit.ViewGroup {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: AndroidKit.Activity!,
        environment: JNIEnvironment? = nil
    )

    /// Backs `HoverContainer.enterAction`, a Kotlin `var`, whose JVM setter is
    /// this name. Same shape as `DropListener.setHoverAction(_:)`.
    /// 對應 Kotlin 的 `var HoverContainer.enterAction`，其 JVM setter 即為此名稱。與
    /// `DropListener.setHoverAction(_:)` 是同一種形狀。
    @JavaMethod
    func setEnterAction(_ action: SwiftAction?)

    @JavaMethod
    func setExitAction(_ action: SwiftAction?)
}

extension AndroidBackend: BackendFeatures.HoverGestures {
    public func createHoverTarget(wrapping child: Widget) -> Widget {
        let container = HoverContainer(Self.activity, environment: Self.env)
        container.addView(child)
        return container.as(AndroidKit.View.self)!
    }

    public func updateHoverTarget(
        _ hoverTarget: Widget,
        environment: EnvironmentValues,
        action: @escaping (Bool) -> Void
    ) {
        guard let container = hoverTarget.as(HoverContainer.self) else { return }

        // The check is inside the closure rather than around the assignment,
        // which is what GtkBackend and WinUIBackend both do. Clearing the
        // actions instead would leave the Kotlin side's edge detector holding
        // whatever it last saw, so a view disabled while the pointer was inside
        // it would report the exit late -- on the next enter -- rather than not
        // at all.
        //
        // 此檢查放在 closure 之內而非包在指派之外，GtkBackend 與 WinUIBackend 兩者都是這樣做的。
        // 若改為清空這兩個 action，Kotlin 端的邊緣偵測器就會停留在它最後看到的狀態，於是一個「在
        // 指標仍在其內時被停用」的 view 會延遲回報離開——延到下一次進入時——而不是完全不回報。
        let isEnabled = environment.isEnabled

        container.setEnterAction(
            SwiftAction(environment: Self.env) {
                guard isEnabled else { return }
                action(true)
            }
        )

        container.setExitAction(
            SwiftAction(environment: Self.env) {
                guard isEnabled else { return }
                action(false)
            }
        )
    }
}
