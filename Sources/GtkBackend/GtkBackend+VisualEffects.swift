import CGtk
import Gtk
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

        // Everything else is one CSS `filter`. Written as a single property
        // because that is how CSS composes them: the functions apply in the
        // order given, and setting `filter` twice replaces rather than combines.
        //
        // 其餘全部合併為一條 CSS `filter`。之所以寫成單一屬性，是因為 CSS 就是這樣組合它們的：
        // 各個函式依所給順序套用，而重複設定 `filter` 是取代而非合併。
        var functions: [String] = []

        if effect.blurRadius != 0 {
            functions.append("blur(\(effect.blurRadius)px)")
        }
        if effect.saturation != 1 {
            functions.append("saturate(\(effect.saturation))")
        }
        if effect.brightness != 0 {
            // SwiftUI's brightness adds to each channel and is neutral at 0;
            // CSS multiplies and is neutral at 1. Converting rather than passing
            // it through, or `.brightness(0)` -- the value that means "do
            // nothing" -- would render the view black.
            //
            // SwiftUI 的 brightness 是對每個通道做加法、以 0 為中性值；CSS 則是乘法、以 1 為中性
            // 值。此處必須換算而非直接傳遞，否則 `.brightness(0)`——那個代表「什麼都不做」的值——
            // 會把 view 畫成全黑。
            functions.append("brightness(\(1 + effect.brightness))")
        }
        if effect.contrast != 1 {
            functions.append("contrast(\(effect.contrast))")
        }
        if effect.grayscale != 0 {
            functions.append("grayscale(\(effect.grayscale))")
        }
        if effect.hueRotation != .zero {
            functions.append("hue-rotate(\(effect.hueRotation.degrees)deg)")
        }

        if functions.isEmpty {
            widget.css.set(property: .init(key: "filter", value: "none"))
        } else {
            widget.css.set(
                property: .init(key: "filter", value: functions.joined(separator: " "))
            )
        }
    }
}
