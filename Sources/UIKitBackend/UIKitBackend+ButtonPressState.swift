import UIKit
@_spi(Backends) import SwiftCrossUI

/// `BackendFeatures.ButtonPressState` on UIKit.
///
/// **UIKit is the one platform that ships the answer as an API.** `UIControl`
/// already distinguishes the four ways a press can end, and names them:
/// `.touchUpInside`, `.touchUpOutside`, `.touchDragExit` and `.touchCancel`.
/// The abandon case therefore needs no bounds arithmetic and no reimplementation
/// of the framework's own hit testing -- `.touchDragExit` *is* "the finger left
/// the button while still down", and `.touchDragEnter` is it coming back. So
/// press, drag off, release reports `true`, `false`, and the release adds
/// nothing because the value is already `false`.
///
/// `addTarget(_:action:for:)` is the mechanism the backend's own button already
/// uses for its tap (`UIKitBackend+CustomButton.swift:165,167` and
/// `UIKitBackend+Control.swift:10`), and a control keeps a list of targets
/// rather than a single one, so registering here cannot displace that.
///
/// **Why not the existing `isHighlighted`.** `UICustomButton` overrides it at
/// `UIKitBackend+CustomButton.swift:139` and that override is where the
/// highlight animation lives -- but the hook is a `didSet` on a Swift property,
/// which nothing outside the file can observe, and adding a callback to it means
/// editing that file. It would also have covered only the buttons built by
/// `createButton(wrapping:)`: `createSimpleButton()` returns a `ButtonWidget`
/// wrapping a plain `UIButton` (`UIKitBackend+Control.swift:4,269`), which has
/// no `UICustomButton` in it. Control events cover both, because both are
/// `UIControl`s.
///
/// **tvOS.** The same control events are what a `UIButton` emits there for the
/// remote's select button, so a focused button reports its press; a button that
/// is merely focused and not selected is not pressed, which is the right answer
/// rather than a gap.
///
/// UIKit 上的 `BackendFeatures.ButtonPressState`。
///
/// **UIKit 是唯一把答案直接做成 API 的平台。** `UIControl` 本來就區分了一次按壓結束的四種方式，並且
/// 各有其名：`.touchUpInside`、`.touchUpOutside`、`.touchDragExit` 與 `.touchCancel`。因此放棄的情況
/// 不需要任何邊界運算，也不需要重新實作框架自己的 hit testing——`.touchDragExit` **就是**「手指仍按著
/// 卻離開了按鈕」，而 `.touchDragEnter` 就是它回來。於是「按下、拖離、放開」會回報 `true`、`false`，
/// 而最後的放開不再增添任何東西，因為值已經是 `false` 了。
///
/// `addTarget(_:action:for:)` 正是這個 backend 自己的按鈕用來處理點擊的機制
/// （`UIKitBackend+CustomButton.swift:165,167` 與 `UIKitBackend+Control.swift:10`），而一個 control
/// 保存的是一份 target 清單而非單一 target，因此在此註冊不可能把那個擠掉。
///
/// **為何不用既有的 `isHighlighted`。** `UICustomButton` 於
/// `UIKitBackend+CustomButton.swift:139` 覆寫了它，高亮動畫也就住在那個覆寫裡——但那個掛勾是一個
/// Swift 屬性的 `didSet`，檔案之外沒有任何東西觀察得到它，而要在其中加上 callback 就等於編輯該檔。
/// 而且它也只會涵蓋由 `createButton(wrapping:)` 建立的按鈕：`createSimpleButton()` 回傳的是一個包住
/// 純 `UIButton` 的 `ButtonWidget`（`UIKitBackend+Control.swift:4,269`），其中沒有任何
/// `UICustomButton`。control event 兩者皆能涵蓋，因為兩者都是 `UIControl`。
///
/// **tvOS。** 在該平台上，`UIButton` 針對遙控器的選取鍵所送出的正是同一組 control event，因此一顆
/// 取得焦點的按鈕會回報它的按壓；而一顆只是取得焦點、並未被選取的按鈕並非按下狀態——那是正確答案，
/// 不是缺口。
///
/// **A bare extension, deliberately.** The conformance is declared on the class
/// itself at `UIKitBackend.swift:32`; naming `BackendFeatures.ButtonPressState`
/// again here would be a redundant conformance and would not compile.
///
/// **刻意採用不帶 conformance 的 extension。** 該 conformance 已宣告於類別本身
/// （`UIKitBackend.swift:32`）；在此再次寫出 `BackendFeatures.ButtonPressState` 會構成重複
/// conformance 而無法編譯。
extension UIKitBackend {
    public func updateButtonPressHandler(
        _ button: Widget,
        handler: @escaping (Bool) -> Void
    ) {
        guard let control = Self.control(in: button) else { return }
        UIKitButtonPressTarget.install(on: control, handler: handler)
    }

