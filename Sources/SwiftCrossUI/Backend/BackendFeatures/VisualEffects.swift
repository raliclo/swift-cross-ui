extension BackendFeatures {
    /// Backend methods for compositing effects -- opacity, blur and colour
    /// adjustment.
    ///
    /// These are used by ``View/opacity(_:)``, ``View/blur(radius:)``,
    /// ``View/saturation(_:)``, ``View/brightness(_:)``, ``View/contrast(_:)``,
    /// ``View/grayscale(_:)`` and ``View/hueRotation(_:)``.
    ///
    /// A backend that can express only some of ``VisualEffect``'s fields should
    /// still conform and apply what it can, and say what it leaves out -- see
    /// `testapp/gtk-silent-noops.md` for why "says so" matters as much as
    /// "applies what it can".
    ///
    /// A backend that does not conform at all is not aborted: the effect
    /// modifiers warn once and show the view unmodified
    /// (`VisualEffectModifier.asWidget`), and transitions and `scrollTransition`
    /// draw without their visual part. That degraded path exists only for
    /// backends outside the shipped set -- CursesBackend, LVGLBackend and
    /// QtBackend. GtkBackend, WinUIBackend, AppKitBackend, UIKitBackend and
    /// AndroidBackend must implement this protocol; an effect missing on one of
    /// them is a bug, not a degradation.
    ///
    /// 用於合成效果的 backend 方法——不透明度、模糊與色彩調整。
    ///
    /// 若某個 backend 只能表達 ``VisualEffect`` 的部分欄位，仍應宣告 conformance、套用其做得到的
    /// 部分，並明白告知漏掉了什麼——「明白告知」與「盡力套用」同等重要，理由見
    /// `testapp/gtk-silent-noops.md`。
    ///
    /// 完全未宣告 conformance 的 backend 不會被中止：各效果 modifier 會警告一次並顯示未經修飾的
    /// view(`VisualEffectModifier.asWidget`),transition 與 `scrollTransition` 則不畫其視覺部分。
    /// 這條降級路徑只給已發布集合以外的 backend 使用——CursesBackend、LVGLBackend 與 QtBackend。
    /// GtkBackend、WinUIBackend、AppKitBackend、UIKitBackend 與 AndroidBackend 必須實作本協定；
    /// 在它們之中任何一個上缺少某個效果是 bug,不是降級。
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
