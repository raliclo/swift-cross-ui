import UIKit
import SwiftCrossUI

extension UIKitBackend {
    public func createButton(wrapping widget: Widget) -> Widget {
        let widget = widget as! UIView
        let button = UICustomButton(label: widget)

        button.translatesAutoresizingMaskIntoConstraints = false
        widget.isUserInteractionEnabled = false
        button.isUserInteractionEnabled = true

        return CustomButtonWidget(button: button)
    }

    public func updateButton(
        _ button: Widget,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        let button = (button as! CustomButtonWidget).child
        button.onTap = action
        button.isEnabled = environment.isEnabled
        button.buttonStyle = environment.resolvedButtonStyle.kind

        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, *) {
            button.configuration = switch environment.resolvedButtonStyle.kind {
                case .bordered: .bordered()
                case .borderless: .borderless()
                case .plain: .plain()
            }
        }

        // Automatically sets the label text of a Button("") {} as accessibilityLabel.
        // This should be improved via a future .accessibilityLabel(_:) modifier.
        // The ViewBuilder button init is not covered by this current solution.
        // Searched, not indexed.
        //
        // This was `button.subviews[1] as? WrapperWidget<TextView>`, which is
        // the same shape that made every AppKit button unnamed: it holds only
        // while the label is that exact type at that exact index. A button whose
        // label is wrapped in anything -- a padding, a frame, an HStack of two
        // texts -- silently got no name at all, and nothing reports a missing
        // accessibility name.
        //
        // The AppKit half was found by dumping the tree (`78fc4b0e`); this one
        // was found by reading the code beside it afterwards, which is why it is
        // fixed the same way rather than differently.
        //
        // 用**找**的，不是用索引取的。
        //
        // 這裡原本是 `button.subviews[1] as? WrapperWidget<TextView>`——那與「讓每一顆 AppKit 按鈕
        // 都沒有名字」的是同一個形狀:它只有在「標籤恰好是那個型別、恰好在那個索引」時才成立。一顆
        // 標籤被任何東西包住的按鈕——一層 padding、一個 frame、一個由兩段文字組成的 HStack——會靜默地
        // 完全沒有名字，而「缺少 accessibility 名稱」這件事不會有任何東西回報。
        //
        // AppKit 那一半是靠傾印那棵樹找到的(`78fc4b0e`);這一半是事後讀它旁邊的程式碼時發現的
        // ——這正是它以**相同**方式修好、而不是以另一種方式修好的原因。
        button.accessibilityLabel = Self.firstText(in: button)
    }

    /// The first non-empty text anywhere below this view.
    ///
    /// An image-only button still gets nothing, and that is what
    /// `.accessibilityLabel(_:)` (#123) is for: a guess about which of several
    /// texts names a button is worse than no guess, but no text at all is a
    /// button a screen reader cannot announce.
    ///
    /// 這個 view 底下任何一層的第一段非空文字。
    ///
    /// 純圖示的按鈕仍然什麼都得不到，而那正是 `.accessibilityLabel(_:)`(#123)的用途:在數段文字之間
    /// 猜「哪一段是這顆按鈕的名字」比不猜更糟，但完全沒有文字，就是一顆螢幕閱讀器念不出來的按鈕。
    static func firstText(in view: UIView) -> String? {
        for subview in view.subviews {
            if let wrapper = subview as? WrapperWidget<TextView>, !wrapper.child.text.isEmpty {
                return wrapper.child.text
            }
            if let label = subview as? UILabel, let text = label.text, !text.isEmpty {
                return text
            }
            if let nested = firstText(in: subview) {
                return nested
            }
        }
        return nil
    }

    public func buttonPadding(in environment: EnvironmentValues) -> SIMD2<Int> {
        let borderedPadding = SIMD2(
            Int(UICustomButton.horizontalInsets),
            Int(UICustomButton.verticalInsets)
        )

        // tvOS always gets full padding, due to highlighting using
        // the highlighted state of bordered button for all styles.
        #if os(tvOS)
            return borderedPadding
        #else
            return switch environment.resolvedButtonStyle.kind {
                case .plain, .borderless: SIMD2(0, 0)
                case .bordered: borderedPadding
            }
        #endif
    }

    public func defaultButtonStyle() -> PrimitiveButtonStyle {
        .borderless
    }

    public func computeButtonLabelEnvironment(
        from environment: EnvironmentValues
    ) -> EnvironmentValues {
        var labelEnvironment = environment

        let buttonStyle = environment.resolvedButtonStyle.kind

        // Set the default foregroundColor for the label unless overridden.
        // Uses the same colors as SwiftUI.
        if
            buttonStyle == .borderless,
            deviceClass == .desktop
        {
            labelEnvironment = labelEnvironment.with(
                \.foregroundColor,
                environment.foregroundColor
                    ?? environment.suggestedForegroundColor.opacity(0.7)
            )
        } else if
            deviceClass == .phone || deviceClass == .tablet,
            buttonStyle == .borderless || buttonStyle == .bordered
        {
            labelEnvironment = labelEnvironment.with(
                \.foregroundColor,
                environment.foregroundColor ?? .blue // TODO: Replace with .accent
            )
        }

        // The disabled opacities and defaults are based on discoveries in SwiftUI.
        // iOS appears to dim even foregroundColors in the environment.sd
        if !environment.isEnabled, buttonStyle == .bordered || buttonStyle == .borderless {
            labelEnvironment = labelEnvironment.with(
                \.foregroundColor,
                environment.suggestedForegroundColor.opacity(0.3) // SwiftUI uses tertiary afaict.
            )
        }

        return labelEnvironment
    }
}

