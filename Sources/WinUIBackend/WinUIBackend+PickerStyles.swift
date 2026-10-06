import SwiftCrossUI
import UWP
@preconcurrency import WindowsFoundation
import WinUI

/// `.segmented` on WinUI: a row of mutually exclusive `ToggleButton`s.
///
/// WinUI 3 ships no segmented control (the Community Toolkit's `Segmented` is
/// not a dependency here), and this style used to reach the `fatalError` in
/// `createPicker` -- or, through `.pickerStyle`, be downgraded to `.menu`
/// without a word. A segmented control is a row of buttons of which exactly the
/// chosen one stays pressed; `ToggleButton` already draws "pressed" in the
/// accent colour, so the row only has to keep the presses exclusive.
///
/// `.segmented` 在 WinUI 上：一列互斥的 `ToggleButton`。WinUI 3 沒有 segmented 控制項(Community
/// Toolkit 的 `Segmented` 不是此處的相依套件)，這個樣式原本會走到 `createPicker` 的 `fatalError`——
/// 或經 `.pickerStyle` 被無聲降級為 `.menu`。segmented 控制項就是一列按鈕，只有選中的那顆保持按下；
/// `ToggleButton` 本來就以強調色畫出「按下」，所以這一列只需讓按下互斥。
final class SegmentedPicker: WinUI.StackPanel {
    var onChangeSelection: ((Int?) -> Void)?
    private(set) var options: [String] = []
    private var buttons: [WinUI.ToggleButton] = []
    private var selectedIndex: Int?

    override init() {
        super.init()
        orientation = .horizontal
        spacing = 2
    }

    @MainActor
    func update(options: [String], environment: EnvironmentValues) {
        if options != self.options {
            children.clear()
            buttons = options.indices.map { _ in makeButton() }
            for button in buttons {
                children.append(button)
            }
            self.options = options
        }
        for (button, option) in zip(buttons, options) {
            environment.apply(to: button)
            // The label carries no colour of its own, so the button's
            // foreground -- the theme's, which flips when checked, or the
            // environment's -- reaches it.
            // 標籤自己不帶顏色，讓按鈕的前景色——主題的(勾選時會反轉)或環境的——傳到它身上。
            let label = (button.content as? WinUI.TextBlock) ?? WinUI.TextBlock()
            label.text = option
            label.fontSize = button.fontSize
            button.content = label
        }
        setSelectedIndex(to: selectedIndex)
    }

    func setSelectedIndex(to index: Int?) {
        selectedIndex = index.flatMap { $0 < buttons.count ? $0 : nil }
        for (i, button) in buttons.enumerated() {
            button.isChecked = i == selectedIndex
        }
    }

    private func makeButton() -> WinUI.ToggleButton {
        let button = WinUI.ToggleButton()
        // A click has already flipped the button; put the row back to exactly
        // one pressed, including when the pressed one is clicked again.
        // 點擊時按鈕已自行翻轉；把整列恢復成恰好一顆按下，包括再次點擊已按下的那顆。
        button.click.addHandler { [weak self, weak button] _, _ in
            guard let self, let button,
                let index = self.buttons.firstIndex(where: { $0 === button })
            else { return }
            self.setSelectedIndex(to: index)
            self.onChangeSelection?(index)
        }
        return button
    }
}

/// `.wheel` on WinUI: a five-row scrolling list with one row selected.
///
/// The same shape AppKit (`WheelPicker`, a small single-column table) and GTK
/// (`GtkBackend/WheelPicker.swift`, a five-row ListBox) use, since none of
/// the three has a spinning wheel; Mac Catalyst's UIKit shows a table for this
/// style too. Before this it was the `fatalError` in `createPicker`.
///
/// `.wheel` 在 WinUI 上：一段五列高、會捲動、選中一列的清單。與 AppKit(`WheelPicker`,小的單欄表格)
/// 和 GTK(`GtkBackend/WheelPicker.swift`,五列的 ListBox)同一形狀，因為三者都沒有旋轉滾輪；Mac Catalyst
/// 的 UIKit 對這個樣式也顯示表格。在此之前它是 `createPicker` 裡的 `fatalError`。
final class WheelPicker: WinUI.ListView {
    var onChangeSelection: ((Int?) -> Void)?
    private(set) var options: [String] = []
    private var rows: [WinUI.ListViewItem] = []
    /// Set while code moves the selection, so that move is not reported back
    /// as the user's choice. 程式移動選取時設定，避免把那次移動當成使用者的選擇回報。
    private var isUpdatingSelection = false

    /// Five rows tall, as a wheel shows a few options around the chosen one.
    /// 五列高，就像滾輪在選中項周圍露出幾個選項。
    static let visibleRows = 5
    /// Below `ListViewItem`'s default minimum of 40, which would make five rows
    /// 200 pixels tall. 低於 `ListViewItem` 預設的最小高度 40,否則五列就有 200 像素高。
    static let rowHeight = 32.0
    /// Five rows plus the one-pixel border. 五列加上一像素邊框。
    static let fixedHeight = rowHeight * Double(visibleRows) + 2

    override init() {
        super.init()
        selectionMode = .single
        height = Self.fixedHeight
        borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        selectionChanged.addHandler { [weak self] _, _ in
            guard let self, !self.isUpdatingSelection else { return }
            self.onChangeSelection?(self.selectedIndex < 0 ? nil : Int(self.selectedIndex))
        }
    }

    @MainActor
    func update(options: [String], environment: EnvironmentValues) {
        environment.apply(to: self)
        if options != self.options {
            let selected = selectedIndex
            isUpdatingSelection = true
            defer { isUpdatingSelection = false }
            items.clear()
            rows = options.indices.map { _ in
                let row = WinUI.ListViewItem()
                row.minHeight = Self.rowHeight
                row.height = Self.rowHeight
                row.padding = Thickness(left: 12, top: 0, right: 12, bottom: 0)
                row.horizontalContentAlignment = .left
                return row
            }
            for row in rows {
                items.append(row)
            }
            self.options = options
            if selected >= 0, Int(selected) < options.count {
                selectedIndex = selected
            }
        }
        for (row, option) in zip(rows, options) {
            let label = (row.content as? WinUI.TextBlock) ?? WinUI.TextBlock()
            label.text = option
            environment.apply(to: label)
            row.content = label
        }
    }

    /// The width the rows need at the fixed five-row height.
    ///
    /// `WinUIBackend.naturalSize(of:)` clears `width` and `height` before it
    /// measures, so a `ListView` reports every row laid out -- P74's seven-day
    /// wheel came out seven rows tall. Measured here with the height held.
    /// 在固定五列高度下，各列所需的寬度。`WinUIBackend.naturalSize(of:)` 量測前會清掉 `width` 與
    /// `height`,於是 `ListView` 回報的是所有列都排開的大小——P74 的七天滾輪因此有七列高。此處在高度固定下量測。
    @MainActor
    func naturalSize() -> SIMD2<Int> {
        let oldWidth = width
        let oldHeight = height
        defer {
            width = oldWidth
            height = oldHeight
        }
        width = .nan
        height = Self.fixedHeight
        try! measure(WindowsFoundation.Size(width: .infinity, height: .infinity))
        return SIMD2(Int(desiredSize.width.rounded(.up)), Int(Self.fixedHeight))
    }

    func setSelectedIndex(to index: Int?) {
        isUpdatingSelection = true
        defer { isUpdatingSelection = false }
        if let index, index < rows.count {
            selectedIndex = Int32(index)
            try? scrollIntoView(rows[index])
        } else {
            selectedIndex = -1
        }
    }
}
