import SwiftCrossUI
import WinUI
import UWP

extension WinUIBackend {
    public func createButton(
        wrapping widget: Widget
    ) -> Widget {
        let button = ViewLabelCustomButton()
        button.content = widget
        return button
    }

    public func updateButton(
        _ button: Widget,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        let button = button as! ViewLabelCustomButton
        button.action = action
        button.buttonStyle = environment.resolvedButtonStyle.kind
        button.enabled = environment.isEnabled
        button.refreshAccessibilityName()
    }

    public func buttonPadding(in environment: EnvironmentValues) -> SIMD2<Int> {
        switch environment.resolvedButtonStyle.kind {
            case .bordered: measureBorderedButtonPadding()
            case .plain, .borderless: SIMD2(0, 0)
        }
    }

    public func defaultButtonStyle() -> PrimitiveButtonStyle { .bordered }

    func measureBorderedButtonPadding() -> SIMD2<Int> {
        if let borderedButtonPadding { return borderedButtonPadding }

        let testString = "E"
        let dummyButton = Button()
        let block = TextBlock()
        block.text = testString
        dummyButton.content = block

        let buttonSize = Self.naturalSize(of: dummyButton)
        let textSize = Self.naturalSize(of: block)

        let result = SIMD2(
            Int(buttonSize.x - textSize.x),
            Int(buttonSize.y - textSize.y)
        )

        borderedButtonPadding = result
        return result
    }
}

/// The button behind `createButton(wrapping:)` -- the arbitrary-view label API
/// upstream added when it split buttons into `StringLabelButtons` and
/// `ViewLabelButtons` (#590). Its content is whatever `Widget` the caller passed.
///
/// There is deliberately a SECOND button class, `CustomButton` in
/// WinUIBackend.swift, and neither may be deleted in favour of the other. That
/// one owns a `TextBlock` label of its own, and three methods still depend on it:
/// `createSimpleButton()`, `updateSimpleButton(_:label:environment:action:)` and
/// `updateButton(_:label:menu:environment:)` -- the last being the menu/flyout
/// button, which has nothing to do with #590. Unlike GtkBackend, those three were
/// never moved into this file, so both classes are live. Merging them breaks menu
/// buttons.
///
/// 這是 `createButton(wrapping:)` 背後的按鈕——即上游將按鈕拆成 `StringLabelButtons` 與
/// `ViewLabelButtons`(#590)時新增的「任意 view 作為 label」API。其 content 就是呼叫端傳入的
/// `Widget`。
///
/// 這裡刻意存在第二個按鈕類別,即 WinUIBackend.swift 中的 `CustomButton`,兩者都不得為了對方而
/// 被刪除。那一個自己持有一個 `TextBlock` label,且仍有三個方法依賴它:`createSimpleButton()`、
/// `updateSimpleButton(_:label:environment:action:)` 與
/// `updateButton(_:label:menu:environment:)`——最後一個是 menu/flyout 按鈕,與 #590 無關。
/// 與 GtkBackend 不同,那三個方法從未被搬進本檔案,因此兩個類別都仍在使用中。合併它們會弄壞 menu
/// 按鈕。
/// Routes `.accessibilityLabel` to a view-label button, and reports whether
/// `widget` was one.
/// 把 `.accessibilityLabel` 交給 view-label 按鈕,並回報 `widget` 是否就是這種按鈕。
func scuiSetButtonAccessibilityLabel(_ widget: WinUI.UIElement, to label: String?) -> Bool {
    guard let button = widget as? ViewLabelCustomButton else {
        return false
    }
    button.accessibilityLabelOverride = label
    return true
}

