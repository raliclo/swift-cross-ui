import CGtk
import Gtk
import GtkCHelpers
@_spi(Backends) import SwiftCrossUI

extension GtkBackend: BackendFeatures.VisualEffects {
    public func createVisualEffectContainer(wrapping child: Widget) -> Widget {
        // The same passthrough container every other wrapper here uses. It draws
        // nothing itself, which matters: a plain GtkFixed claims every point its
        // children do not cover, and a wrapper that swallowed the pointer would
        // make `.opacity(0.99)` silently break clicking.
        //
        // 與此處其他包裝器所使用的 passthrough 容器相同。它自身不繪製任何內容，而這一點很重要：
        // 一般的 GtkFixed 會攔截子元件未覆蓋到的每一個點，若包裝器吞掉了指標事件，
        // `.opacity(0.99)` 就會在無聲無息中讓點擊失效。
        let container = createContainer()
        insert(child, into: container, at: 0)
        return container
    }

    public func setVisualEffect(_ effect: VisualEffect, ofWidget widget: Widget) {
        // Opacity through the widget property, not through CSS.
        //
        // `gtk_widget_set_opacity` composites the widget and everything under it
        // as a group, which is what SwiftUI's `.opacity(_:)` does. The CSS
        // `opacity` property is inherited by each child's own rendering instead,
        // so two overlapping children at 0.5 would show through each other --
        // visibly different, and wrong.
        //
        // 不透明度使用 widget 屬性而非 CSS。
        //
        // `gtk_widget_set_opacity` 會把該 widget 及其之下的所有內容當成一個群組來合成，這正是
        // SwiftUI 的 `.opacity(_:)` 所做的事。而 CSS 的 `opacity` 屬性則會由每個子元件各自的繪製
        // 繼承，於是兩個重疊、各為 0.5 的子元件會互相透出——外觀明顯不同，而且是錯的。
        widget.opacity = effect.opacity

        // Everything else is drawn by the container itself, in its snapshot
        // (gtk_passthrough_fixed.c): blur, saturation, brightness, contrast,
        // grayscale, hue, in AppKitBackend's order. Not a CSS `filter`, because
        // CSS `grayscale(1)` is the same grey as `saturate(0)` and AppKit's is
        // darker -- AppKit's is the reference (P39, 2026-10-16) -- and because
        // CSS `brightness()` multiplies where SwiftUI adds.
        //
        // 其餘全部由容器自己在 snapshot 中繪製(gtk_passthrough_fixed.c):模糊、飽和度、亮度、對比、
        // 灰階、色相，順序同 AppKitBackend。不使用 CSS `filter`,因為 CSS 的 `grayscale(1)` 與
        // `saturate(0)` 是同一種灰，而 AppKit 的更暗——以 AppKit 為準(P39,2026-10-16)——
        // 也因為 CSS 的 `brightness()` 是乘法，而 SwiftUI 是加法。
        gtk_passthrough_fixed_set_effect(
            widget.widgetPointer,
            Float(effect.blurRadius),
            Float(effect.saturation),
            Float(effect.brightness),
            Float(effect.contrast),
            Float(effect.grayscale),
            Float(effect.hueRotation.degrees)
        )
    }
}
