import UIKit
@_spi(Backends) import SwiftCrossUI

protocol CheckboxWidget: WidgetProtocol {
    var state: Bool { get set }

    func update(environment: EnvironmentValues, onChange: @escaping (Bool) -> Void)
}

#if targetEnvironment(macCatalyst)
    @available(macCatalyst 14, *)
    final class UISwitchCheckbox: WrapperWidget<UISwitch>, CheckboxWidget {
        private var onChange: ((Bool) -> Void)?

        init() {
            let child = UISwitch()
            child.preferredStyle = .checkbox

            super.init(child: child)

            child.addTarget(self, action: #selector(switchChanged(sender:)), for: .valueChanged)
        }

        var state: Bool {
            get { child.isOn }
            set { child.isOn = newValue }
        }

        func update(environment: EnvironmentValues, onChange: @escaping (Bool) -> Void) {
            child.isEnabled = environment.isEnabled
            // The checkbox's checked fill in the tint. 核取方塊勾選時的填色用 tint。
            child.onTintColor = environment.tint?.resolve(in: environment).uiColor
            self.onChange = onChange
        }

        @objc func switchChanged(sender: UISwitch) {
            onChange?(sender.isOn)
        }
    }
#endif

final class UIButtonCheckbox: WrapperWidget<UIButton>, CheckboxWidget {
    private static let image = UIImage(systemName: "checkmark")

    var state = false {
        didSet {
            if state {
                child.setImage(Self.image, for: .normal)
            } else {
                child.setImage(nil, for: .normal)
            }
            applyFill()
        }
    }

    /// The checked fill; nil is systemBlue. 勾選時的填色;nil 為 systemBlue。
    var tint: UIColor? {
        didSet { applyFill() }
    }

    private func applyFill() {
        #if !os(tvOS)
            child.backgroundColor = child
                .isEnabled && state ? (tint ?? .systemBlue) : .secondarySystemFill
        #endif
    }

    private var onChange: ((Bool) -> Void)?

    override var intrinsicContentSize: CGSize {
        let buttonSize = child.intrinsicContentSize
        let size = max(buttonSize.width, buttonSize.height)
        return CGSize(width: size, height: size)
    }

    init() {
        let child = UIButton(type: .system)
        child.contentEdgeInsets = .zero

        super.init(child: child)

        let event: UIControl.Event
        #if os(tvOS)
            event = .primaryActionTriggered
        #else
            event = .touchUpInside
            child.layer.cornerRadius = 10.0
        #endif
        child.addTarget(self, action: #selector(tapped), for: event)
    }

    func update(environment: EnvironmentValues, onChange: @escaping (Bool) -> Void) {
        child.isEnabled = environment.isEnabled
        child.imageView?.tintColor = UIKitBackend.resolvedForegroundColor(environment)
        // Dimmed when disabled: the unchecked box is a flat fill that looks the
        // same either way, and P21 showed the enabled and disabled checkboxes as
        // two identical grey squares.
        // 停用時變淡:未勾選的方塊是一塊平塗,啟用與停用看起來一樣,P21 把兩者顯示成兩個相同的灰色方塊。
        child.alpha = environment.isEnabled ? 1 : 0.4
        self.onChange = onChange
        // The checked fill in the tint, systemBlue without one. 勾選時的填色用 tint,沒有時是 systemBlue。
        tint = environment.tint?.resolve(in: environment).uiColor
    }

    @objc func tapped() {
        state.toggle()
        onChange?(state)
    }
}

extension UIKitBackend {
    public func createCheckbox() -> any WidgetProtocol {
        #if targetEnvironment(macCatalyst)
            if #available(macCatalyst 14, *),
               UIDevice.current.userInterfaceIdiom == .mac
            {
                return UISwitchCheckbox()
            }
        #endif

        return UIButtonCheckbox()
    }

    public func updateCheckbox(
        _ checkboxWidget: any WidgetProtocol,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let widget = checkboxWidget as! any CheckboxWidget
        widget.update(environment: environment, onChange: onChange)
    }

    public func setState(ofCheckbox checkboxWidget: any WidgetProtocol, to state: Bool) {
        let widget = checkboxWidget as! any CheckboxWidget

        widget.state = state
    }
}
