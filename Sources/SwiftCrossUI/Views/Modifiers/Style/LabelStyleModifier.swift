extension View {
    /// Sets the style of labels contained within this view.
    ///
    /// Propagated through the environment, so the innermost `.labelStyle(_:)`
    /// wins: ``EnvironmentModifier`` applies its modification as the tree
    /// descends, and a nested call therefore overwrites an outer one for its own
    /// subtree only.
    ///
    /// Unlike ``View/pickerStyle(_:)`` this cannot refuse a style, and there is
    /// no `isSupported` to consult. A label style rearranges views the caller
    /// already supplied; no backend is asked for anything, so no backend can
    /// decline. See ``LabelStyle`` for why that member is absent rather than
    /// stubbed out to `true`.
    ///
    /// - Parameter style: The label style to use.
    ///
    /// ## See Also
    ///
    /// - ``LabelStyle``
    ///
    /// 設定此 view 之下所有 label 的樣式。
    ///
    /// 透過 environment 傳遞，因此最內層的 `.labelStyle(_:)` 勝出：``EnvironmentModifier`` 是在樹
    /// 向下走的過程中套用其修改，因此巢狀的呼叫只會在它自己的子樹中覆寫外層的設定。
    ///
    /// 與 ``View/pickerStyle(_:)`` 不同，此處無法拒絕某個樣式，也沒有 `isSupported` 可查。label
    /// style 重新排列的是呼叫端本來就提供的 view；沒有向任何 backend 索取東西，因此也沒有 backend
    /// 能夠拒絕。該成員為何是「缺席」而非「填一個 `true` 的樁」，見 ``LabelStyle``。
    public func labelStyle(_ style: any LabelStyle) -> some View {
        EnvironmentModifier(self) { environment in
            environment.with(\.labelStyle, style)
        }
    }
}
