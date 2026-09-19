extension BackendFeatures {
    /// Reading back the pixels a widget actually drew.
    ///
    /// **This exists because of a gap someone else hit, written down in their
    /// own words.** `SoftPCB-UI`'s `plan.md` §10.7 ends with a table headed "the
    /// real obstacles", and its second row is: *SwiftCrossUI has
    /// `InspectionModifiers.swift`, but it inspects SwiftCrossUI's own widget
    /// tree; what an `MTKView` drew inside itself is invisible to it. Rendering
    /// correctness can only be checked by a custom offscreen comparison, or not
    /// at all.* They ranked that page last of theirs for exactly that reason --
    /// it is the one part of their UI whose output no test can judge.
    ///
    /// Inspection reads the tree. This reads the picture, which is the only
    /// thing that can answer "did it draw" about a view the framework does not
    /// draw.
    ///
    /// **The pixel format is the one ``Images`` already uses** -- rows of RGBA8
    /// concatenated, width and height in pixels -- so a snapshot can be handed
    /// straight back to an ``Image`` with no conversion. Two spellings of the
    /// same thing in one framework is how the two drift.
    ///
    /// 把一個 widget **實際畫出來的像素**讀回來。
    ///
    /// **它的存在,源自別人撞到、而且用他們自己的話寫下來的一個缺口。** `SoftPCB-UI` 的 `plan.md`
    /// §10.7 以一張標題為「真正的阻礙」的表作結,其第二列寫著:*SwiftCrossUI 有
    /// `InspectionModifiers.swift`,但它檢視的是 SwiftCrossUI 自己的 widget 樹;`MTKView` 內部畫了什麼,
    /// 那套機制看不到。渲染正確性只能靠自訂的離屏比對,或不測。* 他們把那一頁排在最後,理由正是如此
    /// ——那是他們整個 UI 裡,唯一一塊「輸出正確與否無法由測試判定」的部分。
    ///
    /// Inspection 讀的是樹。這個讀的是**畫面**——而對一個「不是由框架畫出來的 view」而言,那是唯一
    /// 回答得了「它到底有沒有畫」的東西。
    ///
    /// **像素格式沿用 ``Images`` 已經在用的那一個**——逐列串接的 RGBA8,寬高以像素計——因此一份快照
    /// 可以不經轉換就交回給 ``Image``。同一件事在一個框架裡有兩種寫法,正是兩者開始漂移的方式。
    @MainActor
    public protocol WidgetSnapshots<Widget>: Core {
        /// Reads back what this widget currently shows.
        ///
        /// Returns `nil` when the widget has no pixels to give -- a zero-sized
        /// view, or one the backend cannot read from -- rather than an empty
        /// image. **A blank snapshot and a failed snapshot must not look the
        /// same**: a caller comparing images would call the first a difference
        /// and the second a match, and only one of those is a conclusion.
        ///
        /// The size is in PIXELS, not points, and on a 2x display it is twice
        /// the widget's layout size in each direction.
        ///
        /// 把這個 widget 目前顯示的內容讀回來。
        ///
        /// 當這個 widget 沒有像素可給時回傳 `nil`——尺寸為零、或 backend 讀不到它——而不是回傳一張空白
        /// 影像。**空白的快照與失敗的快照不可以長得一樣**:一個比對影像的呼叫端,會把前者當成「有差異」、
        /// 把後者當成「相符」,而其中只有一個是結論。
        ///
        /// 尺寸單位是**像素**、不是點;在 2x 顯示器上,它是該 widget 版面尺寸的兩倍(每個方向)。
        func snapshotWidget(_ widget: Widget) -> WidgetSnapshot?
    }
}
