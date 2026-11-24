extension View {
    /// Sets the accent colour of the controls in this view, as SwiftUI's
    /// `tint(_:)` does.
    ///
    /// Inherited through the environment, so `.tint(.green)` on a stack
    /// recolours every switch, checkbox, slider, progress bar and accent-drawn
    /// button label inside it; see ``EnvironmentValues/tint`` for what each
    /// backend paints with it. `nil` gives the subtree back the platform's own
    /// accent, so an inner `.tint(nil)` undoes an outer one. It changes colour
    /// only: no control changes size.
    ///
    /// 設定此 view 中控制項的強調色，與 SwiftUI 的 `tint(_:)` 相同。
    ///
    /// 經由 environment 繼承，所以加在 stack 上的 `.tint(.green)` 會重新上色其中每一個開關、核取方塊、滑桿、
    /// 進度條以及以強調色繪製的按鈕標籤；各 backend 用它畫什麼見 ``EnvironmentValues/tint``。`nil` 讓這個子樹回到
    /// 平台自己的強調色，所以內層的 `.tint(nil)` 會取消外層的設定。它只改變顏色：沒有任何控制項會改變大小。
    ///
    /// - Parameter tint: The accent colour, or `nil` for the platform's.
    public func tint(_ tint: Color?) -> some View {
        EnvironmentModifier(self) { environment in
            environment.with(\.tint, tint)
        }
    }
}
