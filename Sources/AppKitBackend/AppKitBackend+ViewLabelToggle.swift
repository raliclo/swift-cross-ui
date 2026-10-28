import AppKit
@_spi(Backends) import SwiftCrossUI

/// A button-style toggle whose label is a SwiftCrossUI view.
///
/// The bezel is the same `NSCustomToggleButton` with `.pushOnPushOff` that a
/// string-label toggle uses (`createToggle()`), filled with the accent colour,
/// or the app's `toggleColor`, while on. The label is laid over it, as
/// `NSCustomButton` lays a view label over its bezel. Every click on the
/// container -- bezel or label -- is taken by the container itself
/// (`hitTest`), so a click on the label flips the toggle. VoiceOver sees one
/// element: a checkbox with the toggle subrole, named by the label's texts,
/// whose value is the state, as AppKit exposes a push-on/push-off button.
///
/// 標籤為 SwiftCrossUI view 的按鈕樣式 toggle。
///
/// 外框與字串標籤 toggle(`createToggle()`)所用的相同：一個 `.pushOnPushOff` 的 `NSCustomToggleButton`,開啟時以強調色
/// (或 app 的 `toggleColor`)填滿。標籤疊在它上面，與 `NSCustomButton` 把 view 標籤疊在外框上相同。容器上的每一次點擊
/// ——外框或標籤——都由容器自己接收(`hitTest`),因此點擊標籤會翻轉 toggle。VoiceOver 只看到一個元素：一個帶 toggle
/// subrole 的 checkbox,以標籤的文字命名，值為其狀態，與 AppKit 呈現 push-on/push-off 按鈕的方式相同。
final class NSViewLabelToggle: NSView {
    fileprivate let bezel = NSCustomToggleButton()
    fileprivate let label: NSView
    fileprivate var onChange: ((Bool) -> Void)?
    private var isPressed = false

    fileprivate var isOn = false {
        didSet {
            applyState()
        }
    }

    fileprivate var isEnabled = true {
        didSet {
            bezel.isEnabled = isEnabled
            if !isEnabled {
                isPressed = false
                bezel.isHighlighted = false
            }
        }
    }

    init(label: NSView) {
        self.label = label
        super.init(frame: .zero)

        bezel.setButtonType(.pushOnPushOff)
        bezel.title = ""
        bezel.isBordered = true
        bezel.bezelStyle = .flexiblePush
        bezel.translatesAutoresizingMaskIntoConstraints = false
        bezel.setAccessibilityElement(false)
        addSubview(bezel)
        NSLayoutConstraint.activate([
            bezel.leadingAnchor.constraint(equalTo: leadingAnchor),
            bezel.trailingAnchor.constraint(equalTo: trailingAnchor),
            bezel.topAnchor.constraint(equalTo: topAnchor),
            bezel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    fileprivate func applyState() {
        bezel.state = isOn ? .on : .off
        bezel.bezelColor = isOn ? bezel.effectiveOnStateBezelColor : nil
    }

    /// Flips the toggle as a click does, and reports the new state.
    /// 像一次點擊那樣翻轉 toggle,並回報新狀態。
    private func flip() {
        guard isEnabled else { return }
        isOn.toggle()
        onChange?(isOn)
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    // MARK: Mouse and keyboard / 滑鼠與鍵盤

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        bezel.isHighlighted = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, isPressed else { return }
        bezel.isHighlighted = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, isPressed else { return }
        isPressed = false
        bezel.isHighlighted = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            flip()
        }
    }

    override var acceptsFirstResponder: Bool {
        isEnabled && NSApplication.shared.isFullKeyboardAccessEnabled
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        bezel.cell?.drawFocusRingMask(withFrame: bounds, in: self)
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, event.charactersIgnoringModifiers == " " else {
            super.keyDown(with: event)
            return
        }
        flip()
    }

    // MARK: Accessibility / 輔助使用

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .toggle }

    override func accessibilityLabel() -> String? {
        if let explicit = super.accessibilityLabel(), !explicit.isEmpty {
            return explicit
        }
        var texts: [String] = []
        Self.collectTexts(in: label, into: &texts)
        return texts.isEmpty ? nil : texts.joined(separator: " ")
    }

    override func accessibilityValue() -> Any? {
        NSNumber(value: isOn ? 1 : 0)
    }

    override func accessibilityPerformPress() -> Bool {
        flip()
        return isEnabled
    }

    override func isAccessibilityEnabled() -> Bool { isEnabled }

    override func accessibilityChildren() -> [Any]? { [] }

    /// Hides the label's text fields from VoiceOver, which reads their text as
    /// this element's name instead. / 讓 VoiceOver 不單獨讀取標籤裡的文字欄位，改以其文字作為本元素的名稱。
    fileprivate func hideLabelFromAccessibility(_ view: NSView? = nil) {
        let view = view ?? label
        view.setAccessibilityElement(false)
        for subview in view.subviews {
            hideLabelFromAccessibility(subview)
        }
    }

    private static func collectTexts(in view: NSView, into texts: inout [String]) {
        if let field = view as? NSTextField, !field.stringValue.isEmpty {
            texts.append(field.stringValue)
            return
        }
        for subview in view.subviews {
            collectTexts(in: subview, into: &texts)
        }
    }
}

extension AppKitBackend: BackendFeatures.ViewLabelToggleButtons {
    public func createToggle(wrapping widget: Widget) -> Widget {
        let toggle = NSViewLabelToggle(label: widget)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }

    public func updateToggle(
        _ toggle: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let toggle = toggle as! NSViewLabelToggle
        toggle.onChange = onChange
        toggle.isEnabled = environment.isEnabled
        toggle.bezel.onStateBezelColor = environment.toggleColor?
            .resolve(in: environment).nsColor
        // Re-applied here as `updateToggle(_:label:environment:onChange:)` does,
        // so a colour change while the toggle is on repaints.
        // 與 `updateToggle(_:label:environment:onChange:)` 相同，在此重新套用，讓開啟中顏色改變時重繪。
        toggle.applyState()
        toggle.hideLabelFromAccessibility()
    }

    public func setState(ofViewLabelToggle toggle: Widget, to state: Bool) {
        let toggle = toggle as! NSViewLabelToggle
        if toggle.isOn != state {
            toggle.isOn = state
        }
    }

    /// The bordered button's padding: the toggle's bezel is the same push
    /// button bezel. / 帶框按鈕的 padding:toggle 的外框就是同一種按鈕外框。
    public func toggleButtonPadding(in environment: EnvironmentValues) -> SIMD2<Int> {
        measureBorderedButtonPadding()
    }

    /// White on the filled (on) bezel, as AppKit draws the title of a
    /// push-on/push-off button on its accent fill; dimmed when disabled, as a
    /// bordered button's label is. An app's own colour wins.
    /// 填滿(開)的外框上用白色，與 AppKit 在強調色填色上畫 push-on/push-off 按鈕標題的方式相同；停用時變淡，與帶框按鈕的
    /// 標籤相同。app 自己的顏色優先。
    public func computeToggleLabelEnvironment(
        from environment: EnvironmentValues,
        isOn: Bool
    ) -> EnvironmentValues {
        guard environment.foregroundColor == nil else { return environment }
        if !environment.isEnabled {
            return environment.with(
                \.foregroundColor, environment.suggestedForegroundColor.opacity(0.3)
            )
        }
        return isOn ? environment.with(\.foregroundColor, .white) : environment
    }
}
