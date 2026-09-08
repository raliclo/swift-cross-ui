@_spi(Backends) import SwiftCrossUI
import UIKit

final class ButtonWidget: WrapperWidget<UIButton> {
    private let event: UIControl.Event

    var onTap: (() -> Void)? {
        didSet {
            if oldValue == nil {
                child.addTarget(self, action: #selector(buttonTapped), for: event)
            }
        }
    }

    @objc
    func buttonTapped() {
        onTap?()
    }

    init() {
        #if os(tvOS)
            event = .primaryActionTriggered
        #else
            event = .touchUpInside
        #endif
        super.init(child: UIButton(type: .system))
    }
}

final class TextFieldWidget: WrapperWidget<UITextField>, UITextFieldDelegate {
    var onChange: ((String) -> Void)?
    var onSubmit: (() -> Void)?

    @objc
    func textChanged() {
        onChange?(child.text ?? "")
    }

    init() {
        super.init(child: UITextField())

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textChanged),
            name: UITextField.textDidChangeNotification,
            object: child
        )
        child.delegate = self
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        onSubmit?()
        return false
    }
}

final class TextEditorWidget: WrapperWidget<UITextView>, UITextViewDelegate {
    var onChange: ((String) -> Void)?
    var isEditable: Bool = true {
        didSet {
            #if os(tvOS)
                if !isEditable {
                    child.resignFirstResponder()
                }
            #else
                child.isEditable = isEditable
            #endif
        }
    }

    init() {
        super.init(child: UITextView())
        child.delegate = self
    }

    func textViewDidChange(_: UITextView) {
        onChange?(child.text ?? "")
    }

    func textViewShouldBeginEditing(_: UITextView) -> Bool {
        return isEditable
    }
}

