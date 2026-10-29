@_spi(Backends) import SwiftCrossUI
import UWP
import WinUI

/// A button-style toggle whose label is a SwiftCrossUI view: a WinUI
/// `ToggleButton`, the control a string-label toggle is (`createToggle()`),
/// with the label as its `content` instead of a `TextBlock`.
///
/// `ToggleButton` is a `ContentControl`, so the label is part of the control
/// and a click on it flips the toggle. While checked the control fills with
/// the accent colour and the label takes the opposite colour scheme, as
/// `updateToggle(_:label:environment:onChange:)` gives its `TextBlock`. UI
/// Automation sees a toggle button whose name is the label's texts; the label's
/// own elements are hidden from it, as a view-label button hides them.
///
/// 標籤為 SwiftCrossUI view 的按鈕樣式 toggle:一個 WinUI `ToggleButton`(字串標籤 toggle 用的就是它，見 `createToggle()`),
/// 以標籤作為它的 `content`,而不是一個 `TextBlock`。`ToggleButton` 是 `ContentControl`,因此標籤是控制項的一部分，點擊標籤
/// 會翻轉 toggle。勾選時控制項以強調色填滿，標籤改用相反的配色，與 `updateToggle(_:label:environment:onChange:)` 給其
/// `TextBlock` 的相同。UI Automation 看到的是一個以標籤文字命名的 toggle button;標籤自身的元素對它隱藏，與 view 標籤按鈕相同。
final class ViewLabelToggleButton: WinUI.ToggleButton {
    var onChange: ((Bool) -> Void)?

    override init() {
        super.init()
        horizontalContentAlignment = .center
        verticalContentAlignment = .center
        click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.onChange?(self.isChecked ?? false)
        }
    }

    func refreshAccessibilityName() {
        guard let label = content as? WinUI.UIElement else { return }
        let texts = Self.texts(in: label)
        AutomationProperties.setName(self, texts.joined(separator: " "))
        scuiSetAccessibilityView(ofSubtree: label, hidden: !texts.isEmpty)
    }

    private static func texts(in element: WinUI.UIElement) -> [String] {
        if let block = element as? WinUI.TextBlock {
            return block.text.isEmpty ? [] : [block.text]
        }
        return scuiChildren(of: element).flatMap(texts(in:))
    }
}

extension WinUIBackend: BackendFeatures.ViewLabelToggleButtons {
    public func createToggle(wrapping widget: Widget) -> Widget {
        let toggle = ViewLabelToggleButton()
        toggle.content = widget
        return toggle
    }

    public func updateToggle(
        _ toggle: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let toggle = toggle as! ViewLabelToggleButton
        environment.apply(to: toggle)
        toggle.onChange = onChange
        toggle.refreshAccessibilityName()
    }

    public func setState(ofViewLabelToggle toggle: Widget, to state: Bool) {
        let toggle = toggle as! ViewLabelToggleButton
        if toggle.isChecked != state {
            toggle.isChecked = state
        }
    }

    /// What a `ToggleButton` adds around a `TextBlock`, measured once.
    /// 一個 `ToggleButton` 在 `TextBlock` 周圍所增加的空間，量一次。
    public func toggleButtonPadding(in environment: EnvironmentValues) -> SIMD2<Int> {
        if let padding = Self.measuredTogglePadding {
            return padding
        }
        let dummy = ToggleButton()
        let block = TextBlock()
        block.text = "E"
        dummy.content = block
        let toggleSize = Self.naturalSize(of: dummy)
        let textSize = Self.naturalSize(of: block)
        let padding = SIMD2(toggleSize.x - textSize.x, toggleSize.y - textSize.y)
        Self.measuredTogglePadding = padding
        return padding
    }

    @MainActor static var measuredTogglePadding: SIMD2<Int>?

    /// The opposite colour scheme while checked, so the label reads on the
    /// accent fill, as the string-label toggle's `TextBlock` does.
    /// 勾選時改用相反的配色，讓標籤在強調色填色上可讀，與字串標籤 toggle 的 `TextBlock` 相同。
    public func computeToggleLabelEnvironment(
        from environment: EnvironmentValues,
        isOn: Bool
    ) -> EnvironmentValues {
        isOn ? environment.with(\.colorScheme, environment.colorScheme.opposite) : environment
    }
}
