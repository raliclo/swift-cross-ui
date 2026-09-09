import AndroidKit
@_spi(Backends) import SwiftCrossUI

extension AndroidBackend: BackendFeatures.ScrollingLists {
    /// An Android `ListView` scrolls and recycles by itself; it was being given
    /// a height equal to all of its rows.
    ///
    /// **This one is nearly a no-op, and saying so is the point.** `setSize` --
    /// which `List.commit` calls immediately after this -- already writes
    /// `layoutParams.height`, so on this backend the conformance is what does
    /// the work: it makes `List` report `min(height, proposed)` instead of the
    /// sum of every row, and the existing `setSize` then applies that number.
    /// The method is still implemented rather than left empty, because an empty
    /// body would read as "Android does not need a viewport" when what is true
    /// is "Android's viewport arrives through another call one line later", and
    /// a later change to that ordering would then break this silently.
    ///
    /// `layoutLength` is used rather than a raw multiplication for the reason
    /// given at its definition: `MATCH_PARENT` and `WRAP_CONTENT` are negative
    /// sentinels living in the same field as a length, and scaling one by the
    /// display density turns it into the other.
    ///
    /// Android 的 `ListView` 自己會捲動、也自己回收;它先前拿到的是一個等於其所有列總和的高度。
    ///
    /// **這一個幾乎是空操作,而「說出這件事」正是重點。** `setSize`——`List.commit` 緊接在此之後就會
    /// 呼叫它——本來就會寫入 `layoutParams.height`,因此在這個 backend 上,真正起作用的是「conformance
    /// 本身」:它讓 `List` 回報 `min(height, proposed)` 而非每一列的總和,再由既有的 `setSize` 套用
    /// 那個數字。此處仍然實作而不留空,因為一個空的實作讀起來會像是「Android 不需要視口」,而事實是
    /// 「Android 的視口由一行之後的另一個呼叫送達」;日後若有人更動那個順序,空實作會讓它靜默地壞掉。
    ///
    /// Measured on the emulator (1080x2400, density 2.625), same APK, only
    /// `-rows` varying, 2026-09-09 -- the value written into `layoutParams`:
    ///
    ///     rows=50     450 pt -> 1181 px
    ///     rows=400    450 pt -> 1181 px
    ///     rows=2000   450 pt -> 1181 px
    ///
    /// Constant across a fortyfold range, and a screenshot at 2000 rows shows
    /// rows 0 through 12, so it is a viewport rather than a list clipped to
    /// nothing. **The before-value was not measured separately on this
    /// backend**: without the conformance `setViewportHeight` is never called,
    /// so the probe that produced these numbers has nothing to print. What the
    /// old height was is `Views/List.swift`'s sum over every row, which is the
    /// same expression AppKit's before-and-after pinned.
    ///
    /// 於模擬器上量測(1080x2400,density 2.625),同一個 APK、只有 `-rows` 變動,2026-09-09——
    /// 寫入 `layoutParams` 的值在 50、400、2000 列時皆為 450 pt(1181 px),在四十倍的範圍內是常數;
    /// 而 2000 列時的截圖顯示 row 0 到 row 12,因此它是一個視口,不是一個被裁成空白的清單。
    /// **本 backend 的「之前」並未單獨量測**:少了 conformance,`setViewportHeight` 根本不會被呼叫,
    /// 產生上述數字的那個探針也就無從印出任何東西。當時的高度是 `Views/List.swift` 對每一列的總和,
    /// 而那正是 AppKit 的前後量測所釘住的同一個運算式。
    public func setViewportHeight(ofSelectableListView listView: Widget, to height: Int) {
        guard let layoutParams = listView.getLayoutParams() else { return }
        let density = listView.getResources().getDisplayMetrics().density
        layoutParams.height = Self.layoutLength(height, density: density)
        listView.setLayoutParams(layoutParams)
    }
}
