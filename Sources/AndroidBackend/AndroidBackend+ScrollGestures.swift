import AndroidKit
import SwiftCrossUI

/// `.onScrollGesture` on Android.
///
/// **A container, not a listener, and the reason is arithmetic.** A `View` has exactly one
/// `OnTouchListener` slot; `ButtonPressState` and `.onTapGesture(.secondary)` already contend for
/// it (`AndroidBackend+ButtonPressState.swift` writes that conflict out). A third claimant would
/// make three modifiers silently disable each other depending on commit order. A `ViewGroup` of
/// this modifier's own overrides `onTouchEvent` and `onGenericMotionEvent` instead, which nothing
/// else in this backend touches — the same route `ContinuousGestureContainer` took.
///
/// **Both devices, because Android has both.** A finger drags and reports `isPrecise: true`; a
/// mouse wheel sends `ACTION_SCROLL` and reports `false`, with the notches multiplied by
/// `ViewConfiguration`'s own scroll factors. UIKitBackend could only answer `true` — a
/// `UIPanGestureRecognizer` carries no `scrollType` — so Android is the first backend after AppKit
/// where the flag actually distinguishes two devices.
///
/// Android 上的 `.onScrollGesture`。
///
/// **用容器而不是 listener,理由是算術。** 一個 `View` 只有一個 `OnTouchListener` 插槽;
/// `ButtonPressState` 與 `.onTapGesture(.secondary)` 已經在搶它了
/// (`AndroidBackend+ButtonPressState.swift` 把那個衝突寫了出來)。第三個競爭者會讓三個 modifier
/// 依 commit 順序靜默地互相停用。改用一個屬於本 modifier 自己的 `ViewGroup`,覆寫 `onTouchEvent`
/// 與 `onGenericMotionEvent`——那是本 backend 其他任何東西都不碰的路徑,也是
/// `ContinuousGestureContainer` 走過的同一條。
///
/// **兩種裝置都收,因為 Android 兩種都有。** 手指拖曳回報 `isPrecise: true`;滑鼠滾輪送出
/// `ACTION_SCROLL` 並回報 `false`,格數再乘上 `ViewConfiguration` 自己的 scroll factor。
/// UIKitBackend 只答得出 `true`——`UIPanGestureRecognizer` 不帶 `scrollType`——因此在 AppKit 之後,
/// Android 是第一個「這個旗標真的分得出兩種裝置」的 backend。
extension AndroidBackend: BackendFeatures.ScrollGestures {
    public func createScrollGestureTarget(wrapping child: Widget) -> Widget {
        let container = ScrollGestureContainer(context: Self.activity)
        container.addView(child)
        return container.as(AndroidKit.View.self)!
    }

    public func updateScrollGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (ScrollGestureValue) -> Void,
        onEnd: @escaping (ScrollGestureValue) -> Void
    ) {
        let target = target.as(ScrollGestureContainer.self)!
        let value = { @MainActor in
            ScrollGestureValue(
                delta: SIMD2(Double(target.getDeltaX()), Double(target.getDeltaY())),
                translation: SIMD2(
                    Double(target.getTravelX()),
                    Double(target.getTravelY())
                ),
                isPrecise: target.isPrecise()
            )
        }
        target.setOnChange(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onChange(value()) } }) : nil
        )
        target.setOnEnd(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onEnd(value()) } }) : nil
        )
    }
}
