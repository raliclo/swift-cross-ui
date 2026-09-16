extension BackendFeatures {
    /// What a screen reader should say about a widget.
    ///
    /// **Properties, not an action plus an event -- which is why this is not
    /// ``FocusableViews``.** A label is set and then it is there; nobody else
    /// changes it and nothing has to be reported back. Focus is the opposite:
    /// asking for it can be refused, and it moves for reasons the app did not
    /// cause. Putting both in one protocol would force a backend that only
    /// wants labels to implement focus reporting, so they are separate and this
    /// half could land first. That split was agreed in
    /// `testapp/plan/plan-focus-protocol.md` §4.
    ///
    /// **Conformance-checked, not required**, the same way ``ScrollingLists``
    /// and ``LazyListRows`` are, so the five backends convert one at a time. A
    /// backend that does not conform warns once per modifier rather than
    /// failing: a screen reader saying the wrong thing is invisible from the
    /// outside, so the one thing this must not do is stay quiet about it.
    ///
    /// 螢幕閱讀器應該如何描述一個 widget。
    ///
    /// **這些是屬性,不是「一個動作加一個事件」——這正是它不屬於 ``FocusableViews`` 的原因。**
    /// 標籤設下去就在那裡;沒有別人會改動它,也不需要回報任何東西。焦點恰好相反:去要它可能被拒絕,
    /// 而且它會因為 app 沒有造成的原因而移動。把兩者放進同一個協定,會迫使「只想加標籤」的 backend
    /// 去實作焦點回報,因此它們是分開的,而這一半得以先落地。該切分在
    /// `testapp/plan/plan-focus-protocol.md` §4 議定。
    ///
    /// **採 conformance 檢查而非要求實作**,與 ``ScrollingLists``、``LazyListRows`` 相同,好讓五個
    /// backend 一次轉一個。未 conform 的 backend 會每個 modifier 警告一次,而不是失敗:「螢幕閱讀器
    /// 說錯話」從外面完全看不出來,因此這件事**唯一**不能做的就是保持沉默。
    @MainActor
    public protocol Accessibility: Core {
        /// The name a screen reader reads for this widget.
        ///
        /// `nil` removes an override and returns the widget to whatever the
        /// platform would have derived on its own -- a button's title, an
        /// image's file name. Removing is not the same as setting `""`: an
        /// empty string is a widget a screen reader announces as nameless,
        /// which is a legitimate thing to ask for and a terrible default.
        ///
        /// 螢幕閱讀器為這個 widget 讀出的名稱。
        ///
        /// `nil` 會移除覆寫,讓該 widget 回到平台自己會推導出的東西——按鈕的標題、圖片的檔名。
        /// 「移除」與「設為 `""`」不同:空字串是一個「螢幕閱讀器會宣告為無名」的 widget,那是一個
        /// 正當的要求,卻是一個糟糕的預設值。
        func setAccessibilityLabel(ofWidget widget: Widget, to label: String?)

        /// What happens if the user activates this widget.
        ///
        /// Separate from the label because they are read at different times:
        /// the label identifies, the hint explains, and a screen reader may be
        /// configured to skip hints entirely. Folding the hint into the label
        /// would make it unskippable.
        ///
        /// 使用者啟動這個 widget 會發生什麼事。
        ///
        /// 與標籤分開,因為兩者被讀出的時機不同:標籤用來指認,提示用來說明,而螢幕閱讀器可能被設定為
        /// 完全跳過提示。把提示併進標籤,會讓它變得無法跳過。
        func setAccessibilityHint(ofWidget widget: Widget, to hint: String?)

        /// This widget's current content, when that is not its label.
        ///
        /// A slider's label is "Volume" and its value is "40 percent". Both are
        /// needed and neither substitutes for the other, which is why this is a
        /// third method and not a longer label.
        ///
        /// 這個 widget 目前的內容,當那個內容不等於它的標籤時。
        ///
        /// 一個滑桿的標籤是「音量」,而它的值是「百分之四十」。兩者都需要,而且互不替代——這正是它
        /// 是第三個方法、而不是一個更長的標籤的原因。
        func setAccessibilityValue(ofWidget widget: Widget, to value: String?)

        /// Takes this widget out of what a screen reader can reach, along with
        /// everything inside it.
        ///
        /// **Its children too, and that is the point.** The use is a decorative
        /// group -- an icon beside a label that repeats it, a spacer drawn as a
        /// rule -- where hiding only the container would leave the parts behind
        /// and make the announcement worse, not better.
        ///
        /// It does NOT hide the widget visually. A screen-reader user and a
        /// sighted user see different things here on purpose; a modifier that
        /// did both would have no way to express "visible, but already said".
        ///
        /// 把這個 widget、連同它裡面的一切,移出螢幕閱讀器能抵達的範圍。
        ///
        /// **連同它的子元件,而那正是重點。** 用途是一個裝飾性的群組——一個與標籤重複的圖示、一條
        /// 被畫成橫線的間隔——在這種情況下,只藏容器會把各個零件留在原地,讓宣讀變得更糟而不是更好。
        ///
        /// 它**不會**在視覺上隱藏該 widget。螢幕閱讀器使用者與視覺使用者在此看到不同的東西,而那是
        /// 刻意的;一個兩者都做的 modifier,將無從表達「看得見,但已經被講過了」。
        func setAccessibilityHidden(ofWidget widget: Widget, to hidden: Bool)
    }
}
