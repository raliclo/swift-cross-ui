extension View {
    /// Presents `content` over the whole window while `isPresented` is true.
    ///
    /// Built on ``View/sheet(isPresented:onDismiss:content:)`` rather than on a
    /// new backend requirement, because a full-screen cover is a sheet with its
    /// options pinned: it fills the presentation, it has no rounded corners and
    /// no drag indicator, and it cannot be dismissed by dragging. All five
    /// backends already implement ``BackendFeatures/Sheets``, so this works
    /// everywhere the moment it exists, and each backend's own sheet
    /// presentation is what appears.
    ///
    /// **The four options below are the definition, not defaults.** SwiftUI's
    /// `fullScreenCover` differs from its `sheet` in exactly these ways, and
    /// each one is set here rather than left to the caller because a cover the
    /// user can swipe away is a sheet, and a sheet presented at full height is
    /// still a sheet. A caller that wants any of them back wants `sheet`.
    ///
    /// 當 `isPresented` 為真時，將 `content` 呈現在整個視窗之上。
    ///
    /// 建構於 ``View/sheet(isPresented:onDismiss:content:)`` 之上，而非另立一項新的 backend 需求——
    /// 因為 full-screen cover 就是一個把選項釘死的 sheet:它填滿整個呈現、沒有圓角、沒有拖曳指示，
    /// 也無法以拖曳關閉。五個 backend 皆已實作 ``BackendFeatures/Sheets``，因此它一存在就在每個地方
    /// 都能運作，且出現的正是各 backend 自身的 sheet 呈現方式。
    ///
    /// **下方那四個選項就是它的定義，不是預設值。** SwiftUI 的 `fullScreenCover` 與其 `sheet` 的差別
    /// 恰恰就是這幾項，而每一項都在此處設定、不交由呼叫端——因為一個使用者可以滑掉的 cover 就是
    /// sheet，而一個以全高呈現的 sheet 仍然是 sheet。想要拿回其中任何一項的呼叫端，要的是 `sheet`。
    public func fullScreenCover<CoverContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> CoverContent
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content()
                // The frame is not decoration. `.fraction(1)` makes the sheet
                // machinery propose the window's size, and a proposal is only an
                // offer -- a VStack takes its ideal size and leaves the rest.
                // Without this the cover was laid out at 431x128 inside a 780x620
                // window and appeared as a small rounded panel with the page
                // still legible around it, which is a sheet.
                //
                // 這個 frame 不是裝飾。`.fraction(1)` 會讓 sheet 機制提議視窗的尺寸,而提議終究只是
                // 提議——VStack 會取它的理想尺寸,剩下的留著不用。少了這一行,該 cover 會在一個
                // 780x620 的視窗中以 431x128 佈局,呈現為一塊小的圓角面板、四周的頁面仍然讀得到
                // ——那就是一個 sheet。
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .presentationDetents([.fraction(1)])
                .presentationCornerRadius(0)
                .presentationDragIndicatorVisibility(.hidden)
                .interactiveDismissDisabled()
        }
    }
}
