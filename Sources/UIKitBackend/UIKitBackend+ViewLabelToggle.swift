import UIKit
@_spi(Backends) import SwiftCrossUI

/// A button-style toggle whose label is a SwiftCrossUI view.
///
/// Drawn as a string-label toggle (`ToggleWidget`, a selected system button)
/// is drawn: a borderless label in the tint while off, and the tint filled
/// behind a white label, with 6 pt corners, while on. The label is laid over a `UIControl` with its own
/// interaction switched off, so a tap on the label is a tap on the toggle.
/// VoiceOver sees one element named by the label's texts, with the
/// toggle-button trait (iOS 17 and later; the button trait before) and
/// `.selected` while on.
///
/// 標籤為 SwiftCrossUI view 的按鈕樣式 toggle。
///
/// 畫法與字串標籤 toggle(`ToggleWidget`,被選取的系統按鈕)相同：關時是強調色的無框標籤，開時在白色標籤後填滿強調色、6 pt 圓角。標籤疊在一個
/// `UIControl` 上並關閉自身的互動，因此點擊標籤就是點擊 toggle。VoiceOver 只看到一個元素，以標籤的文字命名，帶 toggle-button
/// 特徵(iOS 17 起；之前為 button)以及開啟時的 `.selected`。
final class ViewLabelToggleControl: UIControl {
    let label: UIView
    var onChange: ((Bool) -> Void)?

    var isOn = false {
        didSet {
            updateAppearance()
        }
    }

    init(label: UIView) {
        self.label = label
        super.init(frame: .zero)
        label.isUserInteractionEnabled = false
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        layer.cornerRadius = 6
        isAccessibilityElement = true
        #if os(tvOS)
            addTarget(self, action: #selector(tapped), for: .primaryActionTriggered)
        #else
            addTarget(self, action: #selector(tapped), for: .touchUpInside)
        #endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc
    private func tapped() {
        isOn.toggle()
        onChange?(isOn)
    }

    override var isHighlighted: Bool {
        didSet {
            label.alpha = isHighlighted ? 0.4 : 1
        }
    }

    func updateAppearance() {
        backgroundColor = isOn ? tintColor : nil
        accessibilityLabel = UIKitBackend.firstText(in: self)
        var traits: UIAccessibilityTraits = .button
        if #available(iOS 17.0, tvOS 17.0, macCatalyst 17.0, *) {
            traits = .toggleButton
        }
        if isOn {
            traits.insert(.selected)
        }
        if !isEnabled {
            traits.insert(.notEnabled)
        }
        accessibilityTraits = traits
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateAppearance()
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        tapped()
        return true
    }
}

final class ViewLabelToggleWidget: WrapperWidget<ViewLabelToggleControl> {}

extension UIKitBackend: BackendFeatures.ViewLabelToggleButtons {
    public func createToggle(wrapping widget: Widget) -> Widget {
        ViewLabelToggleWidget(child: ViewLabelToggleControl(label: widget as! UIView))
    }

    public func updateToggle(
        _ toggle: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let control = (toggle as! ViewLabelToggleWidget).child
        control.onChange = onChange
        control.isEnabled = environment.isEnabled
        // As `updateToggle(_:label:environment:onChange:)` dims a disabled toggle.
        // 與 `updateToggle(_:label:environment:onChange:)` 讓停用的 toggle 變淡的方式相同。
        control.alpha = environment.isEnabled ? 1 : 0.4
        control.updateAppearance()
    }

    public func setState(ofViewLabelToggle toggle: Widget, to state: Bool) {
        let control = (toggle as! ViewLabelToggleWidget).child
        if control.isOn != state {
            control.isOn = state
        }
    }

    /// What a `UIButton(type: .system)` -- the control behind a string-label
    /// toggle -- adds around its title, measured once.
    /// 一個 `UIButton(type: .system)`(字串標籤 toggle 背後的控制項)在其標題周圍增加的空間，量一次。
    public func toggleButtonPadding(in environment: EnvironmentValues) -> SIMD2<Int> {
        if let padding = Self.measuredTogglePadding {
            return padding
        }
        let button = UIButton(type: .system)
        button.setTitle("Teststring", for: .normal)
        let buttonSize = button.intrinsicContentSize
        let textSize = button.titleLabel?.intrinsicContentSize ?? .zero
        let padding = SIMD2(
            max(Int((buttonSize.width - textSize.width).rounded()), 0),
            max(Int((buttonSize.height - textSize.height).rounded()), 0)
        )
        Self.measuredTogglePadding = padding
        return padding
    }

    @MainActor static var measuredTogglePadding: SIMD2<Int>?

    /// White on the filled (on) toggle and the tint otherwise, as a selected and an
    /// unselected system button draw their titles; an app's own colour wins.
    /// 開(填滿)時白色、其他時候強調色，與被選取及未選取的系統按鈕畫標題的方式相同;app 自己的顏色優先。
    public func computeToggleLabelEnvironment(
        from environment: EnvironmentValues,
        isOn: Bool
    ) -> EnvironmentValues {
        guard environment.foregroundColor == nil, deviceClass != .desktop else {
            return environment
        }
        return environment.with(\.foregroundColor, isOn ? .white : .system(.blue))
    }
}
