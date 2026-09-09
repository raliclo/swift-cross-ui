/// A scene that holds the app's settings, shown by ``EnvironmentValues/openSettings``.
///
/// ```swift
/// var body: some Scene {
///     WindowGroup("Editor") { EditorView() }
///     Settings { SettingsView() }
/// }
/// ```
///
/// **How it appears is the backend's answer, not the app's.** With multiple
/// windows it is a window of its own, titled "Settings"; without them it is a
/// sheet over the window that already exists. Both are real presentations, and
/// the choice is made by asking ``BaseAppBackend/supportsMultipleWindows``
/// rather than by hard-coding either.
///
/// The single-window path is not a fallback added for tidiness. Measured
/// 2026-09-09: `AndroidBackend.createWindow` returns a fresh `Window()` value
/// with a `TODO` beside it, so a window-based Settings there would be silently
/// invisible -- and CLAUDE.md rules that out, since a truthful report of a
/// missing feature is not the same as a working one.
///
/// | backend | `supportsMultipleWindows` | how settings appear |
/// | --- | --- | --- |
/// | AppKit, Gtk, WinUI | true | a separate window |
/// | UIKit, Android | false | a sheet over the current window |
///
/// 一個承載 app 設定的 scene,由 ``EnvironmentValues/openSettings`` 顯示。
///
/// **它「怎麼出現」是由 backend 回答的,不是由 app 回答的。** 有多視窗時它是一個標題為「Settings」
/// 的獨立視窗;沒有多視窗時,它是蓋在既有視窗上的一個 sheet。兩者都是真正的呈現,而這個選擇來自詢問
/// ``BaseAppBackend/supportsMultipleWindows``,而不是把其中一種寫死。
///
/// 單視窗那條路不是為了整齊而補上的退路。2026-09-09 實測:`AndroidBackend.createWindow` 回傳的是一個
/// 旁邊還留著 `TODO` 的新 `Window()` 值,因此在那裡以視窗為基礎的 Settings 會靜默地隱形——而
/// CLAUDE.md 排除了這種做法,因為「如實回報一項缺失的功能」與「擁有一項可運作的功能」是兩回事。
public struct Settings<Content: View>: WindowingScene {
    public typealias Node = SettingsNode<Content>

    /// The title of the settings window on backends that open one.
    ///
    /// Not configurable, and matching SwiftUI, whose `Settings` scene takes no
    /// title either: the window is the app's settings and every desktop
    /// platform already has a name for that.
    /// 在會開啟視窗的 backend 上,那個設定視窗的標題。
    ///
    /// 不可設定,並與 SwiftUI 一致——它的 `Settings` scene 同樣不收標題:那個視窗就是這個 app 的設定,
    /// 而每一個桌面平台本來就已經有它自己的名字。
    public var title: String { "Settings" }

    public var content: () -> Content

    /// The id the settings window is opened under.
    ///
    /// Namespaced so an app that happens to define `Window(id: "settings")` of
    /// its own does not collide with this one -- the two would share an entry in
    /// `openWindowFunctionsByID`, and whichever registered last would win.
    /// 設定視窗所使用的 id。
    ///
    /// 加上命名空間,好讓一個「碰巧自己定義了 `Window(id: "settings")`」的 app 不會與這個相撞——那兩者
    /// 會共用 `openWindowFunctionsByID` 中的同一個項目,而最後登記的那一個會勝出。
    static var windowID: String { "swiftcrossui.settings" }

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
}

/// The ``SceneGraphNode`` corresponding to a ``Settings`` scene.
public final class SettingsNode<Content: View>: SceneGraphNode {
    public typealias NodeScene = Settings<Content>

    private var scene: Settings<Content>

    /// The settings window, on backends that have one. `nil` until it is opened,
    /// and `nil` again once it is closed.
    /// 設定視窗,僅在有視窗的 backend 上。在被開啟之前為 `nil`,被關閉之後再度為 `nil`。
    private var windowReference: WindowReference<Settings<Content>>?

    public init<Backend: BaseAppBackend>(
        from scene: Settings<Content>,
        backend: Backend,
        environment: EnvironmentValues
    ) {
        self.scene = scene
        // Never opened at launch, unlike `Window` and `WindowGroup`. A settings
        // window that appeared on every start would be the first thing the user
        // saw, and `defaultLaunchBehavior` is not consulted here because there
        // is no version of this scene that should open by itself.
        // 與 `Window` 及 `WindowGroup` 不同，此處在啟動時絕不開啟。一個每次啟動都出現的設定視窗，
        // 會是使用者看到的第一個東西；此處也不去查詢 `defaultLaunchBehavior`，因為這個 scene 沒有任何
        // 一種「應該自行開啟」的版本。
    }

    public func updateNode(
        _ newScene: NodeScene?,
        environment: EnvironmentValues
    ) -> SceneNodeUpdateResult {
        if let newScene {
            self.scene = newScene
        }

        return .leafScene()
    }

    public func update<Backend: BaseAppBackend>(
        backend: Backend,
        environment: EnvironmentValues
    ) {
        let registry = environment.settingsRegistry

        // Re-registered on every update rather than once, because the closure
        // captures `scene`, and `scene` is replaced whenever the app's body is
        // recomputed. A closure captured once would keep rendering the settings
        // view the app had at launch -- which looks like a settings screen that
        // ignores state, not like a stale closure.
        // 每一次更新都重新登記，而不是只登記一次，因為那個 closure 捕捉了 `scene`，而 `scene` 會在
        // app 的 body 被重新計算時被替換掉。只捕捉一次的 closure 會持續畫出「app 啟動當時」的那個設定
        // 畫面——那看起來會像是一個忽略狀態的設定頁，而不像一個過期的 closure。
        registry.content = { [scene] in AnyView(scene.content()) }

        if backend.supportsMultipleWindows {
            // The window path. `open` is installed here rather than in the view
            // tree because this node is the only thing that can build a window
            // for a scene it owns.
            // 視窗那條路。`open` 在此處安裝、而非在 view 樹中安裝，因為只有這個節點才建得出「屬於它
            // 自己所擁有之 scene」的視窗。
            registry.installPresenter { [weak self] in
                guard let self else { return }

                if let windowReference {
                    // Already open: bring it forward instead of opening a
                    // second one. Two settings windows is a state no platform
                    // offers and no app asked for.
                    // 已經開著：把它帶到前面，而不是再開一個。兩個設定視窗是任何平台都不提供、
                    // 也沒有任何 app 要求過的狀態。
                    windowReference.activate(backend: backend)
                } else {
                    let reference = WindowReference(
                        scene: self.scene,
                        backend: backend,
                        environment: environment,
                        onClose: { self.windowReference = nil },
                        id: Settings<Content>.windowID
                    )
                    self.windowReference = reference
                    reference.update(nil, backend: backend, environment: environment)
                }
            }
        }
        // On a single-window backend `open` is left alone: the sheet host in
        // `WindowReference` installs it when it appears. Overwriting it here
        // with a window-opening closure would produce a press that succeeds and
        // shows nothing on exactly the two platforms this path exists for.
        // 在單視窗的 backend 上，此處不去動 `open`：由 `WindowReference` 中的 sheet host 在它出現時
        // 安裝它。若在此處以一個「開視窗的 closure」覆寫掉它，會在「這條路正是為之存在」的那兩個平台上，
        // 產生一次「成功了、卻什麼也沒顯示」的按下。

        windowReference?.update(scene, backend: backend, environment: environment)
    }
}
