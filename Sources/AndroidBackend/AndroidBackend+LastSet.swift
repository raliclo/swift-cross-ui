/// What the backend last told each widget, kept on the Swift side.
///
/// Skipping a setter whose value has not changed only pays if the comparison
/// is free, and reading the current value back from Java is not: every
/// `getText()` or `getLayoutParams()` is a JNI call, and swift-java looks the
/// method up again on each one. With the read-back checks of 2026-10-04 in
/// place, `updateTextView` and `setPosition` were still 27 % and 22 % of P66's
/// main thread during its animation, mostly spent on those reads. Remembering
/// the last value here makes an unchanged call cost one dictionary lookup.
///
/// Entries are keyed by the widget object and hold it weakly, so a widget that
/// is freed and whose address is reused by a new one is not mistaken for it.
///
/// 後端最後一次告訴每個 widget 的值，保存在 Swift 這一側。只有當比較本身免費時，「值沒變就跳過」才划算，
/// 而從 Java 讀回現值並不免費：每一次 `getText()` 或 `getLayoutParams()` 都是一次 JNI 呼叫，而 swift-java
/// 每次都重新查找方法。2026-10-04 加上讀回檢查之後，P66 動畫期間 `updateTextView` 與 `setPosition` 仍佔
/// 主執行緒的 27% 與 22%,大多花在那些讀取上。把最後的值記在這裡，沒有改變的呼叫只花一次字典查找。條目以
/// widget 物件為鍵並弱參考它，因此被釋放的 widget 若位址被新的重用，不會被誤認。
@MainActor
final class LastSet<Value> {
    private final class Entry {
        weak var object: AnyObject?
        var value: Value
        init(_ object: AnyObject, _ value: Value) {
            self.object = object
            self.value = value
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func value(for object: AnyObject) -> Value? {
        guard let entry = entries[ObjectIdentifier(object)], entry.object === object else {
            return nil
        }
        return entry.value
    }

    func set(_ value: Value, for object: AnyObject) {
        if let entry = entries[ObjectIdentifier(object)], entry.object === object {
            entry.value = value
            return
        }
        if entries.count > 4096 {
            entries = entries.filter { $0.value.object != nil }
        }
        entries[ObjectIdentifier(object)] = Entry(object, value)
    }

    func forget(_ object: AnyObject) {
        entries[ObjectIdentifier(object)] = nil
    }
}

extension AndroidBackend {
    /// Each container's children's positions, by index. Forgotten whenever the
    /// container's children are inserted, removed or reordered, because the
    /// indices then name different views.
    /// 每個容器子元件的位置，依索引存放。容器的子元件被插入、移除或重新排序時就忘掉，因為索引從此指向不同的 view。
    @MainActor static let childPositions = LastSet<[Int: SIMD2<Int>]>()
    /// Each widget's size in points.
    /// 每個 widget 的尺寸(點)。
    @MainActor static let widgetSizes = LastSet<SIMD2<Int>>()
    /// Each text view's content and text-style key.
    /// 每個 text view 的內容與文字樣式鍵。
    @MainActor static let textContents = LastSet<String>()
}
