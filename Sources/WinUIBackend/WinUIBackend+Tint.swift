import SwiftCrossUI
import UWP
import WinUI

/// `tint(_:)` on WinUI: lightweight styling. Each control's template reads its
/// accent through named theme resources (`ToggleSwitchFillOn`,
/// `CheckBoxCheckBackgroundFillChecked`, `SliderTrackValueFill`, ...), and a
/// resource of the same name in the control's own `Resources` wins over the
/// application's -- the override Microsoft documents for recolouring one
/// control. The pointer-over and pressed variants are overridden with it, or
/// the accent would come back under the pointer.
///
/// A template resolves `{ThemeResource}` when it is applied and again when the
/// theme changes, not when a dictionary changes, so after a change the
/// control's `requestedTheme` is flipped and restored -- the theme change that
/// makes it look again. Only on a change: the resources' first key is compared
/// with the tint before anything is written.
///
/// WinUI 上的 `tint(_:)`:輕量樣式(lightweight styling)。每個控制項的範本經由具名的主題資源
/// (`ToggleSwitchFillOn`、`CheckBoxCheckBackgroundFillChecked`、`SliderTrackValueFill`……)讀取強調色，而控制項自己
/// `Resources` 中同名的資源優先於 application 的——這正是 Microsoft 為單一控制項重新上色所記載的覆寫方式。指標停留與按下的
/// 變體也一併覆寫，否則指標移上去時強調色又會回來。
///
/// 範本在套用時以及主題改變時解析 `{ThemeResource}`,字典改變時則不會，所以改變之後把控制項的 `requestedTheme` 翻轉再還原——
/// 那次主題改變讓它重新查找。只在改變時這麼做：寫入任何東西之前，先比較資源中第一個鍵與 tint。
extension WinUIBackend {
    static let toggleSwitchTintKeys = [
        "ToggleSwitchFillOn", "ToggleSwitchFillOnPointerOver", "ToggleSwitchFillOnPressed",
        "ToggleSwitchStrokeOn", "ToggleSwitchStrokeOnPointerOver", "ToggleSwitchStrokeOnPressed",
    ]

    static let checkBoxTintKeys = [
        "CheckBoxCheckBackgroundFillChecked",
        "CheckBoxCheckBackgroundFillCheckedPointerOver",
        "CheckBoxCheckBackgroundFillCheckedPressed",
        "CheckBoxCheckBackgroundStrokeChecked",
        "CheckBoxCheckBackgroundStrokeCheckedPointerOver",
        "CheckBoxCheckBackgroundStrokeCheckedPressed",
        "CheckBoxCheckBackgroundFillIndeterminate",
        "CheckBoxCheckBackgroundFillIndeterminatePointerOver",
        "CheckBoxCheckBackgroundFillIndeterminatePressed",
        "CheckBoxCheckBackgroundStrokeIndeterminate",
        "CheckBoxCheckBackgroundStrokeIndeterminatePointerOver",
        "CheckBoxCheckBackgroundStrokeIndeterminatePressed",
    ]

    static let sliderTintKeys = [
        "SliderTrackValueFill", "SliderTrackValueFillPointerOver", "SliderTrackValueFillPressed",
        "SliderThumbBackground", "SliderThumbBackgroundPointerOver", "SliderThumbBackgroundPressed",
    ]

    static let toggleButtonTintKeys = [
        "ToggleButtonBackgroundChecked", "ToggleButtonBackgroundCheckedPointerOver",
        "ToggleButtonBackgroundCheckedPressed",
        "ToggleButtonBorderBrushChecked", "ToggleButtonBorderBrushCheckedPointerOver",
        "ToggleButtonBorderBrushCheckedPressed",
    ]

    /// Puts `color` (nil: the theme's accent) under `keys` in the control's
    /// own resources, and has the template look them up again if they changed.
    /// Call it after `apply(to:)`, which sets `requestedTheme`.
    /// 把 `color`(nil:主題的強調色)放進控制項自己資源的 `keys` 之下，若有改變就讓範本重新查找。在設定
    /// `requestedTheme` 的 `apply(to:)` 之後呼叫。
    func applyTint(_ color: SwiftCrossUI.Color.Resolved?, to control: WinUI.Control, keys: [String]) {
        guard let resources = control.resources, let first = keys.first else { return }
        let current: UWP.Color? =
            resources.hasKey(first) ? (resources.lookup(first) as? SolidColorBrush)?.color : nil
        let wanted = color?.uwpColor
        guard current != wanted else { return }
        if let wanted {
            let brush = SolidColorBrush(wanted)
            for key in keys {
                _ = resources.insert(key, brush)
            }
        } else {
            for key in keys {
                resources.remove(key)
            }
        }
        let theme = control.requestedTheme
        control.requestedTheme = theme == .dark ? .light : .dark
        control.requestedTheme = theme
    }
}
