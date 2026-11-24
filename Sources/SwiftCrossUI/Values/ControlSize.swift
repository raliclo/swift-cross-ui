/// The size of a control, from smallest to largest.
///
/// Set with ``View/controlSize(_:)`` and read from
/// ``EnvironmentValues/controlSize``. It is inherited through the environment,
/// so one modifier sizes every control beneath it: buttons (and so
/// ``Stepper``), toggles in every built-in style, sliders, pickers, text fields
/// and progress views. Other views, `Text` among them, are not affected.
///
/// The cases are ordered, so `.small < .regular` holds; that is what lets a
/// test say "smaller" without knowing the platform's metrics.
///
/// 控制項的尺寸，由小到大。
///
/// 以 ``View/controlSize(_:)`` 設定、從 ``EnvironmentValues/controlSize`` 讀取。它經由 environment 繼承，
/// 因此一個 modifier 就決定其下所有控制項的尺寸：按鈕(因此也包含 ``Stepper``)、所有內建樣式的 toggle、slider、
/// picker、文字欄位與進度指示。其他 view(包括 `Text`)不受影響。
///
/// 各 case 有順序，所以 `.small < .regular` 成立；這讓測試不必知道平台的度量也能說「比較小」。
public enum ControlSize: Hashable, Sendable, CaseIterable, Comparable {
    case mini
    case small
    case regular
    case large
    case extraLarge

    /// How much a control at this size is scaled relative to `.regular`.
    ///
    /// One factor for every control and every backend, so a `.small` button
    /// and a `.small` switch shrink by the same proportion and the ordering
    /// `mini < small < regular < large < extraLarge` holds in each dimension on
    /// every platform. A label's point size and a button's padding are
    /// multiplied by it; a native control with no label of ours (switch,
    /// checkbox, slider, picker, text field, progress view) is laid out at its
    /// regular size and drawn through the backend's geometric effect at this
    /// scale. The mini and small factors match AppKit's 9 and 11 point control
    /// fonts against its 13 point regular one.
    ///
    /// 此尺寸的控制項相對於 `.regular` 的縮放倍率。
    ///
    /// 每一種控制項、每一個 backend 都用同一個倍率，所以 `.small` 的按鈕與 `.small` 的 switch 縮小的比例相同，
    /// 而 `mini < small < regular < large < extraLarge` 的順序在每個平台的每個維度上都成立。標籤的字級與按鈕的
    /// padding 乘以它；沒有我們自己標籤的原生控制項(switch、checkbox、slider、picker、文字欄位、進度指示)以 regular
    /// 尺寸排版，再經由 backend 的幾何效果以此倍率畫出。mini 與 small 的倍率對應 AppKit 9 點與 11 點的控制項字型
    /// 相對於 13 點的 regular 字型。
    public var scale: Double {
        switch self {
            case .mini: 0.7
            case .small: 0.85
            case .regular: 1
            case .large: 1.2
            case .extraLarge: 1.4
        }
    }

    public static func < (lhs: ControlSize, rhs: ControlSize) -> Bool {
        lhs.scale < rhs.scale
    }
}
