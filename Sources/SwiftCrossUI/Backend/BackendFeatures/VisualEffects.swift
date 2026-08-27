extension BackendFeatures {
    /// Backend methods for compositing effects -- opacity, blur and colour
    /// adjustment.
    ///
    /// These are used by ``View/opacity(_:)``, ``View/blur(radius:)``,
    /// ``View/saturation(_:)``, ``View/brightness(_:)``, ``View/contrast(_:)``,
    /// ``View/grayscale(_:)`` and ``View/hueRotation(_:)``.
    ///
    /// A backend that can express only some of ``VisualEffect``'s fields should
    /// still conform and apply what it can. Declining to conform is not a
    /// graceful degradation here: ``CastBackend`` turns a missing conformance
    /// into `fatalError`, so an app calling `.opacity(_:)` would abort rather
    /// than render without the effect. Applying the subset and saying so is the
    /// better failure -- see `testapp/gtk-silent-noops.md` for why "says so"
    /// matters as much as "applies what it can".
    ///
    /// 用於合成效果的 backend 方法——不透明度、模糊與色彩調整。
    ///
    /// 若某個 backend 只能表達 ``VisualEffect`` 的部分欄位，仍應宣告 conformance 並套用其做得到的
    /// 部分。在此處「不宣告 conformance」並非優雅降級：``CastBackend`` 會把缺少的 conformance 轉為
    /// `fatalError`，因此呼叫 `.opacity(_:)` 的 app 會直接中止，而不是「畫出來但沒有效果」。套用
    /// 子集並明白告知才是較好的失敗方式——「明白告知」與「盡力套用」同等重要，理由見
    /// `testapp/gtk-silent-noops.md`。
    @MainActor
    public protocol VisualEffects: Core {
        /// Create a container capable of applying compositing effects to its
        /// child.
        ///
        /// If no container is necessary, this method is allowed to return
        /// `child` unmodified.
        ///
        /// - Parameters:
        ///   - child: The widget being wrapped to apply an effect to.
        func createVisualEffectContainer(wrapping child: Widget) -> Widget

        /// Apply an effect to a widget, replacing any effect previously set on
        /// it.
        ///
        /// Replacing rather than accumulating: each modifier owns one container
        /// and sets that container's whole effect, so composition comes from
        /// nesting containers. A backend that added to what was already there
        /// would compound the effect on every view update.
        ///
        /// 是「取代」而非「累加」：每個 modifier 擁有一個容器，並設定該容器的完整效果，因此
        /// 組合來自容器的巢狀結構。若 backend 在既有值上累加，每次 view 更新都會讓效果不斷疊加。
        ///
        /// - Parameters:
        ///   - effect: The effect to apply. ``VisualEffect/identity`` means
        ///     remove any effect.
        ///   - widget: The widget to apply it to.
        func setVisualEffect(_ effect: VisualEffect, ofWidget widget: Widget)
    }
}