#if os(tvOS)
    final class SwitchWidget: WrapperWidget<UISegmentedControl> {
        var onChange: ((Bool) -> Void)?

        @objc
        func switchFlipped() {
            onChange?(child.selectedSegmentIndex == 1)
        }

        init() {
            // TODO: localization?
            super.init(
                child: UISegmentedControl(items: [
                    "OFF" as NSString,
                    "ON" as NSString,
                ])
            )

            child.addTarget(self, action: #selector(switchFlipped), for: .valueChanged)
        }

        func setOn(_ on: Bool) {
            child.selectedSegmentIndex = on ? 1 : 0
        }
    }
#else
    final class SwitchWidget: WrapperWidget<UISwitch> {
        var onChange: ((Bool) -> Void)?

        @objc
        func switchFlipped() {
            onChange?(child.isOn)
        }

        init() {
            super.init(child: UISwitch())

            // On iOS 14 and later, UISwitch can be either a switch or a checkbox (and I believe
            // it's a checkbox by default on Mac Catalyst). We have no control over this on
            // iOS 13, but when possible, prefer a switch.
            if #available(iOS 14, macCatalyst 14, *) {
                child.preferredStyle = .sliding
            }

            child.addTarget(self, action: #selector(switchFlipped), for: .valueChanged)
        }

        func setOn(_ on: Bool) {
            child.setOn(on, animated: true)
        }
    }
#endif

final class TappableWidget: ContainerWidget {
    private var tapGestureRecognizer: UITapGestureRecognizer?
    private var longPressGestureRecognizer: UILongPressGestureRecognizer?

    var onTap: (() -> Void)? {
        didSet {
            if onTap != nil && tapGestureRecognizer == nil {
                let gestureRecognizer = UITapGestureRecognizer(
                    target: self,
                    action: #selector(viewTouched)
                )
                child.view.addGestureRecognizer(gestureRecognizer)
                self.tapGestureRecognizer = gestureRecognizer
            } else if onTap == nil, let tapGestureRecognizer {
                child.view.removeGestureRecognizer(tapGestureRecognizer)
                self.tapGestureRecognizer = nil
            }
        }
    }

    var onLongPress: (() -> Void)? {
        didSet {
            if onLongPress != nil && longPressGestureRecognizer == nil {
                let gestureRecognizer = UILongPressGestureRecognizer(
                    target: self,
                    action: #selector(viewLongPressed(sender:))
                )
                child.view.addGestureRecognizer(gestureRecognizer)
                self.longPressGestureRecognizer = gestureRecognizer
            } else if onLongPress == nil, let longPressGestureRecognizer {
                child.view.removeGestureRecognizer(longPressGestureRecognizer)
                self.onLongPress = nil
            }
        }
    }

    @objc
    func viewTouched() {
        onTap?()
    }

    @objc
    func viewLongPressed(sender: UILongPressGestureRecognizer) {
        // GTK emits the event once as soon as the gesture is recognized.
        // UIKit emits it twice, once when it's recognized and once when you lift your finger.
        // For consistency, ignore the second event.
        if sender.state != .ended {
            onLongPress?()
        }
    }
}

#if !os(tvOS)
    final class HoverableWidget: ContainerWidget {
        private var hoverGestureRecognizer: UIHoverGestureRecognizer?

        var hoverChangesHandler: ((Bool) -> Void)? {
            didSet {
                if hoverChangesHandler != nil && hoverGestureRecognizer == nil {
                    let gestureRecognizer = UIHoverGestureRecognizer(
                        target: self,
                        action: #selector(hoveringChanged(_:))
                    )
                    child.view.addGestureRecognizer(gestureRecognizer)
                    self.hoverGestureRecognizer = gestureRecognizer
                } else if hoverChangesHandler == nil, let hoverGestureRecognizer {
                    child.view.removeGestureRecognizer(hoverGestureRecognizer)
                    self.hoverGestureRecognizer = nil
                }
            }
        }

        @objc
        func hoveringChanged(_ recognizer: UIHoverGestureRecognizer) {
            switch recognizer.state {
                case .began: hoverChangesHandler?(true)
                case .ended: hoverChangesHandler?(false)
                default: break
            }
        }
    }
#endif

@available(tvOS, unavailable)
final class SliderWidget: WrapperWidget<UISlider> {
    var onChange: ((Double) -> Void)?

    private var _decimalPlaces = 17
    var decimalPlaces: Int {
        get { _decimalPlaces }
        set {
            _decimalPlaces = max(0, min(newValue, 17))
        }
    }

    @objc
    func sliderMoved() {
        onChange?(
            (Double(child.value) * pow(10.0, Double(decimalPlaces)))
                .rounded(.toNearestOrEven)
                / pow(10.0, Double(decimalPlaces))
        )
    }

    init() {
        super.init(child: UISlider())
        child.addTarget(self, action: #selector(sliderMoved), for: .valueChanged)
    }
}

@available(tvOS, unavailable)
final class DatePickerWidget: WrapperWidget<UIDatePicker> {
    var onChange: ((Date) -> Void)? {
        didSet {
            if oldValue == nil {
                child.addTarget(self, action: #selector(dateChanged), for: .valueChanged)
            }
        }
    }

    @objc
    func dateChanged(sender: UIDatePicker) {
        onChange?(sender.date)
    }

    override var intrinsicContentSize: CGSize {
        return child.sizeThatFits(UIView.layoutFittingCompressedSize)
    }
}

extension UIKitBackend {
    public func createSimpleButton() -> Widget {
        ButtonWidget()
    }

    /// Takes the `UIButton`, not the wrapper, so a toggle can share it.
    ///
    /// `ToggleWidget` is a `WrapperWidget<UIButton>` too but not a
    /// `ButtonWidget`, and the title logic below -- the tvOS branch in
    /// particular -- is worth having in one place rather than two.
    /// 接受 `UIButton` 而非 wrapper，好讓 toggle 也能共用。
    ///
    /// `ToggleWidget` 同樣是 `WrapperWidget<UIButton>`，但並非 `ButtonWidget`；而下方的標題處理
    /// 邏輯——尤其是 tvOS 那一支——值得只存在一處，而非兩處。
    func setSimpleButtonTitle(
        _ buttonWidget: ButtonWidget,
        _ label: String,
        environment: EnvironmentValues
    ) {
        setButtonTitle(buttonWidget.child, label, environment: environment)
    }

    func setButtonTitle(
        _ button: UIButton,
        _ label: String,
        environment: EnvironmentValues
    ) {
        // tvOS's buttons change foreground color when focused. If we set an
        // attributed string for `.normal` we also have to set another for
        // `.focused` with a colour that's readable on a white background.
        // However, with that approach the label's color animates too slowly
        // and all round looks quite sloppy. Therefore, it's safest to just
        // ignore foreground color for buttons on tvOS until we have a better
        // solution.
        #if os(tvOS)
            button.setTitle(label, for: .normal)
        #else
            button.setAttributedTitle(
                UIKitBackend.attributedString(
                    text: label,
                    environment: environment,
                    // Handle Mac Catalyst
                    defaultForegroundColor: deviceClass == .desktop ? .label : .link
                ),
                for: .normal
            )
        #endif
    }

    public func updateSimpleButton(
        _ button: Widget,
        label: String,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        let buttonWidget = button as! ButtonWidget

        setSimpleButtonTitle(buttonWidget, label, environment: environment)

        buttonWidget.onTap = action
        buttonWidget.child.isEnabled = environment.isEnabled
    }

    public func createTextField() -> Widget {
        TextFieldWidget()
    }

    public func updateTextField(
        _ textField: Widget,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        let textFieldWidget = textField as! TextFieldWidget

        textFieldWidget.child.isEnabled = environment.isEnabled
        textFieldWidget.child.placeholder = placeholder
        textFieldWidget.child.font = environment.resolvedFont.uiFont
        textFieldWidget.child.textColor =
            environment.suggestedForegroundColor
                .resolve(in: environment).uiColor
        textFieldWidget.onChange = onChange
        textFieldWidget.onSubmit = onSubmit

        let (keyboardType, contentType) = splitTextContentType(environment.textContentType)
        textFieldWidget.child.keyboardType = keyboardType
        textFieldWidget.child.textContentType = contentType

        // UIKit names all four shapes on one property, so there is nothing to
        // synthesise -- see `Self.borderStyle(for:)`. Assigned unconditionally
        // rather than only on change, matching every other line in this
        // function; `borderStyle` is a plain stored property and setting it to
        // the value it already holds is not a relayout.
        //
        // UIKit 在單一屬性上為四種外形全部命名，因此沒有東西需要合成——見 `Self.borderStyle(for:)`。
        // 此處無條件指派，與本函式中其他每一行一致；`borderStyle` 是一個單純的儲存屬性，把它設成
        // 它已持有的值並不會觸發重新佈局。
        textFieldWidget.child.borderStyle = Self.borderStyle(
            for: environment.backendTextFieldStyle
        )

        #if os(iOS)
            if let updateToolbar = environment.updateToolbar {
                let toolbar =
                    (textFieldWidget.child.inputAccessoryView as? KeyboardToolbar)
                        ?? KeyboardToolbar()
                updateToolbar(toolbar, environment)
                textFieldWidget.child.inputAccessoryView = toolbar
            } else {
                textFieldWidget.child.inputAccessoryView = nil
            }
        #endif
    }

    /// Maps a ``BackendTextFieldStyle`` onto `UITextField.BorderStyle`.
    ///
    /// UIKit is the cheapest of the five to satisfy: `UITextField.BorderStyle`
    /// already enumerates exactly the shapes wanted, so this is a rename rather
    /// than an implementation. No layer work, no corner radius, no border
    /// width -- `layer.cornerRadius` and `layer.borderWidth` are used elsewhere
    /// in this backend (`UIKitBackend+Container.swift`, `RootScrollHost.swift`)
    /// and are deliberately not used here, because a hand-drawn border would
    /// not track Dynamic Type, dark mode or the system's own inset metrics the
    /// way `borderStyle` does.
    ///
    /// **`automatic` and `plain` both give `.none`, and that is correct rather
    /// than a gap.** A bare `UITextField` has `borderStyle == .none`, and a
    /// bare SwiftUI `TextField` on iOS shows no border either -- borderless
    /// *is* the platform convention here, which is what
    /// ``BackendTextFieldStyle/automatic`` promises to preserve. iOS is the
    /// mirror image of macOS, where `automatic` and `squareBorder` coincide
    /// instead.
    ///
    /// `squareBorder` is `.bezel` and not `.line`: `.line` draws a single rule
    /// under the text, which is an underline rather than a border, and would
    /// leave `squareBorder` looking like a different control from
    /// `roundedBorder` rather than the same one with different corners.
    ///
    /// - Note: Unrun. This backend cannot be built or executed on the Windows
    ///   machine this was written on, so it is implemented by reading UIKit's
    ///   interface rather than by observing it.
    ///
    /// UIKit 是五者中最省事的：`UITextField.BorderStyle` 本來就列舉了正好想要的那些外形，因此這裡
    /// 是一次改名而非一次實作。沒有 layer 的操作、沒有圓角半徑、沒有邊框寬度——`layer.cornerRadius`
    /// 與 `layer.borderWidth` 在本 backend 的其他地方有用到，但此處刻意不用，因為手繪的邊框不會像
    /// `borderStyle` 那樣跟隨 Dynamic Type、深色模式與系統自身的內縮度量。
    ///
    /// **`automatic` 與 `plain` 同樣得到 `.none`，這是正確的，而不是一個缺口。** 一個未加設定的
    /// `UITextField` 其 `borderStyle` 就是 `.none`，而 iOS 上未加修飾的 SwiftUI `TextField` 同樣不
    /// 顯示邊框——無邊框**就是**此處的平台慣例，而那正是 ``BackendTextFieldStyle/automatic`` 承諾要
    /// 保留的東西。iOS 是 macOS 的鏡像，後者則是 `automatic` 與 `squareBorder` 重合。
    ///
    /// `squareBorder` 對應 `.bezel` 而非 `.line`：`.line` 只在文字下方畫一條線，那是底線而非邊框，
    /// 會讓 `squareBorder` 看起來像是與 `roundedBorder` 不同的控制項，而不是同一個控制項換了轉角。
    ///
    /// - Note: 未實際執行。撰寫本程式碼的 Windows 機器無法建置或執行此 backend，因此它是靠閱讀
    ///   UIKit 的介面實作的，而非靠觀察其行為。
    static func borderStyle(
        for style: BackendTextFieldStyle
    ) -> UITextField.BorderStyle {
        switch style {
            case .automatic, .plain:
                .none
            case .roundedBorder:
                .roundedRect
            case .squareBorder:
                .bezel
        }
    }

    public func setContent(ofTextField textField: Widget, to content: String) {
        (textField as! TextFieldWidget).child.text = content
    }

    public func getContent(ofTextField textField: Widget) -> String {
        (textField as! TextFieldWidget).child.text ?? ""
    }

    public func createSecureField() -> Widget {
        let textField = TextFieldWidget()
        textField.child.isSecureTextEntry = true
        return textField
    }

    public func updateSecureField(
        _ secureField: Widget,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        updateTextField(
            secureField,
            placeholder: placeholder,
            environment: environment,
            onChange: onChange,
            onSubmit: onSubmit
        )
    }

    public func setContent(ofSecureField secureField: Widget, to content: String) {
        setContent(ofTextField: secureField, to: content)
    }

    public func getContent(ofSecureField secureField: Widget) -> String {
        getContent(ofTextField: secureField)
    }

    public func createTextEditor() -> Widget {
        let widget = TextEditorWidget()
        widget.child.backgroundColor = .clear
        widget.child.textContainer.lineFragmentPadding = 0
        widget.child.textContainerInset = .zero
        return widget
    }

    public func updateTextEditor(
        _ textEditor: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void
    ) {
        let textEditorWidget = textEditor as! TextEditorWidget

        textEditorWidget.isEditable = environment.isEnabled
        textEditorWidget.child.font = environment.resolvedFont.uiFont
        textEditorWidget.child.textColor =
            environment.suggestedForegroundColor
                .resolve(in: environment).uiColor
        textEditorWidget.onChange = onChange

        let (keyboardType, contentType) = splitTextContentType(environment.textContentType)
        textEditorWidget.child.keyboardType = keyboardType
        textEditorWidget.child.textContentType = contentType

        #if os(iOS)
            if let updateToolbar = environment.updateToolbar {
                let toolbar =
                    (textEditorWidget.child.inputAccessoryView as? KeyboardToolbar)
                        ?? KeyboardToolbar()
                updateToolbar(toolbar, environment)
                textEditorWidget.child.inputAccessoryView = toolbar
            } else {
                textEditorWidget.child.inputAccessoryView = nil
            }

            textEditorWidget.child.alwaysBounceVertical =
                environment.scrollDismissesKeyboardMode != .never
            textEditorWidget.child.keyboardDismissMode =
                switch environment.scrollDismissesKeyboardMode {
                    case .automatic:
                        textEditorWidget.child.inputAccessoryView == nil
                            ? .interactive : .interactiveWithAccessory
                    case .immediately:
                        textEditorWidget.child.inputAccessoryView == nil
                            ? .onDrag : .onDragWithAccessory
                    case .interactively:
                        textEditorWidget.child.inputAccessoryView == nil
                            ? .interactive : .interactiveWithAccessory
                    case .never:
                        .none
                }
        #endif
    }

    public func setContent(ofTextEditor textEditor: Widget, to content: String) {
        let textEditorWidget = textEditor as! TextEditorWidget
        textEditorWidget.child.text = content
    }

    public func getContent(ofTextEditor textEditor: Widget) -> String {
        let textEditorWidget = textEditor as! TextEditorWidget
        return textEditorWidget.child.text ?? ""
    }

    // Splits a SwiftCrossUI TextContentType into a UIKit keyboard type and
    // text content type.
    private func splitTextContentType(
        _ textContentType: TextContentType
    ) -> (UIKeyboardType, UITextContentType?) {
        switch textContentType {
            case .text:
                return (.default, nil)
            case .digits(ascii: false):
                return (.numberPad, nil)
            case .digits(ascii: true):
                return (.asciiCapableNumberPad, nil)
            case .url:
                return (.URL, .URL)
            case .phoneNumber:
                return (.phonePad, .telephoneNumber)
            case .name:
                return (.namePhonePad, .name)
            case .decimal(signed: false):
                return (.decimalPad, nil)
            case .decimal(signed: true):
                return (.numbersAndPunctuation, nil)
            case .emailAddress:
                return (.emailAddress, .emailAddress)
        }
    }

    public func createSwitch() -> Widget {
        SwitchWidget()
    }

    public func updateSwitch(
        _ switchWidget: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let wrapper = switchWidget as! SwitchWidget
        wrapper.onChange = onChange
        wrapper.child.isEnabled = environment.isEnabled
    }

    public func setState(ofSwitch switchWidget: Widget, to state: Bool) {
        let wrapper = switchWidget as! SwitchWidget
        wrapper.setOn(state)
    }

    #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
        public func createSlider() -> Widget {
            SliderWidget()
        }

        public func updateSlider(
            _ slider: Widget,
            minimum: Double,
            maximum: Double,
            decimalPlaces: Int,
            environment: EnvironmentValues,
            onChange: @escaping (Double) -> Void
        ) {
            let sliderWidget = slider as! SliderWidget
            sliderWidget.child.minimumValue = Float(minimum)
            sliderWidget.child.maximumValue = Float(maximum)
            sliderWidget.child.isEnabled = environment.isEnabled
            sliderWidget.onChange = onChange
            sliderWidget.decimalPlaces = decimalPlaces
        }

        public func setValue(ofSlider slider: Widget, to value: Double) {
            let sliderWidget = slider as! SliderWidget
            sliderWidget.child.setValue(Float(value), animated: true)
        }
    #else
        public func createSlider() -> Widget {
            fatalError("\(Self.self): \(#function) not implemented")
        }

        public func updateSlider(
            _ slider: Widget,
            minimum: Double,
            maximum: Double,
            decimalPlaces: Int,
            environment: EnvironmentValues,
            onChange: @escaping (Double) -> Void
        ) {
            fatalError("\(Self.self): \(#function) not implemented")
        }

        public func setValue(ofSlider slider: Widget, to value: Double) {
            fatalError("\(Self.self): \(#function) not implemented")
        }
    #endif
}

extension UIKitBackend: BackendFeatures.TapGestures {
    public func createTapGestureTarget(wrapping child: Widget, gesture _: TapGesture) -> Widget {
        TappableWidget(child: child)
    }

    public func updateTapGestureTarget(
        _ tapGestureTarget: Widget,
        gesture: TapGesture,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        let wrapper = tapGestureTarget as! TappableWidget
        switch gesture.kind {
            case .primary:
                wrapper.onTap = environment.isEnabled ? action : {}
                wrapper.onLongPress = nil
            case .secondary, .longPress:
                wrapper.onTap = nil
                wrapper.onLongPress = environment.isEnabled ? action : {}
        }
    }
}

#if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
    extension UIKitBackend: BackendFeatures.HoverGestures {
        public func createHoverTarget(wrapping child: Widget) -> Widget {
            HoverableWidget(child: child)
        }

        public func updateHoverTarget(
            _ hoverTarget: any WidgetProtocol,
            environment: EnvironmentValues,
            action: @escaping (Bool) -> Void
        ) {
            let wrapper = hoverTarget as! HoverableWidget
            wrapper.hoverChangesHandler = action
        }
    }

    extension UIKitBackend: BackendFeatures.DatePickers {
        public nonisolated var supportedDatePickerStyles: [BackendDatePickerStyle] {
            if #available(iOS 14, macCatalyst 14, *) {
                [.automatic, .graphical, .compact, .wheel]
            } else if #available(iOS 13.4, macCatalyst 13.4, *) {
                [.automatic, .compact, .wheel]
            } else {
                [.automatic]
            }
        }

        public func createDatePicker() -> Widget {
            DatePickerWidget()
        }

        public func updateDatePicker(
            _ datePicker: Widget,
            environment: EnvironmentValues,
            date: Date,
            range: ClosedRange<Date>,
            components: DatePickerComponents,
            onChange: @escaping (Date) -> Void
        ) {
            let datePickerWidget = datePicker as! DatePickerWidget

            datePickerWidget.child.date = date
            datePickerWidget.onChange = onChange

            datePickerWidget.child.isEnabled = environment.isEnabled
            datePickerWidget.child.calendar = environment.calendar
            datePickerWidget.child.timeZone = environment.timeZone
            datePickerWidget.child.minimumDate = range.lowerBound
            datePickerWidget.child.maximumDate = range.upperBound

            datePickerWidget.child.datePickerMode =
                switch components {
                    case [.date, .hourAndMinute]:
                        .dateAndTime
                    case .date:
                        .date
                    case .hourAndMinute:
                        .time
                    default:
                        // Crashing upon receiving [] is consistent with SwiftUI.
                        fatalError("Unexpected Components: \(components)")
                }

            if #available(iOS 13.4, macCatalyst 13.4, *) {
                switch environment.backendDatePickerStyle {
                    case .automatic:
                        datePickerWidget.child.preferredDatePickerStyle = .automatic
                    case .compact:
                        datePickerWidget.child.preferredDatePickerStyle = .compact
                    case .graphical:
                        guard #available(iOS 14, macCatalyst 14, *) else {
                            preconditionFailure(
                                "DatePickerStyle.graphical is only available on iOS 14 or newer"
                            )
                        }
                        datePickerWidget.child.preferredDatePickerStyle = .inline
                    case .wheel:
                        datePickerWidget.child.preferredDatePickerStyle = .wheels
                }
            }
        }
    }
#endif
