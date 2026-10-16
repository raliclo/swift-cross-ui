import ObjectiveC
@_spi(Backends) import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.LongPressTextSelection {
    /// A `UILongPressGestureRecognizer` on the `UITextField` or `UITextView`,
    /// with UITextInput's own hit-testing: `closestPosition(to:)` under the
    /// finger, `selectedTextRange` to select.
    ///
    /// **Every other recogniser on the same touch waits for it to fail**
    /// (`gestureRecognizer(_:shouldBeRequiredToFailBy:)` answers `true`): the
    /// text input's tap and loupe, the `UITextView`'s own pan and an enclosing
    /// `UIScrollView`'s pan. A tap still lands -- the long press fails the
    /// moment the finger lifts before 0.5 s -- and a swipe still scrolls once
    /// it has moved 10 points, which fails the long press too. Once the long
    /// press has begun, none of them can, so the page and the editor stay put
    /// while the selection follows the finger. Setting `selectedTextRange` from
    /// code shows no edit menu, so the release leaves just the selection.
    ///
    /// `UITextField`/`UITextView` 上的 `UILongPressGestureRecognizer`,配上 UITextInput 自己的命中測試：
    /// 以 `closestPosition(to:)` 取手指底下的位置，以 `selectedTextRange` 選取。**同一次觸控上的其他每個辨識器都
    /// 等它失敗**(`gestureRecognizer(_:shouldBeRequiredToFailBy:)` 回答 `true`):文字輸入的點擊與放大鏡、
    /// `UITextView` 自己的 pan,以及外層 `UIScrollView` 的 pan。點擊照樣成立——手指在 0.5 秒前離開，長按就立刻
    /// 失敗——滑動在移動 10 點後照樣捲動，那同樣讓長按失敗。長按一旦開始，它們都無法開始，所以頁面與編輯器在
    /// 選取跟著手指走的期間都不動。從程式設定 `selectedTextRange` 不會叫出編輯選單，所以放開後只留下選取。
    public func setLongPressTextSelection(
        ofTextInput textInput: Widget,
        enabled: Bool,
        onChange: (@MainActor (TextDragSelection, TextDragSelectionPhase) -> Void)?
    ) {
        let input: (UIView & UITextInput)?
        if let field = textInput as? TextFieldWidget {
            input = field.child
        } else if let editor = textInput as? TextEditorWidget {
            input = editor.child
        } else {
            input = nil
        }
        guard let input else { return }
        let existing = UIKitLongPressSelection.attached(to: input)
        guard enabled, let onChange else {
            existing?.onChange = nil
            existing?.recognizer.isEnabled = false
            return
        }
        let selection = existing ?? UIKitLongPressSelection(attachingTo: input)
        selection.onChange = onChange
        selection.recognizer.isEnabled = true
    }
}

/// The recogniser and the anchor for one text input, kept on it as an
/// associated object so that it lives as long as the view.
/// 某個文字輸入的辨識器與錨點，以 associated object 存在它身上，與視圖同壽。
@MainActor
final class UIKitLongPressSelection: NSObject, UIGestureRecognizerDelegate {
    private nonisolated(unsafe) static var key: UInt8 = 0

    weak var input: (UIView & UITextInput)?
    let recognizer = UILongPressGestureRecognizer()
    var onChange: (@MainActor (TextDragSelection, TextDragSelectionPhase) -> Void)?
    private var anchor = 0
    private var isSelecting = false

    static func attached(to input: UIView) -> UIKitLongPressSelection? {
        objc_getAssociatedObject(input, &key) as? UIKitLongPressSelection
    }

    init(attachingTo input: UIView & UITextInput) {
        self.input = input
        super.init()
        recognizer.minimumPressDuration = LongPressSelectionTracker.defaultMinimumDuration
        recognizer.allowableMovement = LongPressSelectionTracker.defaultMaximumDistance
        recognizer.delegate = self
        recognizer.addTarget(self, action: #selector(handle(_:)))
        input.addGestureRecognizer(recognizer)
        objc_setAssociatedObject(input, &Self.key, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handle(_ recognizer: UILongPressGestureRecognizer) {
        guard let input else { return }
        // In the input's own coordinates; for a UITextView that is its
        // content, which is what closestPosition(to:) takes.
        // 以輸入框自己的座標;對 UITextView 而言就是它的內容座標，正是 closestPosition(to:) 所要的。
        let point = recognizer.location(in: input)
        switch recognizer.state {
            case .began:
                if !input.isFirstResponder { _ = input.becomeFirstResponder() }
                guard let position = input.closestPosition(to: point) else { return }
                anchor = input.offset(from: input.beginningOfDocument, to: position)
                isSelecting = true
                select(to: position, phase: .began)
            case .changed:
                guard isSelecting, let position = input.closestPosition(to: point) else { return }
                select(to: position, phase: .changed)
            case .ended, .cancelled, .failed:
                guard isSelecting else { return }
                isSelecting = false
                if let position = input.closestPosition(to: point) {
                    select(to: position, phase: .ended)
                }
            default:
                break
        }
    }

    private func select(to position: UITextPosition, phase: TextDragSelectionPhase) {
        guard let input else { return }
        let start = input.beginningOfDocument
        let extent = input.offset(from: start, to: position)
        let range = TextDragSelection(anchor: anchor, extent: extent).range
        if let lower = input.position(from: start, offset: range.lowerBound),
            let upper = input.position(from: start, offset: range.upperBound)
        {
            input.selectedTextRange = input.textRange(from: lower, to: upper)
        }
        // Read back from UIKit, not echoed. / 從 UIKit 讀回，而非照抄。
        guard let held = input.selectedTextRange else { return }
        let low = input.offset(from: start, to: held.start)
        let high = input.offset(from: start, to: held.end)
        let reported =
            extent < anchor
            ? TextDragSelection(anchor: high, extent: low)
            : TextDragSelection(anchor: low, extent: high)
        onChange?(reported, phase)
    }
}
