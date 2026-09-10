import AppKit
import SwiftCrossUI

extension AppKitBackend {
    public func createSimpleButton() -> Widget {
        NSButton()
    }

    public func updateSimpleButton(
        _ button: Widget,
        label: String,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        let button = button as! NSButton
        button.attributedTitle = Self.attributedString(
            for: label,
            in: environment.with(\.multilineTextAlignment, .center)
        )
        button.appearance = environment.colorScheme.nsAppearance
        button.isEnabled = environment.isEnabled

        button.onAction = { _ in
            action()
        }
    }

    public func createButton(
        wrapping child: Widget
    ) -> NSView {
        let button = NSCustomButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setupButton()

        button.addAndSetupLabel(child)

        return button
    }

    public func updateButton(
        _ button: NSView,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        let button = button as! NSCustomButton

        button.action = action
        button.isEnabled = environment.isEnabled
        button.buttonStyle = environment.resolvedButtonStyle.kind
        // On every update rather than at creation: the label is a child view whose
        // text changes without this button being rebuilt.
        // 每次更新都做，而非在建立時做一次：標籤是一個子 view，它的文字會在這顆按鈕未被重建的
        // 情況下改變。
        button.refreshAccessibilityLabel()
    }

    public func buttonPadding(in environment: EnvironmentValues) -> SIMD2<Int> {
        switch environment.resolvedButtonStyle.kind {
            case .bordered: measureBorderedButtonPadding()
            case .plain, .borderless: SIMD2<Int>(0, 0)
        }
    }

    public func defaultButtonStyle() -> PrimitiveButtonStyle { .bordered }

    func measureBorderedButtonPadding() -> SIMD2<Int> {
        if let borderedButtonPadding { return borderedButtonPadding }

        let testString = "E"
        let dummyButton = NSButton()
        dummyButton.title = testString
        dummyButton.controlSize = .regular
        dummyButton.sizeToFit()

        let field = NSTextField(wrappingLabelWithString: "")
        field.stringValue = testString
        field.font = dummyButton.font
        let textSize = field.intrinsicContentSize

        let buttonSize = dummyButton.intrinsicContentSize

        let result = SIMD2(
            Int(buttonSize.width - textSize.width),
            Int(buttonSize.height - textSize.height)
        )

        borderedButtonPadding = result
        return result
    }
}

public final class NSCustomButton: NSView {
    fileprivate var action: (() -> Void)?
    fileprivate let button = NSButtonBackground()
    fileprivate var buttonStyle: PrimitiveButtonStyle.Kind = .bordered {
        didSet { updateButtonAppearance() }
    }

    var isEnabled = true {
        didSet {
            if !isEnabled {
                isPressed = false
                isHighlighted = false
            }
            buttonStyle.applyModifications(self)
            needsDisplay = true
        }
    }

    // Whether left mousebutton is pressed on this view.
    private var isPressed = false

    private var highlightResetWorkItem: DispatchWorkItem?

    public var isHighlighted = false {
        didSet {
            buttonStyle.applyModifications(self)
            needsDisplay = true
        }
    }

    override public func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override public func accessibilityActionNames() -> [NSAccessibility.Action] {
        return [.press]
    }

    override public func accessibilityPerformPress() -> Bool {
        self.action?()
        return true
    }

