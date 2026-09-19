extension BackendFeatures {
    /// A view whose contents are a 3D scene the backend renders (M10).
    ///
    /// **The renderer is the framework's, not the application's, and that is the
    /// whole point of this protocol.** An application can already put an
    /// `MTKView` on screen -- every backend ships a representable escape hatch,
    /// and `SoftPCB-UI` renders a circuit board that way today. What it costs is
    /// one view and one backend dependency per platform: that application's
    /// manifest takes `AppKitBackend` conditionally on macOS to do it. Describing
    /// a mesh and letting the backend draw it is the same relationship ``Paths``
    /// already has for two dimensions.
    ///
    /// **Conformance-checked, like ``TableSelection`` and ``PopoverArrowEdges``.**
    /// A backend that has not implemented it keeps building, ``Mesh3DView``
    /// draws an empty box and says so once, and an application can ask
    /// `backend is any BackendFeatures.Mesh3DViews` to put the answer on screen
    /// -- which is what P72 does. That is not a licence to leave it unimplemented:
    /// `CLAUDE.md` is explicit that the five shipped backends implement every
    /// feature, and the order here (Apple first, the rest later) is a schedule
    /// rather than a policy.
    ///
    /// 一個「內容是由 backend 算繪的 3D 場景」的 view(M10)。
    ///
    /// **renderer 屬於框架、不屬於應用程式,而那正是這個協定存在的全部理由。** 應用程式本來就能把一個
    /// `MTKView` 放上畫面——每個 backend 都有 representable 逃生門,而 `SoftPCB-UI` 今天就是這樣畫出一塊
    /// 電路板的。它的代價是「每個平台各一個 view、各一個 backend 相依」:那支 app 的 manifest 為此在 macOS
    /// 上條件式地相依 `AppKitBackend`。改為「描述一個 mesh、由 backend 畫出來」,與 ``Paths`` 在二維上
    /// 已有的關係是同一個。
    ///
    /// **採 conformance 檢查,與 ``TableSelection``、``PopoverArrowEdges`` 相同。** 尚未實作的 backend
    /// 照常建置,``Mesh3DView`` 會畫一個空盒子並說一次,而應用程式可以用
    /// `backend is any BackendFeatures.Mesh3DViews` 把答案印在畫面上——P72 正是這麼做。這不是「可以不實作」
    /// 的許可:`CLAUDE.md` 明寫五個已發布的 backend 都要實作每一項功能,而此處的順序(Apple 先、其餘後補)
    /// 是一份時程,不是一項政策。
    @MainActor
    public protocol Mesh3DViews<Widget>: Core {
        /// A view that will show a 3D scene.
        /// 一個將用來顯示 3D 場景的 view。
        func createMesh3DView() -> Widget

        /// Hands the view the scene to draw.
        ///
        /// Called on every commit, as the other update methods are, so an
        /// application animating a camera through ``BackendFeatures/FrameClocks``
        /// simply produces a new scene per frame. A backend is free to notice
        /// that the meshes are unchanged and re-upload nothing; nothing here
        /// requires it to.
        ///
        /// 把要繪製的場景交給這個 view。
        ///
        /// 與其他 update 方法一樣,每次 commit 都會被呼叫;因此一個透過
        /// ``BackendFeatures/FrameClocks`` 讓相機動起來的應用程式,只要每幀產生一個新的場景即可。
        /// backend 可以自行判斷 mesh 沒變而不重新上傳;此處不要求它那麼做。
        ///
        /// `onFrame` is called after each frame the backend actually draws,
        /// which is **not** once per call to this method: a commit that changes
        /// nothing may draw nothing, and a resize draws without a commit. That
        /// distinction is the whole value of the callback -- P72 shows the count
        /// it reports, and a count that advanced is the difference between a
        /// pipeline that compiles and a pipeline that runs.
        ///
        /// `onFrame` 會在 backend **實際畫出**每一幀之後被呼叫,而那**不是**「每呼叫本方法一次就一次」:
        /// 一次什麼都沒改變的 commit 可能不會畫,而一次縮放則會在沒有 commit 的情況下畫。那個分野正是
        /// 這個 callback 的全部價值——P72 顯示它回報的計數,而「計數有前進」正是
        /// 「pipeline 編得過」與「pipeline 真的在跑」之間的差別。
        func updateMesh3DView(
            _ view: Widget,
            scene: Mesh3DScene,
            onFrame: @escaping @MainActor (Mesh3DFrameInfo) -> Void,
            environment: EnvironmentValues
        )
    }
}
