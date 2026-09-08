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
fileprivate final class ViewLabelCustomButton: WinUI.Button {
    fileprivate var action: (() -> Void)?

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
