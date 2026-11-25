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
        //
        // With a blend mode the widget stays at 1 and the container applies the opacity
        // to its content before blending (gtk_passthrough_fixed_set_blend_mode below):
        // below 1 GTK draws the widget into an offscreen group, and the copy of the
        // backdrop taken inside it would hold nothing, so `.opacity(0.5)` and a blend
        // mode in one container blended with transparency.
        // 設有混合模式時 widget 維持 1,由容器在混合前把 opacity 乘到內容上(見下方的
        // gtk_passthrough_fixed_set_blend_mode):小於 1 時 GTK 會把 widget 畫進離屏群組，在其中取得的背景副本
        // 是空的，於是同一容器中的 `.opacity(0.5)` 與混合模式會跟透明混合。
        widget.opacity = effect.blendMode == .normal ? effect.opacity : 1

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
            Float(effect.hueRotation.degrees),
            effect.colorInvert ? 1 : 0
        )
        // shadow(color:radius:x:y:): GSK's radius is a CSS blur radius, twice the
        // Gaussian spread that Core Animation's shadowRadius (SwiftUI's radius) names, as
        // for blur above. An alpha of 0 removes the shadow.
        // shadow(color:radius:x:y:):GSK 的半徑是 CSS 的模糊半徑，是 Core Animation shadowRadius(即 SwiftUI
        // 的 radius)所指高斯擴散的兩倍，與上方的 blur 相同。alpha 為 0 時移除陰影。
        let shadow = effect.shadow
        gtk_passthrough_fixed_set_shadow(
            widget.widgetPointer,
            shadow?.color.red ?? 0,
            shadow?.color.green ?? 0,
            shadow?.color.blue ?? 0,
            shadow?.color.opacity ?? 0,
            Float(shadow?.x ?? 0),
            Float(shadow?.y ?? 0),
            Float(2 * (shadow?.radius ?? 0))
        )
        // blendMode(_:), drawn by the container against a copy of what is already drawn
        // behind it (scui_snapshot_blended, gtk_passthrough_fixed.c). Every mode has a
        // GSK route there, so none is approximated.
        // blendMode(_:),由容器對著其後方已畫好內容的副本繪製(gtk_passthrough_fixed.c 的
        // scui_snapshot_blended)。每種模式在那裡都有 GSK 的畫法，因此沒有近似。
        gtk_passthrough_fixed_set_blend_mode(widget.widgetPointer, effect.blendMode.gtkHelperValue, Float(effect.opacity))
    }
}

extension BlendMode {
    /// The SCUI_BLEND_* value gtk_helpers.h names for this mode.
    /// gtk_helpers.h 為此模式命名的 SCUI_BLEND_* 值。
    var gtkHelperValue: Int32 {
        let value =
            switch self {
                case .normal: SCUI_BLEND_NORMAL
                case .multiply: SCUI_BLEND_MULTIPLY
                case .screen: SCUI_BLEND_SCREEN
                case .overlay: SCUI_BLEND_OVERLAY
                case .darken: SCUI_BLEND_DARKEN
                case .lighten: SCUI_BLEND_LIGHTEN
                case .colorDodge: SCUI_BLEND_COLOR_DODGE
                case .colorBurn: SCUI_BLEND_COLOR_BURN
                case .softLight: SCUI_BLEND_SOFT_LIGHT
                case .hardLight: SCUI_BLEND_HARD_LIGHT
                case .difference: SCUI_BLEND_DIFFERENCE
                case .exclusion: SCUI_BLEND_EXCLUSION
                case .hue: SCUI_BLEND_HUE
                case .saturation: SCUI_BLEND_SATURATION
                case .color: SCUI_BLEND_COLOR
                case .luminosity: SCUI_BLEND_LUMINOSITY
                case .sourceAtop: SCUI_BLEND_SOURCE_ATOP
                case .destinationOver: SCUI_BLEND_DESTINATION_OVER
                case .destinationOut: SCUI_BLEND_DESTINATION_OUT
                case .plusDarker: SCUI_BLEND_PLUS_DARKER
                case .plusLighter: SCUI_BLEND_PLUS_LIGHTER
            }
        return Int32(value)
    }
}