fileprivate final class ViewLabelCustomButton: WinUI.Button {
    fileprivate var action: (() -> Void)?

    /// What `.accessibilityLabel` asked for, or `nil` where it asked for nothing.
    /// 由 `.accessibilityLabel` 所要求的標籤;未要求時為 `nil`。
    fileprivate var accessibilityLabelOverride: String? {
        didSet { refreshAccessibilityName() }
    }

    /// Names the button, and takes its content out of the automation tree once
    /// it has a name.
    ///
    /// **Without this, an unlabelled button has an EMPTY UIA Name.** Measured
    /// 2026-09-17 with p69_uia.zsh: `button name='' help='Removes the file
    /// permanently'`, with `text 'Delete'` present only as a child. XAML
    /// derives a Button's name from its content only when the content is a
    /// string, and here the content is a view. AppKitBackend derives the name
    /// from the first text in the label (`firstTextFieldValue`), and this
    /// follows it, including hiding the content so the words are announced once
    /// rather than as the button and again as its child.
    ///
    /// Runs from `updateButton` on every layout pass. That comes after the label
    /// has laid out, and `Text` writes its string during layout, so the text is
    /// already there to read. A label override, set by the modifier after this
    /// pass, wins through `accessibilityLabelOverride`. A button with no text,
    /// such as an image-only label, keeps its content exposed, because that
    /// content is all it has to say.
    ///
    /// 為按鈕命名,並在它有了名字之後把內容移出 automation 樹。
    ///
    /// **少了這一步,未設標籤的按鈕 UIA Name 是空的。** 2026-09-17 以 p69_uia.zsh 實測:
    /// `button name='' help='Removes the file permanently'`,`text 'Delete'` 只以子節點存在。XAML 只在
    /// content 是字串時才從 content 推導 Button 的名稱,而這裡的 content 是一個 view。AppKitBackend 以
    /// label 中第一段文字命名(`firstTextFieldValue`),此處照做,包括把內容藏起來,讓那些字只被念一次,
    /// 而不是按鈕念一次、子節點再念一次。
    ///
    /// 由 `updateButton` 在每一次 layout pass 呼叫。那發生在 label 排版之後,而 `Text` 在排版時就寫入
    /// 字串,所以文字已經在那裡可讀。modifier 在這一趟之後設定的標籤覆寫,經由
    /// `accessibilityLabelOverride` 勝出。沒有文字的按鈕(例如只有圖片的 label)內容保持暴露,因為那是
    /// 它唯一能說的東西。
    fileprivate func refreshAccessibilityName() {
        let label = content as? WinUI.UIElement
        let name = accessibilityLabelOverride ?? label.flatMap(Self.firstText(in:))
        AutomationProperties.setName(self, name ?? "")
        if let label {
            scuiSetAccessibilityView(ofSubtree: label, hidden: name != nil)
        }
    }

    private static func firstText(in element: WinUI.UIElement) -> String? {
        if let block = element as? WinUI.TextBlock, !block.text.isEmpty {
            return block.text
        }
        for child in scuiChildren(of: element) {
            if let text = firstText(in: child) {
                return text
            }
        }
        return nil
    }

    private var isPointerCaptured = false
    fileprivate var isHighlighted = false {
        didSet {
            buttonStyle.applyModifications(self)
        }
    }

    fileprivate var buttonStyle: PrimitiveButtonStyle.Kind = .bordered {
        didSet {
            if buttonStyle != oldValue {
                updateButtonAppearance()
            }
        }
    }

    // Sadly we can't override isEnabled due to it not being an open property
    public var enabled: Bool = true {
        didSet {
            self.isEnabled = enabled

            if !enabled {
                isPointerCaptured = false
                isHighlighted = false
            }

            buttonStyle.applyModifications(self)
        }
    }

    override init() {
        super.init()
        padding = Thickness.null
        horizontalContentAlignment = HorizontalAlignment.center
        verticalContentAlignment = VerticalAlignment.center

        click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.action?()
        }
    }

    override func onPointerPressed(_ e: PointerRoutedEventArgs!) throws {
        try super.onPointerPressed(e)
        isPointerCaptured = true
        isHighlighted = true
    }

    override func onPointerMoved(_ e: PointerRoutedEventArgs!) throws {
        try super.onPointerMoved(e)

        if isPointerCaptured {
            // Pointer position relative to the button.
            guard let currentPoint = try e.getCurrentPoint(self) else { return }
            let position = currentPoint.position

            let width = self.actualWidth
            let height = self.actualHeight

            // Apparently windows uses 0 <= x < actualWidth ¯\_(ツ)_/¯
            if
                (0..<width).contains(Double(position.x)),
                (0..<height).contains(Double(position.y))
            {
                isHighlighted = true
            } else {
                isHighlighted = false
            }
        }
    }

    override func onPointerReleased(_ event: PointerRoutedEventArgs!) throws {
        try super.onPointerReleased(event)
        isPointerCaptured = false
        isHighlighted = false
    }

    override func onPointerCaptureLost(_ event: PointerRoutedEventArgs!) throws {
        try super.onPointerCaptureLost(event)
        isPointerCaptured = false
        isHighlighted = false
    }

    override func onKeyDown(_ event: KeyRoutedEventArgs!) throws {
        try super.onKeyDown(event)

        let targetKey = event.key

        if [.space, .enter].contains(targetKey) {
            isHighlighted = true
        }
    }

    override func onKeyUp(_ event: KeyRoutedEventArgs!) throws {
        try super.onKeyUp(event)

        let targetKey = event.key

        if [.space, .enter].contains(targetKey) {
            isHighlighted = false
        }
    }

    override func onLostFocus(_ event: RoutedEventArgs!) throws {
        try super.onLostFocus(event)
        isPointerCaptured = false
        isHighlighted = false
    }

    private func updateButtonAppearance() {
        buttonStyle.applyModifications(self)
        buttonStyle.updateRenderedStyle(self)
    }
}