    override public func accessibilityLabel() -> String? {
        // Automatically uses the label text of a Button("") {} as accessibilityLabel.
        // This should be improved via a future .accessibilityLabel(_:) modifier.
        //
        // **The label has to reach the INNER `NSButton`, which is the element
        // accessibility actually sees.** `NSCustomButton` is a plain `NSView`, so
        // it is transparent in the accessibility tree and this override is never
        // consulted -- dumping P28's tree showed the `AXButton` and the label's
        // `AXStaticText` as SIBLINGS, which is what a transparent parent looks
        // like. Setting it here alone changed nothing; ``refreshAccessibilityLabel``
        // is what makes it visible, and this stays so the two cannot disagree.
        //
        // It reads the first text field ANYWHERE below, not `subviews.first`.
        // `setupButton` adds the `NSButton` first and `addAndSetupLabel` adds the
        // label after it, so `subviews.first` is the button and the cast to
        // `NSTextField` always failed -- this returned nil for every button in the
        // package. Dumped the accessibility tree of P17, P28 and P34 on
        // 2026-09-10: every `AXButton` had `title=''` and `desc=''`, so a screen
        // reader had nothing at all to announce. `button.title` is set to `""` a
        // few lines above, which is why the empty title is not a second bug.
        //
        // A ViewBuilder label made of several views is still not covered: the
        // first text field is a guess about which one names the button, and a
        // guess is what `.accessibilityLabel(_:)` (#123) exists to replace.
        //
        // **標籤必須送達**內層**的 `NSButton`——那才是 accessibility 真正看見的元素。**
        // `NSCustomButton` 是一個單純的 `NSView`，因此它在 accessibility 樹中是透明的，這個
        // override 從不會被詢問——傾印 P28 的樹時，`AXButton` 與標籤的 `AXStaticText` 是**兄弟**，
        // 而那正是「父節點透明」的樣子。只改這裡毫無作用；讓它現身的是 ``refreshAccessibilityLabel``，
        // 而此處保留下來，是為了讓兩者不會各說各話。
        //
        // 它讀的是「底下任何一層的第一個文字欄位」，而不是 `subviews.first`。
        // `setupButton` 先加入 `NSButton`，`addAndSetupLabel` 之後才加入標籤，因此
        // `subviews.first` 是那顆按鈕，而轉型為 `NSTextField` 永遠失敗——本套件中的每一顆按鈕
        // 在此都回傳 nil。2026-09-10 傾印了 P17、P28、P34 的 accessibility 樹：每一個
        // `AXButton` 的 `title` 與 `desc` 都是空的，螢幕閱讀器沒有任何東西可念。上方數行處
        // 將 `button.title` 設為 `""`，因此「標題為空」不是第二個錯誤。
        //
        // 由多個 view 組成的 ViewBuilder 標籤仍未涵蓋：「第一個文字欄位」是對「哪一個才是這顆
        // 按鈕的名字」的一種猜測，而 `.accessibilityLabel(_:)`(#123)存在的目的正是取代猜測。
        firstTextFieldValue(in: self)
    }

    /// Pushes the label onto the inner `NSButton`, and takes it off the label
    /// itself so it is announced once rather than twice.
    /// 把標籤推到內層的 `NSButton` 上，並將它從標籤自身移除，使它只被念一次而非兩次。
    func refreshAccessibilityLabel() {
        let text = firstTextFieldValue(in: self)
        button.setAccessibilityLabel(text)
        for subview in subviews where subview !== button {
            hideFromAccessibility(subview)
        }
    }

    private func hideFromAccessibility(_ view: NSView) {
        if view is NSTextField {
            view.setAccessibilityElement(false)
        }
        for subview in view.subviews {
            hideFromAccessibility(subview)
        }
    }

    private func firstTextFieldValue(in view: NSView) -> String? {
        for subview in view.subviews {
            if let field = subview as? NSTextField, !field.stringValue.isEmpty {
                return field.stringValue
            }
            if let nested = firstTextFieldValue(in: subview) {
                return nested
            }
        }
        return nil
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    override public var acceptsFirstResponder: Bool {
        // Even though its called FullKeyboardAccess, it's actually
        // the "Keyboard navigation" setting.
        isEnabled && NSApplication.shared.isFullKeyboardAccessEnabled
    }

    override public var focusRingMaskBounds: NSRect { bounds }

    override public func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { noteFocusRingMaskChanged() }
        return ok
    }