final class CustomButtonWidget: WrapperWidget<UICustomButton> {
    init(button: UICustomButton) {
        super.init(child: button)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

final class UICustomButton: UIButton {
    var label: UIView

    static var horizontalInsets: CGFloat {
        guard #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, *) else {
            return 24
        }
        let insets = UIButton.Configuration.bordered().contentInsets
        return insets.leading + insets.trailing
    }

    static var verticalInsets: CGFloat {
        guard #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, *) else {
            return 14
        }
        let insets = UIButton.Configuration.bordered().contentInsets
        return insets.bottom + insets.top
    }

    public var onTap: (() -> Void)?

    public var buttonStyle: PrimitiveButtonStyle.Kind = .borderless

    override public var isHighlighted: Bool {
        didSet {
            UIView.animate(
                withDuration: isHighlighted ? 0.1 : 0.3,
                delay: 0,
                options: [.allowUserInteraction],
                animations: { [weak self] in
                    guard let self else { return }
                    self.buttonStyle.applyModifications(self)
                },
                completion: nil
            )
        }
    }

    override public var isEnabled: Bool {
        didSet {
            self.buttonStyle.applyModifications(self)
        }
    }

    init(label: UIView) {
        self.label = label
        super.init(frame: .zero)
        addAndCenterChild(label)
        #if os(tvOS)
            addTarget(self, action: #selector(buttonTapped), for: .primaryActionTriggered)
        #else
            addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        #endif
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Ensure custom label stays above system overlays (like highlighting)
        bringSubviewToFront(label)
    }

    required init?(coder: NSCoder) {
        fatalError("NSCoder input is not supported on UICustomButton")
    }

    @objc
    func buttonTapped() {
        onTap?()
    }

    func addAndCenterChild(_ child: UIView) {
        addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.centerXAnchor.constraint(equalTo: centerXAnchor),
            child.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

extension PrimitiveButtonStyle.Kind {
    fileprivate func updateBackground(_ button: UICustomButton) {
        // We don't support bordered button style on older versions.
        guard #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, *) else {
            return
        }

        switch self {
            case .bordered:
                button.configuration = .bordered()
            case .plain, .borderless:
                // The borderless special treatment is handled in environment.
                button.configuration = .plain()
        }
    }

    fileprivate func applyModifications(_ button: UICustomButton) {
        guard #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, *) else {
            button.label.alpha = button.isEnabled
                ? button.isHighlighted ? 0.8 : 1.0
                : 0.5
            return
        }
        switch self {
            case .bordered:
                button.label.alpha = button.isEnabled ? 1.0: 0.7
            case .plain:
                button.label.alpha = button.isEnabled
                    ? (button.isHighlighted ? 0.7 : 1.0)
                    : 0.5
            // Why 50% disabled opacity was chosen:
            // A disabled SwiftUI .plain button looks visually the same as
            // an enabled one at 0.5 opacity.
            // Why 70% for active(pressed) was chosen:
            // A pressed SwiftUI .plain button looks visually the same as
            // a not pressed one at 0.7 opacity.
            case .borderless:
                button.label.alpha = button.isHighlighted ? 0.4 : 1.0
                // 40% opacity appears to be the correct amount for pressed state.
                // a blue pressed
        }
    }
}
