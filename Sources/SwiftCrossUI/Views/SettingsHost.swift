/// Wraps a window's root view so that ``Settings`` can be presented over it on
/// backends that cannot open a second window.
///
/// **Every window gets one, and only one of them ever presents anything.** On a
/// backend with multiple windows the sheet path is never armed -- ``SettingsNode``
/// installs a window-opening closure instead -- so this wrapper adds one node
/// and no behaviour. On a single-window backend there is exactly one window, so
/// "which window presents it" has one answer and needs no arbitration.
///
/// The closure is installed from `onAppear` rather than from `body`, because
/// installing it during body evaluation would be a side effect performed every
/// time the view is recomputed, including during the update that the
/// installation itself triggers.
///
/// 包住一個視窗的 root view，好讓 ``Settings`` 能在「開不出第二個視窗」的 backend 上被呈現於其上。
///
/// **每個視窗都會有一個，而其中永遠只有一個真的會呈現東西。** 在有多視窗的 backend 上，sheet 這條路
/// 從未被啟用——``SettingsNode`` 安裝的是一個「開視窗」的 closure——因此本 wrapper 只多出一個節點、
/// 不改變任何行為。在單視窗的 backend 上，視窗恰好只有一個，因此「由哪個視窗呈現」只有一個答案，
/// 不需要任何仲裁。
///
/// 那個 closure 由 `onAppear` 安裝，而非由 `body` 安裝，因為在 body 求值期間安裝它會是一個「每次
/// 該 view 被重新計算就執行一次」的副作用——包括在「該安裝本身所觸發的那次更新」期間。
struct SettingsHost<Content: View>: View {
    var content: Content

    @State private var isPresented = false
    @Environment(\.settingsRegistry) private var registry
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        // **The sheet is attached only where it can be used, and that is not
        // tidiness -- attaching it everywhere aborts the process.** `.sheet`
        // routes through `@CastBackend`, which expands to `fatalError` on a
        // backend with no `BackendFeatures.Sheets` conformance. `DummyBackend`
        // is one, so wrapping unconditionally turned every windowed test into
        // "Fatal error: 'DummyBackend' does not implement 'BackendFeatures.Sheets'".
        // Caught 2026-09-09 by `Scripts/test.sh`, which is the only reason it is
        // not in the tree: the build itself was perfectly happy.
        //
        // The condition is the same one that decides the route, so a backend
        // never gets a sheet it would not have presented anyway.
        //
        // **這個 sheet 只掛在「用得到它」的地方，而那不是為了整齊——到處掛會讓行程中止。**
        // `.sheet` 走的是 `@CastBackend`，它在沒有 `BackendFeatures.Sheets` conformance 的 backend 上
        // 會展開為 `fatalError`。`DummyBackend` 正是其中之一，因此無條件包裹會讓每一個帶視窗的測試
        // 變成「Fatal error: 'DummyBackend' does not implement 'BackendFeatures.Sheets'」。
        // 2026-09-09 由 `Scripts/test.sh` 抓到，而那正是它沒有進到樹裡的唯一理由：建置本身毫無怨言。
        //
        // 這個條件與「決定走哪條路」的條件是同一個，因此不會有任何 backend 拿到一個它本來也不會呈現的
        // sheet。
        if supportsMultipleWindows {
            content
        } else {
            content
                .sheet(isPresented: $isPresented) {
                // The registry's content, or nothing. `EmptyView` rather than a
                // placeholder message: reaching here with no content means the
                // app has no `Settings` scene, and in that case `openSettings`
                // never armed this closure, so the sheet cannot have been asked
                // for in the first place.
                // registry 的內容，或什麼都沒有。使用 `EmptyView` 而非一句佔位訊息：若在此處沒有內容，
                // 代表該 app 沒有 `Settings` scene，而那種情況下 `openSettings` 從未啟用過這個
                // closure，因此這個 sheet 根本不可能被要求過。
                    if let content = registry.content {
                        content()
                    } else {
                        AnyView(EmptyView())
                    }
                }
                .onAppear {
                    // Through `installPresenter`, which also honours a request
                    // that arrived before this ran -- a root view's `onAppear`
                    // fires before this one's.
                    // 透過 `installPresenter`，它同時會履行「在此之前就抵達」的請求——root view 的
                    // `onAppear` 會比這一個先觸發。
                    registry.installPresenter { isPresented = true }
                }
        }
    }
}