    override public func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { noteFocusRingMaskChanged() }
        return ok
    }

    override public func drawFocusRingMask() {
        guard isEnabled else { return }
        buttonStyle.drawFocusRingMask(on: self)
    }

    override public func keyDown(with event: NSEvent) {
        guard
            isEnabled,
            (event.charactersIgnoringModifiers ?? "") == " "
        else {
            super.keyDown(with: event)
            return
        }

        highlightResetWorkItem?.cancel()
        isHighlighted = true
        action?()

        // Task with Task.sleep could be used in the future,
        // it has a min version requirement of macOS 13.
        let workItem = DispatchWorkItem { [weak self] in
            self?.isHighlighted = false
        }
        highlightResetWorkItem = workItem

        // 0.1 highlight duration is an estimate of what it feels like.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        // Reset internal state when moved (or potentially re-used in the future).
        if newWindow == nil {
            highlightResetWorkItem?.cancel()
            isHighlighted = false
            isPressed = false
        }
    }

    override public func mouseDown(with _: NSEvent) {
        guard isEnabled else { return }

        isPressed = true
        isHighlighted = true
    }

    override public func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }

        let pointInView = convert(event.locationInWindow, from: nil)

        if isPressed && bounds.contains(pointInView) {
            isHighlighted = true
        } else {
            isHighlighted = false
        }
    }

    override public func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }

        let pointInView = self.convert(event.locationInWindow, from: nil)

        if bounds.contains(pointInView) {
            action?()
        }

        isPressed = false
        isHighlighted = false
    }

    private func updateButtonAppearance() {
        buttonStyle.applyModifications(self)
        noteFocusRingMaskChanged()
        self.needsDisplay = true
    }

    fileprivate func setupButton() {
        button.title = ""
        button.isBordered = true
        button.bezelStyle = .flexiblePush

        button.translatesAutoresizingMaskIntoConstraints = false

        addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    fileprivate func addAndSetupLabel(_ child: NSView) {
        addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.centerXAnchor.constraint(equalTo: centerXAnchor),
            child.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

// This class is needed, because you cannot set
// isUserInteractionEnabled on a regular NSButton.
private final class NSButtonBackground: NSButton {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override var canBecomeKeyView: Bool { false }

    override func drawFocusRingMask() {
        guard let cell else { return }
        var bounds = bounds
        if #unavailable(macOS 26) {
            // For some reason the focus ring drawing appears is offset
            // by the width of the focusring prior to macOS 26.
            // As far as I know the focus ring width is always 3.
            bounds.origin.x -= 3
            bounds.origin.y -= 3
        }
        cell.drawFocusRingMask(withFrame: bounds, in: self)
    }
}

extension PrimitiveButtonStyle.Kind {
    fileprivate func applyModifications(_ button: NSCustomButton) {
        button.button.isHidden = true
        switch self {
            case .bordered:
                button.button.isHidden = false
                button.button.isEnabled = button.isEnabled
                button.button.isHighlighted = button.isHighlighted
            case .plain, .borderless:
                button.alphaValue = button.isEnabled
                    ? button.isHighlighted ? 0.80: 1.0
                    : 0.5
                // Why 50% disabled opacity was chosen:
                // A disabled SwiftUI .plain button looks visually the same as
                // an enabled one at 0.5 opacity.
                // Why 80% for active(pressed) was chosen:
                // A pressed SwiftUI .plain button looks visually the same as
                // a not pressed one at 0.8 opacity.
        }
    }

    fileprivate var shouldRenderNativeBackground: Bool {
        switch self {
            case .bordered:
                true
            case .plain, .borderless:
                false
        }
    }

    fileprivate func drawFocusRingMask(on button: NSCustomButton) {
        switch self {
            case .bordered:
                button.button.drawFocusRingMask()
            case .plain, .borderless:
                let maskPath = NSBezierPath(rect: button.bounds)
                maskPath.fill()
        }
    }
}
