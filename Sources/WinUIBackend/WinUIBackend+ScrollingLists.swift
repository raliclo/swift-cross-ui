import WinUI
@_spi(Backends) import SwiftCrossUI

/// `BackendFeatures.ScrollingLists` for WinUI (#117).
///
/// Much smaller than the GTK half, and the reason is structural rather than
/// lucky: a `WinUI.ListView` already contains a `ScrollViewer` in its default
/// template and already virtualises through an `ItemsStackPanel`. There is no
/// wrapper to introduce here, so unlike `GtkBackend` this backend's
/// `createSelectableListView` is untouched -- the widget a `List` hands around
/// is still the `CustomListView` it always was, and no `as!` in this file's
/// neighbours had to change.
///
/// **What conforming actually buys, and it is not the scrolling.** The
/// scrolling was already there. What was missing is that `Views/List.swift`
/// reported the SUM of every row height as the list's size to SwiftCrossUI's
/// own layout system, and that is what grew the window. It reports
/// `min(height, proposed)` only for a backend that conforms to this protocol,
/// so on WinUI the conformance is most of the fix and this method is the
/// smaller part of it.
///
/// 為 WinUI 實作的 `BackendFeatures.ScrollingLists`(#117)。
///
/// 比 GTK 那一半小得多,而理由是結構性的、不是運氣:`WinUI.ListView` 的預設樣板中本來就含有一個
/// `ScrollViewer`,也本來就透過 `ItemsStackPanel` 做虛擬化。此處沒有需要引入的外包層,因此與
/// `GtkBackend` 不同,本 backend 的 `createSelectableListView` 完全沒有更動——`List` 傳來傳去的
/// widget 依舊是它一直以來的那個 `CustomListView`,鄰近程式碼裡沒有任何一個 `as!` 需要修改。
///
/// **conformance 真正換到的東西,而那不是捲動。** 捲動本來就在。缺的是:`Views/List.swift` 過去
/// 把「每一列高度的**總和**」當作這個清單的尺寸回報給 SwiftCrossUI 自己的排版系統,而那才是把視窗
/// 撐大的原因。它只對「符合本 protocol」的 backend 回報 `min(height, proposed)`,因此在 WinUI 上,
/// conformance 本身就是這次修正的大半,而本方法是其中較小的那一部分。
///
/// **Corrected 2026-09-09, before this file was ever committed.** The sentence
/// above hedged with "most of the fix" and "the smaller part of it". Both were
/// too generous, and the measurement is in `setViewportHeight` below: the
/// conformance is the WHOLE fix here (656x16224 at 400 rows without it,
/// 656x739 with it), and the method's body is inert today. The distinction
/// matters because "smaller part" invites a reader to assume the body does
/// something, which is the shape this project keeps finding in its own docs.
///
/// **2026-09-09 更正,在本檔被 commit 之前。** 上面那句話用了「大半」與「較小的那一部分」來打折,
/// 而兩者都說得太寬厚;量測結果就寫在下方的 `setViewportHeight` 裡:在這裡 conformance 是**全部**
/// 的修正(400 列時,沒有它是 656x16224,有它是 656x739),而該方法的本體今天是惰性的。這個區別
/// 之所以重要,是因為「較小的那一部分」會誘使讀者假設本體有在做事——而那正是本專案一再在自己文件裡
/// 找到的形狀。
extension WinUIBackend: BackendFeatures.ScrollingLists {
    public func setViewportHeight(ofSelectableListView listView: Widget, to height: Int) {
        let listView = listView as! CustomListView

        // THIS LINE CHANGES NOTHING TODAY, and saying so is the point of this
        // comment. Measured 2026-09-09 on P57 at three row counts, with the
        // conformance kept and only this assignment removed:
        //
        //   rows   without this line   with it
        //   10     656x739             656x739
        //   50     656x739             656x739
        //   400    656x739             656x739
        //
        // Six identical numbers. `List.commit` calls `setSize` one line later
        // with the same height, and an explicit `Height` on a `ListView` already
        // stops it measuring its content, so the ceiling never binds.
        //
        // It is kept anyway, as a ceiling rather than as a fix. `maxHeight`
        // composes with whatever `setSize` does instead of racing it, and if a
        // future caller stops setting an explicit height the ListView goes back
        // to measuring its content, the window grows, and #117 returns with no
        // error anywhere. But that is a guard against a change nobody has made,
        // NOT something you can observe now -- and an earlier draft of this
        // comment claimed the composition as a present benefit, which the
        // measurement above refutes.
        //
        // If you are here because this method looks pointless: it is not the
        // method that fixes WinUI, it is the CONFORMANCE. Measured the same day
        // by removing the whole file: 656x2224 at 50 rows and 656x16224 at 400.
        // `Views/List.swift` reports `min(height, proposed)` only for a backend
        // that conforms, and that is the entire fix on this backend.
        //
        // **這一行今天不改變任何東西**,而說出這件事正是本註解存在的目的。2026-09-09 在 P57 上以
        // 三個列數實測,保留 conformance、只移除這一個指派:10 列 656x739 對 656x739、50 列
        // 656x739 對 656x739、400 列 656x739 對 656x739——六個數字完全相同。`List.commit` 在
        // 下一行就會以相同的高度呼叫 `setSize`,而 `ListView` 上一個明確的 `Height` 本來就會讓它
        // 停止量測自身內容,因此這個上限永遠不會生效。
        //
        // 它仍然被保留,但身分是**上限**而非**修正**。`maxHeight` 會與 `setSize` 所做的事疊合而非
        // 與之競爭;若未來某個呼叫端不再設定明確高度,ListView 就會回頭量測自己的內容,視窗隨之長高,
        // 而 #117 會在沒有任何錯誤訊息的情況下回來。但那是在防一個**還沒有人做出的改動**,
        // **不是**現在觀察得到的效果——而本註解的前一個版本把那個疊合寫成當下的好處,已被上述量測推翻。
        //
        // 若你是因為覺得這個方法沒有意義而讀到這裡:修好 WinUI 的不是這個方法,是那個
        // **conformance**。同一天以「移除整個檔案」實測:50 列 656x2224、400 列 656x16224。
        // `Views/List.swift` 只對符合本 protocol 的 backend 回報 `min(height, proposed)`,
        // 而在這個 backend 上那就是全部的修正。
        //
        // Clamped for the same reason GtkBackend clamps: WinUI treats a
        // negative or NaN `MaxHeight` as unbounded, so a stray value would
        // quietly restore the behaviour this exists to prevent.
        // 夾值的理由與 GtkBackend 相同:WinUI 把負值或 NaN 的 `MaxHeight` 視為「無上限」,因此一個
        // 漏網的值會安靜地把本方法所要防止的行為還原回來。
        listView.maxHeight = Double(max(1, height))
    }
}