    /// Finds the `UIControl` inside a widget from either button factory.
    ///
    /// `createButton(wrapping:)` returns a `CustomButtonWidget`
    /// (`UIKitBackend+CustomButton.swift:13`) and `createSimpleButton()` a
    /// `ButtonWidget` (`UIKitBackend+Control.swift:270`); both are
    /// `WrapperWidget`s, whose single child is the control
    /// (`Widget.swift:411,429`). The direct `as?` first, so a widget that is
    /// itself a control needs no search.
    ///
    /// 在來自任一按鈕工廠方法的 widget 中找出其 `UIControl`。
    ///
    /// `createButton(wrapping:)` 回傳 `CustomButtonWidget`
    /// （`UIKitBackend+CustomButton.swift:13`），`createSimpleButton()` 回傳 `ButtonWidget`
    /// （`UIKitBackend+Control.swift:270`）；兩者都是 `WrapperWidget`，其唯一的子元件就是該 control
    /// （`Widget.swift:411,429`）。先做直接的 `as?`，讓「本身就是 control」的 widget 不必搜尋。
    private static func control(in widget: Widget) -> UIControl? {
        if let control = widget.view as? UIControl {
            return control
        }
        return widget.view.subviews.lazy.compactMap { $0 as? UIControl }.first
    }
}

/// The target object the control events are delivered to.
///
/// A `UIControl` holds its targets weakly, so the target has to be owned here.
/// Keyed by the control's object identity, and swapped rather than replaced on
/// reinstall: `Button.commit` reinstalls the handler on every update
/// (`Sources/SwiftCrossUI/Views/Button.swift:349`), and adding a second target
/// each time would fire the handler once per commit that had ever happened.
///
/// control event 所投遞到的那個 target 物件。
///
/// `UIControl` 對其 target 是弱持有，因此該 target 必須由此處擁有。以 control 的物件識別為鍵，
/// 且在重新安裝時是替換 closure 而非替換整個物件：`Button.commit` 每次更新都會重新安裝 handler
/// （`Sources/SwiftCrossUI/Views/Button.swift:349`），若每次都再加一個 target，handler 就會依照
/// 歷來發生過的 commit 次數被重複觸發。
@MainActor
final class UIKitButtonPressTarget: NSObject {
    private static var targets: [ObjectIdentifier: UIKitButtonPressTarget] = [:]

    private weak var control: UIControl?
    private var handler: (Bool) -> Void
    private var reported = false

    private init(control: UIControl, handler: @escaping (Bool) -> Void) {
        self.control = control
        self.handler = handler
        super.init()
    }

    static func install(on control: UIControl, handler: @escaping (Bool) -> Void) {
        let key = ObjectIdentifier(control)

        if let existing = targets[key] {
            existing.handler = handler
            return
        }

        targets = targets.filter { $0.value.control != nil }

        let target = UIKitButtonPressTarget(control: control, handler: handler)
        targets[key] = target

        // `.touchDownRepeat` is in the "down" list because the second tap of a
        // double tap arrives as that and not as `.touchDown`; without it a
        // double tap would report a release with no matching press.
        // `.touchDownRepeat` 之所以列在「按下」這組，是因為雙擊的第二下是以它、而非以 `.touchDown`
        // 抵達；少了它，一次雙擊會回報一次沒有對應按壓的放開。
        for event in [UIControl.Event.touchDown, .touchDownRepeat, .touchDragEnter] {
            control.addTarget(
                target,
                action: #selector(UIKitButtonPressTarget.pressed),
                for: event
            )
        }

        for event in [
            UIControl.Event.touchDragExit,
            .touchUpInside,
            .touchUpOutside,
            .touchCancel,
        ] {
            control.addTarget(
                target,
                action: #selector(UIKitButtonPressTarget.released),
                for: event
            )
        }
    }

    @objc
    private func pressed() {
        report(true)
    }

    @objc
    private func released() {
        report(false)
    }

    private func report(_ pressed: Bool) {
        guard pressed != reported else { return }
        reported = pressed
        handler(pressed)
    }
}
