/// An action that shows the app's ``Settings`` scene.
@MainActor
public struct OpenSettingsAction {
    let environment: EnvironmentValues

    /// Shows the settings.
    ///
    /// Which presentation appears is the backend's answer: a window where there
    /// can be one, a sheet over the current window where there cannot.
    /// 顯示設定。出現的是哪一種呈現，由 backend 決定：能開視窗的地方開視窗，不能的地方在當前視窗上
    /// 蓋一個 sheet。
    public func callAsFunction() {
        let registry = environment.settingsRegistry
        guard let open = registry.open else {
            // Remembered before warning. A presenter that appears a moment later
            // honours the request instead of leaving a press that did nothing --
            // and the warning still fires, because "settings will open shortly"
            // and "this app declares no Settings scene" both reach this line and
            // only the app author can tell them apart.
            // 先記下、再警告。稍後才出現的呈現者會履行這個請求，而不是留下一次毫無作用的按下——
            // 而那句警告仍然會發出，因為「設定馬上就會開啟」與「這個 app 沒有宣告 Settings scene」
            // 兩者都會抵達這一行，而只有 app 的作者分辨得出是哪一種。
            registry.hasPendingOpen = true
            // Warned rather than ignored. Reaching here means either the app
            // declared no `Settings` scene, or the window that hosts the sheet
            // has not appeared yet -- and both produce a button press that
            // changes nothing on screen, which reads like a broken button.
            // 發出警告而非忽略。抵達這裡代表：該 app 沒有宣告 `Settings` scene，或是承載該 sheet 的
            // 視窗尚未出現——兩者都會產生一次「畫面毫無變化」的按下，而那讀起來像是一顆壞掉的按鈕。
            logger.warning(
                """
                openSettings() called but nothing can present settings; does the \
                app's body include a 'Settings' scene?
                """
            )
            return
        }
        open()
    }
}
