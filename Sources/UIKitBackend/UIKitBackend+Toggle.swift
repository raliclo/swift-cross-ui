import UIKit

@_spi(Backends) import SwiftCrossUI

/// The button-style `Toggle`, which UIKitBackend did not have.
///
/// `createToggle`, `updateToggle` and `setState(ofToggle:)` were three
/// `fatalError`s under a heading reading "Unimplemented Features". Measured on
/// the iOS Simulator 2026-09-02: six of the forty-six test apps -- P12, P13,
/// P16, P21, P23 and P26 -- died within a second of launch on
/// `UIKitBackend: createToggle() not implemented`, which is a quarter of
/// everything that reached a window.
///
/// `createSwitch` was already implemented, so switch-styled toggles worked
/// throughout. That is what made this look like a niche gap rather than the
/// largest one: an app using `.toggleStyle(.switch)` was fine and an app using
/// the default was not.
///
/// 按鈕樣式的 `Toggle`，UIKitBackend 先前並沒有它。
///
/// `createToggle`、`updateToggle` 與 `setState(ofToggle:)` 原本是三個位於「Unimplemented
/// Features」標題之下的 `fatalError`。2026-09-02 於 iOS 模擬器上實測：四十六支測試 app 中有六支
/// ——P12、P13、P16、P21、P23、P26——在啟動一秒內即因
/// `UIKitBackend: createToggle() not implemented` 而終止，佔所有能開出視窗者的四分之一。
///
/// `createSwitch` 早已實作，因此 switch 樣式的 toggle 自始至終都正常。這正是它看起來像一個冷僻缺口、
/// 而非最大缺口的原因：使用 `.toggleStyle(.switch)` 的 app 沒事，使用預設樣式的則不然。
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
        toggleWidget.updateAppearance()
    }

    public func setState(ofToggle toggle: Widget, to state: Bool) {
        let toggleWidget = toggle as! ToggleWidget
        toggleWidget.setOn(state)
    }
}
