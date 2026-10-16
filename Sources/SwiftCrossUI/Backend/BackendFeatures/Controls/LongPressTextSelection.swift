extension BackendFeatures {
    /// Long-press drag selection in a text field or text editor: a long press
    /// puts the caret under the finger and makes it the anchor, the drag that
    /// follows extends the selection to the character under the pointer
    /// (backward when it goes before the anchor), the page and the field do not
    /// scroll during it, and the release keeps the selection. What
    /// ``View/longPressTextSelection(_:)`` turns on.
    ///
    /// **A separate protocol rather than more of ``TextFields``**, so a backend
    /// outside the shipped five keeps compiling and its fields keep working;
    /// the modifier then says once that the backend has no long-press
    /// selection. The five shipped backends -- GtkBackend, WinUIBackend,
    /// AppKitBackend, UIKitBackend, AndroidBackend -- all conform.
    ///
    /// **Hit-tested by the toolkit, not computed**: the character under the
    /// pointer depends on the font, the wrapping, the field's own scrolling
    /// and the platform's caret rules, and every toolkit already answers it --
    /// `characterIndexForInsertion(at:)`, `closestPosition(to:)`,
    /// `getOffsetForPosition`, `gtk_text_view_get_iter_at_position` and
    /// `GtkText`'s cursor extents, `TextBox.GetRectFromCharacterIndex`.
    ///
    /// 文字欄位或文字編輯器中的長按拖曳選取：長按把插入點放在手指底下並當作錨點，接著的拖曳把選取延伸到指標
    /// 底下的字元(拖到錨點之前就是反向)、期間頁面與欄位都不捲動、放開後保留選取。由
    /// ``View/longPressTextSelection(_:)`` 開啟。**獨立成一個協定而不是併入 ``TextFields``**,讓五個已發布
    /// backend 以外的 backend 仍能編譯、欄位仍能使用;modifier 會說一次「這個 backend 沒有長按選取」。五個
    /// 已發布的 backend 全部 conform。**由 toolkit 命中測試，而非計算**:指標底下是哪個字元取決於字型、換行、
    /// 欄位自己的捲動與平台的插入點規則，而每個 toolkit 都已經回答得出來。
    @MainActor
    public protocol LongPressTextSelection: TextFields, TextEditors {
        /// Turns long-press drag selection on or off for a widget made by
        /// `createTextField()` or `createTextEditor()`.
        ///
        /// `onChange` is called with the selection the toolkit holds -- read
        /// back from it after it was set, not the numbers the backend asked
        /// for -- when the long press fires (`.began`), on each move
        /// (`.changed`) and on release (`.ended`).
        ///
        /// Called on every update of the field, so it must be cheap and must
        /// replace the handler rather than install a second recogniser.
        ///
        /// 為 `createTextField()` 或 `createTextEditor()` 建立的 widget 開啟或關閉長按拖曳選取。`onChange`
        /// 收到的是 toolkit 持有的選取——設定之後從它讀回來的，而不是 backend 要求的數字——在長按成立時
        /// (`.began`)、每次移動時(`.changed`)與放開時(`.ended`)。欄位每次更新都會呼叫，所以必須低成本，
        /// 並且替換 handler 而不是再裝一個辨識器。
        func setLongPressTextSelection(
            ofTextInput textInput: Widget,
            enabled: Bool,
            onChange: (@MainActor (TextDragSelection, TextDragSelectionPhase) -> Void)?
        )
    }
}
