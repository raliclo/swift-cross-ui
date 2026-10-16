/// A selection made by dragging from an anchor, in UTF-16 code units -- the
/// unit `NSRange`, `UITextInput` offsets, Android's `Spannable` and WinUI's
/// `TextBox.SelectionStart` all count in.
///
/// **Anchor and extent rather than a range**, because a drag that moves back
/// past the anchor selects backward: the anchor stays where the long press put
/// it and the extent follows the pointer. ``range`` is the ordered range a
/// toolkit that has no direction (WinUI's `Select(start, length)`) is given.
///
/// Not SwiftUI API: SwiftUI's `TextSelection` (iOS 18) has no anchor, and
/// SwiftUI has no long-press drag selection to describe.
///
/// 從一個錨點拖曳出來的選取範圍，以 UTF-16 code unit 計——`NSRange`、`UITextInput` 的位移、Android 的
/// `Spannable` 與 WinUI 的 `TextBox.SelectionStart` 都以它計數。**用錨點與延伸點而非一個範圍**,因為往回拖過
/// 錨點時是反向選取：錨點留在長按放下的位置，延伸點跟著指標走。``range`` 是給沒有方向概念的 toolkit
/// (WinUI 的 `Select(start, length)`)的有序範圍。不是 SwiftUI API:SwiftUI 的 `TextSelection`(iOS 18)
/// 沒有錨點，SwiftUI 也沒有長按拖曳選取可供描述。
public struct TextDragSelection: Hashable, Sendable, CustomStringConvertible {
    /// Where the long press put the caret. / 長按放下插入點的位置。
    public var anchor: Int
    /// Where the pointer is now. / 指標目前的位置。
    public var extent: Int

    public init(anchor: Int, extent: Int) {
        self.anchor = anchor
        self.extent = extent
    }

    /// A caret at `offset`: anchor and extent together. / 位於 `offset` 的插入點。
    public init(caretAt offset: Int) {
        self.init(anchor: offset, extent: offset)
    }

    /// The selected code units, whichever way the drag went.
    /// 被選取的 code unit,不論拖曳往哪個方向。
    public var range: Range<Int> {
        min(anchor, extent)..<max(anchor, extent)
    }

    /// The extent is before the anchor. / 延伸點在錨點之前。
    public var isBackward: Bool { extent < anchor }

    /// Nothing selected: a caret. / 沒有選取任何東西：一個插入點。
    public var isEmpty: Bool { anchor == extent }

    /// The same anchor with the extent moved to `offset`.
    /// 錨點不變、延伸點移到 `offset`。
    public func extended(to offset: Int) -> TextDragSelection {
        TextDragSelection(anchor: anchor, extent: offset)
    }

    /// Both ends kept within `0...length`, for a hit test that answers past
    /// the end of the text or a text that got shorter under the finger.
    /// 兩端都限制在 `0...length` 之內，供「命中測試回答超過文字結尾」或「文字在手指下變短」時使用。
    public func clamped(toLength length: Int) -> TextDragSelection {
        let upper = max(length, 0)
        return TextDragSelection(
            anchor: min(max(anchor, 0), upper),
            extent: min(max(extent, 0), upper)
        )
    }

    public var description: String {
        "anchor \(anchor) extent \(extent) range \(range.lowerBound)..<\(range.upperBound)"
            + (isBackward ? " backward" : "")
    }

    /// The UTF-16 offset of the `characterOffset`-th Unicode scalar of `text`,
    /// for GTK, whose offsets count scalars (`gunichar`s) rather than code units.
    /// Past the end answers the length.
    /// `text` 第 `characterOffset` 個 Unicode scalar 的 UTF-16 位移，供 GTK 使用——它的位移以 scalar
    /// (`gunichar`)計，而不是 code unit。超過結尾時回答長度。
    public static func utf16Offset(ofScalarOffset characterOffset: Int, in text: String) -> Int {
        var units = 0
        var scalars = 0
        for scalar in text.unicodeScalars {
            if scalars >= characterOffset { break }
            units += scalar.utf16.count
            scalars += 1
        }
        return units
    }
}

/// Where a long-press drag selection is: the first selection, each move, the
/// release. / 長按拖曳選取進行到哪裡：第一次選取、每次移動、放開。
public enum TextDragSelectionPhase: String, Sendable {
    case began
    case changed
    case ended
}

