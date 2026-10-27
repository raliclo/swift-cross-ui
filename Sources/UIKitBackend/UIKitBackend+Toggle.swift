import UIKit

@_spi(Backends) import SwiftCrossUI

/// The button-style `Toggle`, the default toggle style.
///
/// `.toggleStyle(.switch)` goes through `createSwitch`; every other toggle
/// comes here, so P12, P13, P16, P21, P23 and P26 all depend on it.
///
/// 按鈕樣式的 `Toggle`，也就是預設的 toggle 樣式。
///
/// `.toggleStyle(.switch)` 走 `createSwitch`;其他所有 toggle 都走這裡，因此 P12、P13、P16、
/// P21、P23 與 P26 都依賴它。
final class ToggleWidget: WrapperWidget<UIButton> {
    var onChange: ((Bool) -> Void)?

    @objc
    func toggleTapped() {
        // Flip first, then report. UIButton does not maintain `isSelected` for
        // you the way AppKit's `.pushOnPushOff` maintains its state, so a
        // handler that only reported would leave the control showing the old
        // value until the view graph happened to write it back -- and it writes
        // the value it was just told, so it would never correct itself.
        // 先翻轉，再回報。UIButton 不會像 AppKit 的 `.pushOnPushOff` 那樣替你維護 `isSelected`，
        // 因此一個只負責回報的 handler，會讓控制項持續顯示舊值，直到 view graph 剛好把它寫回來
        // ——而它寫回的正是它剛被告知的那個值，所以它永遠不會自行更正。
        child.isSelected.toggle()
        onChange?(child.isSelected)
    }

    init() {
        super.init(child: UIButton(type: .system))

        #if os(tvOS)
            child.addTarget(self, action: #selector(toggleTapped), for: .primaryActionTriggered)
        #else
            child.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)
        #endif
    }

    /// Sets the state without calling `onChange`.
    ///
    /// The view graph calls this to push the model's value into the control. If
    /// it went through `toggleTapped` it would report the change back as though
    /// the user had made it, and a `Toggle` bound to a value that its own
    /// `onChange` writes would oscillate.
    ///
    /// 設定狀態，且不呼叫 `onChange`。
    ///
    /// view graph 以此把模型的值推入控制項。若它改走 `toggleTapped`，就會把該變更回報成「使用者所
    /// 造成」；而一個綁定到「由其自身 `onChange` 寫入之值」的 `Toggle`，將因此來回震盪。
    func setOn(_ on: Bool) {
        child.isSelected = on
        updateAppearance()
    }

    /// A visible difference between on and off, which a plain `UIButton` does
    /// not give you.
    ///
    /// AppKit gets this from `.pushOnPushOff`: the button draws itself pushed
    /// in. UIKit's `.system` button changes nothing for `isSelected` unless it
    /// is told to, so an untouched implementation would toggle correctly and
    /// look identical either way -- which reads as the toggle not working, and
    /// is the harder failure to diagnose because the state really did change.
    ///
    /// 讓「開」與「關」在視覺上有差異，而純粹的 `UIButton` 不會給你這個。
    ///
    /// AppKit 是靠 `.pushOnPushOff` 得到它：按鈕會把自己畫成被按下的樣子。UIKit 的 `.system` 按鈕
    /// 對 `isSelected` 不作任何改變，除非明確告知；因此未經處理的實作會正確地切換狀態，外觀卻兩者
    /// 相同——那讀起來像是 toggle 沒有作用，而且是更難診斷的一種失敗，因為狀態確實改變了。
    func updateAppearance() {
        if child.isSelected {
            child.backgroundColor = .tintColor.withAlphaComponent(0.25)
        } else {
            child.backgroundColor = nil
        }
        child.layer.cornerRadius = 6
    }
}

extension UIKitBackend {
    public func createToggle() -> Widget {
        ToggleWidget()
    }

    public func updateToggle(
        _ toggle: Widget,
        label: String,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let toggleWidget = toggle as! ToggleWidget
        setButtonTitle(toggleWidget.child, label, environment: environment)
        toggleWidget.onChange = onChange
        toggleWidget.child.isEnabled = environment.isEnabled
        // Dimmed when disabled. The title is an attributed string with its colour
        // pinned for `.normal`, so UIButton's own disabled dimming never shows, and
        // P21's toggle-button row drew "Disabled" exactly like "Enabled"
        // (p21-ios-final-20260929-052250.png) -- the #390 question on UIKit.
        // 停用時變淡。標題是 `.normal` 狀態下釘死顏色的 attributed string,所以 UIButton 自己的停用變淡永遠不會出現,
        // P21 的 toggle-button 列把 "Disabled" 畫得和 "Enabled" 一模一樣——這就是 UIKit 上的 #390 問題。
        toggleWidget.child.alpha = environment.isEnabled ? 1 : 0.4
        toggleWidget.updateAppearance()
    }

    public func setState(ofToggle toggle: Widget, to state: Bool) {
        let toggleWidget = toggle as! ToggleWidget
        toggleWidget.setOn(state)
    }
}
