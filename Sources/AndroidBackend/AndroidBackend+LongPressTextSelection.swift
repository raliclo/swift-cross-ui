import AndroidKit
@_spi(Backends) import SwiftCrossUI
import SwiftJava

extension AndroidBackend: BackendFeatures.LongPressTextSelection {
    /// The long press, the drag and the hit test live in Kotlin
    /// (`CustomEditText.onTouchEvent`): `getOffsetForPosition(x, y)` under the
    /// finger and `Selection.setSelection(anchor, extent)`, with the platform's
    /// `ViewConfiguration` long-press timeout and touch slop. Touch events never
    /// cross into Swift, so Swift hands Kotlin a `SwiftAction` and reads the
    /// selection back each time it is called -- `getSelectionStart()` is
    /// Android's anchor and `getSelectionEnd()` its extent, unordered, so a
    /// backward selection arrives backward.
    ///
    /// 長按、拖曳與命中測試都在 Kotlin(`CustomEditText.onTouchEvent`):以 `getOffsetForPosition(x, y)` 取手指
    /// 底下的位置、`Selection.setSelection(anchor, extent)` 選取，用平台 `ViewConfiguration` 的長按逾時與 touch
    /// slop。觸控事件從不進入 Swift,所以 Swift 交給 Kotlin 一個 `SwiftAction`,每次被呼叫時讀回選取——
    /// `getSelectionStart()` 是 Android 的錨點、`getSelectionEnd()` 是延伸點，不排序，所以反向選取以反向抵達。
    public func setLongPressTextSelection(
        ofTextInput textInput: Widget,
        enabled: Bool,
        onChange: (@MainActor (TextDragSelection, TextDragSelectionPhase) -> Void)?
    ) {
        guard let field = textInput.as(CustomEditText.self) else { return }
        guard enabled, let onChange else {
            field.setLongPressSelection(nil)
            return
        }
        field.setLongPressSelection(
            SwiftAction(environment: Self.env) {
                // Held strongly for the reason updateTextField gives: the
                // Swift wrapper is all there is, and Java holds the action.
                // 以強參照持有，理由與 updateTextField 相同:Swift wrapper 就是全部，而 action 由 Java 持有。
                let selection = TextDragSelection(
                    anchor: Int(field.getSelectionStart()),
                    extent: Int(field.getSelectionEnd())
                )
                let phase: TextDragSelectionPhase =
                    switch field.longPressSelectionPhase() {
                        case 0: .began
                        case 1: .changed
                        default: .ended
                    }
                MainActor.assumeIsolated {
                    onChange(selection, phase)
                }
            }
        )
    }
}