extension PrimitiveButtonStyle.Kind {
    fileprivate func updateRenderedStyle(_ button: ViewLabelCustomButton) {
        guard let resources = button.resources else { return }

        switch self {
            case .bordered:
                _ = try? button.clearValue(WinUI.Button.backgroundProperty)
                _ = try? button.clearValue(WinUI.Button.borderBrushProperty)
                _ = try? button.clearValue(WinUI.Button.borderThicknessProperty)
                _ = try? button.clearValue(WinUI.Button.cornerRadiusProperty)

                _ = resources.remove("ButtonBackgroundPointerOver")
                _ = resources.remove("ButtonBackgroundPressed")
                _ = resources.remove("ButtonBackgroundDisabled")

                _ = resources.remove("ButtonBorderBrushPointerOver")
                _ = resources.remove("ButtonBorderBrushPressed")
                _ = resources.remove("ButtonBorderBrushDisabled")
            case .plain, .borderless:
                let transparentBrush = SolidColorBrush(UWP.Color.transparent)
                button.background = transparentBrush
                button.borderBrush = transparentBrush
                button.borderThickness = Thickness.null
                button.cornerRadius = CornerRadius.null

                _ = resources.insert("ButtonBackgroundPointerOver", transparentBrush)
                _ = resources.insert("ButtonBackgroundPressed", transparentBrush)
                _ = resources.insert("ButtonBackgroundDisabled", transparentBrush)

                _ = resources.insert("ButtonBorderBrushPointerOver", transparentBrush)
                _ = resources.insert("ButtonBorderBrushPressed", transparentBrush)
                _ = resources.insert("ButtonBorderBrushDisabled", transparentBrush)
        }
    }

    fileprivate func applyModifications(_ button: ViewLabelCustomButton) {
        switch self {
            case .bordered: button.opacity = 1.0
            case .plain, .borderless:
                button.opacity = button.enabled
                    ? button.isHighlighted ? 0.7: 1.0
                    : 0.365
                // Why 36.5% opacity was chosen
                // https://github.com/microsoft/microsoft-ui-xaml/blob/fc2f821173298e8130fb5b143373ba70793bc251/src/controls/dev/CommonStyles/Common_themeresources_any.xaml#L8
                // 5D = 93 in base 10, 93 / 255 = 0.3647 ~ 0.365
        }
    }
}

// These three arrived from upstream as `static let`. Upstream is not in Swift 6
// language mode; this tree is, and there a `static let` of a non-`Sendable` type
// is "not concurrency-safe because ... may have shared mutable state" -- the three
// WinUI/UWP structs are all imported as non-`Sendable`.
//
// Making them computed answers the diagnostic instead of silencing it: a computed
// property has no shared storage for anything to race on. `nonisolated(unsafe)`
// would have kept the storage and merely asserted it was fine, and `@MainActor`
// would have restricted where they can be read. Each is a handful of zeroed fields
// constructed at a handful of call sites, so there is nothing worth caching.
//
// 這三者是從上游帶進來的 `static let`。上游並未啟用 Swift 6 語言模式,而本樹有;在該模式下,
// 非 `Sendable` 型別的 `static let` 會被判為「不具並行安全性,因為……可能持有共享的可變狀態」
// ——這三個 WinUI/UWP struct 匯入後皆為非 `Sendable`。
//
// 改為 computed 是回答該診斷,而非壓制它:computed property 根本沒有可供競爭的共享儲存。
// `nonisolated(unsafe)` 會保留儲存、僅僅斷言它沒問題,而 `@MainActor` 則會限縮可讀取它們的位置。
// 每一個都只是幾個歸零欄位、在少數幾處建構,並無快取的價值。
extension UWP.Color {
    static var transparent: Self { Color(a: 0, r: 0, g: 0, b: 0) }
}

extension WinUI.Thickness {
    static var null: Self { Thickness(left: 0, top: 0, right: 0, bottom: 0) }
}

extension WinUI.CornerRadius {
    static var null: Self { CornerRadius(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0) }
}
