extension View {
    /// Sets the style of text fields contained within this view.
    ///
    /// - Parameter style: The new text field style.
    ///
    /// ## See Also
    ///
    /// - ``TextFieldStyle``
    /// - ``BackendTextFieldStyle`` for what each shape looks like per platform,
    ///   and what ``TextFieldStyle/automatic`` leaves in place.
    ///
    /// 設定此 view 之下所有文字輸入框的樣式。
    public func textFieldStyle(_ style: any TextFieldStyle) -> some View {
        EnvironmentModifier(self) { environment in
            // Only `\.textFieldStyle` is written here, unlike
            // `listStyle(_:)`, which also resolves and writes
            // `\.backendListStyle` in this closure.
            //
            // The resolution cannot happen here, because it needs
            // `_asBackendTextFieldStyle`, which lives on
            // `_BuiltinTextFieldStyle` and so exists only for the four built-in
            // styles. `listStyle(_:)` can do it inline because `ListStyle`
            // itself declares `_asBackendListStyle` -- that protocol is not
            // open in the way this one is, so every conformer has the method.
            //
            // Doing it here anyway, behind an `as? any _BuiltinTextFieldStyle`
            // cast the way `datePickerStyle(_:)` does, would also write the
            // value onto every widget in the subtree rather than onto the text
            // fields, which is harmless only for as long as nothing else reads
            // it. `_BuiltinTextFieldImplementation` sets it where it belongs.
            //
            // 此處只寫入 `\.textFieldStyle`，與 `listStyle(_:)` 不同——後者會在這個 closure 裡一併
            // 解析並寫入 `\.backendListStyle`。
            //
            // 這裡無法進行解析，因為那需要 `_asBackendTextFieldStyle`，而該方法位於
            // `_BuiltinTextFieldStyle` 上，因此只有四個內建 style 才有。`listStyle(_:)` 之所以能
            // 就地完成，是因為 `ListStyle` 本身就宣告了 `_asBackendListStyle`——那個 protocol 並不
            // 像這個一樣開放，所以它的每一個 conformer 都具備該方法。
            //
            // 就算比照 `datePickerStyle(_:)`，在此加一個 `as? any _BuiltinTextFieldStyle` 的 cast
            // 硬做，也會把該值寫到子樹中每一個 widget 上、而非寫到那些文字輸入框上；那只在「目前
            // 沒有別的東西會讀它」的前提下才無害。`_BuiltinTextFieldImplementation` 會把它設定在
            // 它該在的位置。
            environment.with(\.textFieldStyle, style)
        }
    }
}
