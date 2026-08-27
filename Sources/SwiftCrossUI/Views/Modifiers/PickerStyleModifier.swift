/// Styles already reported as unsupported.
///
/// The modification closure below runs on every `computeLayout` and every
/// `commit`, so an ungated log would repeat several times a frame for as long
/// as the view exists. Written without a lock, as `_logger` is: this runs on
/// the main actor with the rest of the view tree.
///
/// The element is optional so that nothing has to invent a stand-in for a style
/// that did not resolve. Only a built-in style can be unsupported -- a custom
/// one takes `PickerStyle`'s default `isSupported`, which is always `true` --
/// so `nil` is unreachable in practice, and a `Set` that says so is cheaper
/// than a fallback nobody can justify.
///
/// 元素為 optional，如此便不需要為「未能解析的 style」憑空捏造一個替代值。只有內建的 style 才
/// 可能不被支援——自訂 style 走的是 `PickerStyle` 的預設 `isSupported`，永遠回傳 `true`——因此
/// `nil` 在實務上不可能出現，而一個如實表達這點的 `Set`，比一個無從辯護的 fallback 更划算。
private nonisolated(unsafe) var warnedPickerStyles: Set<BackendPickerStyle?> = []

extension View {
    /// Sets the picker style for views.
    ///
    /// - Parameter style: The picker style to use.
    ///
    /// ## See Also
    ///
    /// - ``PickerStyle``
    public func pickerStyle(_ style: any PickerStyle) -> some View {
        EnvironmentModifier(self) { environment in
            if !style.isSupported(backend: environment.backend) {
                // `assertionFailure` alone is compiled out of a release build,
                // and release is what this project builds by default (see the
                // `testapp/compile.zsh` policy in CLAUDE.md), so a picker style
                // the backend cannot honour was downgraded to `.automatic` in
                // silence: an author who asked for a segmented control got a
                // dropdown with no way to find out why. That is #38's defect,
                // and `DatePickerStyleModifier` recorded it as waiting here.
                // The style that is unsupported is a property of the backend,
                // not of the moment, so saying it once is saying it.
                //
                // `assertionFailure` 在 release 建置中會被編譯掉，而 release 正是本專案的預設
                // 建置方式（見 CLAUDE.md 中的 `testapp/compile.zsh` 政策），因此 backend 無法
                // 支援的 picker style 會被默默降級為 `.automatic`：作者要的是分段控制項，拿到
                // 的卻是下拉選單，且無從得知原因。這正是 #38 的缺陷，而
                // `DatePickerStyleModifier` 早已記下它潛伏在此處。style 不被支援是 backend 的
                // 屬性、而非某個時刻的屬性，因此說一次就等於說了。
                let resolved = (style as? any _BuiltinPickerStyle)?
                    ._asBackendPickerStyle(backend: environment.backend)
                if warnedPickerStyles.insert(resolved).inserted {
                    logger.warning(
                        """
                        picker style \(type(of: style)) is not supported by \
                        \(type(of: environment.backend)); using .automatic instead
                        """
                    )
                }
                assertionFailure(
                    "Picker style \(style) not supported by backend \(type(of: environment.backend))"
                )
                return environment.with(\.pickerStyle, .automatic)
            }
            return environment.with(\.pickerStyle, style)
        }
    }
}