/// The decision every backend makes about one press: is it a long press that
/// selects, or an ordinary tap or drag that belongs to the toolkit?
///
/// **One state machine, used by the backends that see raw pointer events**
/// (AppKit, GTK, WinUI). UIKit has `UILongPressGestureRecognizer`, which makes
/// the same decision with the system's own numbers; Android's lives in Kotlin
/// (`CustomEditText.kt`), with the same rules, because the touch events never
/// cross into Swift.
///
/// The rules, in order:
///   - moving more than ``maximumDistance`` before ``minimumDuration`` is an
///     ordinary drag (a scroll, the toolkit's own drag-select): ``Event/passThrough``.
///   - still pressed and still near at ``minimumDuration``: ``Event/select(anchor:extent:)``
///     with both ends at the press point -- the caret goes where the finger is.
///   - after that every move is ``Event/extend(to:)`` and the release ``Event/finish``.
///   - a backend without a timer finds out at its next event instead: a move or
///     release after ``minimumDuration`` that never passed through starts the
///     selection there.
///
/// 每個 backend 對一次按壓所做的判斷：這是一次會選取的長按，還是屬於 toolkit 的一般點擊或拖曳?**一個狀態機，
/// 給看得到原始指標事件的 backend 使用**(AppKit、GTK、WinUI)。UIKit 有 `UILongPressGestureRecognizer`,
/// 以系統自己的數字做同一個判斷;Android 的在 Kotlin(`CustomEditText.kt`),規則相同，因為觸控事件從不進入
/// Swift。規則依序：在 ``minimumDuration`` 之前移動超過 ``maximumDistance`` 是一般拖曳(捲動、toolkit 自己的
/// 拖曳選取),回 ``Event/passThrough``;到 ``minimumDuration`` 時仍按著且仍在附近，回兩端都在按壓點的
/// ``Event/select(anchor:extent:)``——插入點放在手指所在處;之後每次移動是 ``Event/extend(to:)``,放開是
/// ``Event/finish``;沒有計時器的 backend 則在下一個事件才得知：在 ``minimumDuration`` 之後、從未放行過的
/// 移動或放開，就在那裡開始選取。
public struct LongPressSelectionTracker: Sendable {
    /// What the backend should do with the event it just reported.
    /// backend 應該如何處理它剛回報的事件。
    public enum Event: Equatable, Sendable {
        /// Nothing yet: keep the toolkit's behaviour for this event.
        /// 還沒有：這個事件維持 toolkit 的行為。
        case none
        /// Not a long press: the rest of this press is the toolkit's.
        /// 不是長按：這次按壓剩下的部分都交給 toolkit。
        case passThrough
        /// The long press fired: put the anchor under `anchor` and the extent
        /// under `extent`, and take the press away from the toolkit.
        /// 長按成立：錨點放在 `anchor` 底下、延伸點放在 `extent` 底下，並把這次按壓從 toolkit 拿走。
        case select(anchor: SIMD2<Double>, extent: SIMD2<Double>)
        /// Move the extent under this point. / 把延伸點移到這個點底下。
        case extend(to: SIMD2<Double>)
        /// Released: keep the selection. / 放開：保留選取。
        case finish
    }

    private enum State: Sendable {
        case idle
        case pressed(origin: SIMD2<Double>, time: Double)
        case selecting
        case passedThrough
    }

    /// The platform's long-press delay: Android's `ViewConfiguration`
    /// default, UIKit's `minimumPressDuration`, both 0.5 s.
    /// 平台的長按延遲:Android `ViewConfiguration` 的預設值、UIKit 的 `minimumPressDuration`,都是 0.5 秒。
    public static let defaultMinimumDuration = 0.5
    /// UIKit's `allowableMovement`, 10 points. / UIKit 的 `allowableMovement`,10 點。
    public static let defaultMaximumDistance = 10.0

    public var minimumDuration: Double
    public var maximumDistance: Double
    private var state: State = .idle

    public init(
        minimumDuration: Double = defaultMinimumDuration,
        maximumDistance: Double = defaultMaximumDistance
    ) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }

    /// A long press has fired and not been released. / 長按已成立且尚未放開。
    public var isSelecting: Bool {
        if case .selecting = state { return true }
        return false
    }

    /// A press is down and undecided. / 有一次按壓、尚未判定。
    public var isPending: Bool {
        if case .pressed = state { return true }
        return false
    }

    /// The pointer went down. Always the toolkit's: the press places the caret
    /// and focuses the field as it always did.
    /// 指標按下。永遠交給 toolkit:按壓照舊放置插入點並讓欄位取得焦點。
    public mutating func press(at point: SIMD2<Double>, time: Double) {
        state = .pressed(origin: point, time: time)
    }

    /// The long-press timer fired at `time`. / 長按計時器在 `time` 觸發。
    public mutating func elapse(to time: Double) -> Event {
        guard case .pressed(let origin, let start) = state,
            time - start >= minimumDuration - 1e-9
        else { return .none }
        state = .selecting
        return .select(anchor: origin, extent: origin)
    }

    /// The pointer moved to `point` at `time`. / 指標在 `time` 移到 `point`。
    public mutating func move(to point: SIMD2<Double>, time: Double) -> Event {
        switch state {
            case .idle, .passedThrough:
                return .none
            case .selecting:
                return .extend(to: point)
            case .pressed(let origin, let start):
                if time - start >= minimumDuration - 1e-9 {
                    state = .selecting
                    return .select(anchor: origin, extent: point)
                }
                let delta = point - origin
                if (delta.x * delta.x + delta.y * delta.y).squareRoot() > maximumDistance {
                    state = .passedThrough
                    return .passThrough
                }
                return .none
        }
    }

    /// The pointer went up at `point`. A press that fired, or would have had
    /// its timer run, selects and finishes; one that did not is a tap.
    /// 指標在 `point` 放開。已成立(或計時器本該已觸發)的按壓會選取並結束;沒有的則是一次點擊。
    public mutating func release(at point: SIMD2<Double>, time: Double) -> [Event] {
        defer { state = .idle }
        switch state {
            case .selecting:
                return [.extend(to: point), .finish]
            case .pressed(let origin, let start) where time - start >= minimumDuration - 1e-9:
                return [.select(anchor: origin, extent: point), .finish]
            case .pressed:
                return [.passThrough]
            case .idle, .passedThrough:
                return []
        }
    }

    /// The toolkit or the system took the press away (a cancel, a lost grab).
    /// toolkit 或系統把這次按壓拿走了(取消、失去 grab)。
    public mutating func cancel() -> Event {
        defer { state = .idle }
        if case .selecting = state { return .finish }
        return .none
    }
}
