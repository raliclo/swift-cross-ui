import Foundation

/// One vertex of a ``Mesh3D``: where it is, which way the surface faces, and
/// what colour it is there.
///
/// **Colour per vertex rather than a material, for now.** three.js has
/// `MeshStandardMaterial` and a lighting model behind it; this has one
/// directional light and a colour, which is what a first renderer can honestly
/// implement on every backend rather than on one. Materials are the obvious
/// next argument and they are deliberately not smuggled in here as an optional
/// field that only Metal reads.
///
/// ``Mesh3D`` 的一個頂點:它在哪裡、表面朝哪個方向、以及該處是什麼顏色。
///
/// **目前是逐頂點顏色,而不是材質。** three.js 有 `MeshStandardMaterial` 與其後的光照模型;
/// 此處只有一盞方向光與一個顏色——那是「第一版 renderer 能在**每一個** backend 上誠實實作」的東西,
/// 而不是只在其中一個上。材質是顯然的下一個議題,而此處刻意不把它偷渡成「只有 Metal 會讀」的選填欄位。
public struct Mesh3DVertex: Equatable, Sendable {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var colour: SIMD3<Float>

    public init(
        position: SIMD3<Float>,
        normal: SIMD3<Float>,
        colour: SIMD3<Float>
    ) {
        self.position = position
        self.normal = normal
        self.colour = colour
    }
}

/// An indexed triangle mesh.
///
/// Indices are triples, so `indices.count` is three times the triangle count. A
/// mesh whose index count is not a multiple of three is a programming error the
/// backend will not try to repair: it draws the whole triples and ignores the
/// remainder, because silently inventing a vertex is worse than a missing
/// triangle nobody asked for.
///
/// 一個帶索引的三角網格。
///
/// 索引以三個為一組,因此 `indices.count` 是三角形數量的三倍。索引數不是三的倍數,是呼叫端的錯誤,
/// 而 backend 不會試著替它修補:它會畫出完整的那些三元組、忽略餘數——因為「靜默地生出一個頂點」
/// 比「少一個沒人要求的三角形」更糟。
public struct Mesh3D: Equatable, Sendable {
    public var vertices: [Mesh3DVertex]
    public var indices: [UInt32]

    /// Where this mesh sits, and how it is turned.
    ///
    /// **One level of transform, not a scene graph, and the difference is the
    /// whole design.** three.js's `Object3D` has parents and children, so a
    /// backend has to flatten a tree and five backends have five chances to
    /// flatten it differently. A single transform per mesh has no tree to
    /// flatten and still covers what an application actually asks for -- move
    /// this, spin that -- without the vertices being rewritten to do it.
    ///
    /// Keeping it here rather than in the application also keeps the geometry
    /// CONSTANT while a thing spins, which is what lets the backend skip the
    /// upload: a cube turning at 60 Hz re-uploads nothing.
    ///
    /// 這個 mesh 在哪裡、怎麼轉。
    ///
    /// **一層變換,而不是一棵 scene graph——那個差別就是整個設計。** three.js 的 `Object3D` 有親子關係,
    /// 因此 backend 必須攤平一棵樹,而五個 backend 就有五次把它攤得不一樣的機會。每個 mesh 一個變換,
    /// 沒有樹要攤平,卻仍涵蓋了應用程式真正會提的要求——把這個移過去、讓那個轉起來——而且不必為此改寫頂點。
    ///
    /// 把它放在這裡而不是放在應用程式裡,還有一個效果:一個東西在自轉的時候,它的幾何是**不變的**——
    /// 而那正是讓 backend 能跳過上傳的條件:一個以 60 Hz 轉動的立方體,一個位元組都不必重傳。
    public var transform: Mesh3DTransform

    public init(
        vertices: [Mesh3DVertex],
        indices: [UInt32],
        transform: Mesh3DTransform = Mesh3DTransform()
    ) {
        self.vertices = vertices
        self.indices = indices
        self.transform = transform
    }
}

/// Where a ``Mesh3D`` is put before it is drawn: scaled, turned, then moved.
///
/// **The order is fixed and stated because it is not guessable.** Scale, then
/// rotate, then translate -- the usual one, and the one three.js's
/// `Object3D.updateMatrix` uses. Rotation is three Euler angles in radians
/// applied Z, then Y, then X. An application that needs an order this does not
/// offer can still bake its own transform into the vertices; what it cannot do
/// is get a different answer out of two backends, because the order is here
/// rather than in each of them.
///
/// 一個 ``Mesh3D`` 在被畫出來之前會被怎麼擺放:先縮放、再旋轉、最後平移。
///
/// **這個順序是固定的,而且此處明說,因為它猜不出來。** 縮放 → 旋轉 → 平移,是慣用的那一個,也是
/// three.js `Object3D.updateMatrix` 所用的那一個。旋轉是三個以弧度表示的 Euler 角,依 Z、Y、X 的
/// 次序套用。需要別種順序的應用程式,仍然可以把自己的變換烘進頂點裡;它做不到的是「從兩個 backend
/// 得到不同的答案」——因為順序寫在這裡,而不是寫在它們各自裡面。
public struct Mesh3DTransform: Equatable, Sendable {
    public var translation: SIMD3<Float>
    /// Euler angles in radians, applied Z then Y then X.
    /// 以弧度表示的 Euler 角,依 Z、Y、X 的次序套用。
    public var rotation: SIMD3<Float>
    public var scale: SIMD3<Float>

    public init(
        translation: SIMD3<Float> = SIMD3(0, 0, 0),
        rotation: SIMD3<Float> = SIMD3(0, 0, 0),
        scale: SIMD3<Float> = SIMD3(1, 1, 1)
    ) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }

    /// Turns the mesh in the XY plane -- a rotation about Z, which is the one
    /// that reads as spinning in the plane of the screen.
    /// 讓 mesh 在 XY 平面上轉動——也就是繞 Z 軸旋轉,那正是「在螢幕所在平面上自轉」看起來的樣子。
    public static func rotatedInXY(_ radians: Float) -> Mesh3DTransform {
        Mesh3DTransform(rotation: SIMD3(0, 0, radians))
    }
}

/// Where the scene is looked at from.
///
/// A position, a target and an up vector, plus a vertical field of view in
/// degrees and the near and far planes -- the same five things three.js's
/// `PerspectiveCamera` takes, named the same way, so that a reader who knows one
/// can read the other.
///
/// 從哪裡看這個場景。
///
/// 一個位置、一個目標、一個上方向,加上以「度」為單位的垂直視角與近遠平面——與 three.js 的
/// `PerspectiveCamera` 所取的是同樣五件事、名字也相同,好讓看得懂其中一邊的人看得懂另一邊。
public struct Mesh3DCamera: Equatable, Sendable {
    public var position: SIMD3<Float>
    public var target: SIMD3<Float>
    public var up: SIMD3<Float>
    /// Vertical field of view, in degrees.
    /// 垂直視角,單位為度。
    public var fieldOfView: Float
    public var near: Float
    public var far: Float

    public init(
        position: SIMD3<Float> = SIMD3(0, 0, 3),
        target: SIMD3<Float> = SIMD3(0, 0, 0),
        up: SIMD3<Float> = SIMD3(0, 1, 0),
        fieldOfView: Float = 50,
        near: Float = 0.1,
        far: Float = 100
    ) {
        self.position = position
        self.target = target
        self.up = up
        self.fieldOfView = fieldOfView
        self.near = near
        self.far = far
    }
}

/// Everything a ``Mesh3DView`` draws: some meshes, a camera, a background and
/// one directional light.
///
/// There is no scene graph. three.js has `Object3D` with parents, children and
/// per-node transforms, and adding that here would mean every backend either
/// flattening it the same way or disagreeing about how. A flat array of meshes
/// whose vertices are already in world space is the version whose meaning
/// cannot drift between five implementations.
///
/// ``Mesh3DView`` 所畫的一切:若干 mesh、一台相機、一個背景,以及一盞方向光。
///
/// **沒有 scene graph。** three.js 有帶親子關係與各節點變換的 `Object3D`;把它加進來,等於要求每個
/// backend 要嘛以相同方式攤平它、要嘛對「該怎麼攤平」各持己見。一個「頂點已經在世界座標」的平面陣列,
/// 是那個「意義不會在五份實作之間漂移」的版本。
public struct Mesh3DScene: Equatable, Sendable {
    public var meshes: [Mesh3D]
    public var camera: Mesh3DCamera
    public var background: Color
    /// The direction light travels, in world space; it is normalised by the
    /// backend.
    /// 光行進的方向(世界座標);由 backend 做正規化。
    public var lightDirection: SIMD3<Float>

    public init(
        meshes: [Mesh3D] = [],
        camera: Mesh3DCamera = Mesh3DCamera(),
        background: Color = Color(red: 0.1, green: 0.1, blue: 0.12),
        lightDirection: SIMD3<Float> = SIMD3(-0.4, -0.8, -0.45)
    ) {
        self.meshes = meshes
        self.camera = camera
        self.background = background
        self.lightDirection = lightDirection
    }
}

/// What the backend reports after drawing a frame.
///
/// **The drawable size is in pixels, and the layout size is in points.** On a
/// 2x display they differ by a factor of two, and a renderer that confuses them
/// draws a quarter of the view and stretches it -- which looks like a blurry
/// scene rather than like a bug. P72 shows both numbers side by side so the
/// factor is visible rather than inferred.
///
/// backend 畫完一幀之後回報的內容。
///
/// **drawable 尺寸的單位是像素,而 layout 尺寸的單位是點。** 在 2x 顯示器上兩者差兩倍,而一個把它們
/// 搞混的 renderer 會只畫出四分之一的範圍再拉伸——那看起來像「畫面糊掉」而不像一個 bug。P72 把兩個
/// 數字並排顯示,好讓那個倍率是**看得見**的,而不是推論出來的。
public struct Mesh3DFrameInfo: Equatable, Sendable {
    /// Which renderer drew it, named well enough to tell two apart -- e.g.
    /// `Metal (Apple M1 Max)`.
    /// 是哪一個 renderer 畫的,而且名字要足以分辨兩者——例如 `Metal (Apple M1 Max)`。
    public var renderer: String
    /// The drawable's size in pixels.
    /// drawable 的尺寸,單位為像素。
    public var drawableSize: SIMD2<Int>
    /// Frames drawn since the view was created.
    /// 自這個 view 被建立以來已畫出的幀數。
    public var frameCount: Int

    public init(renderer: String, drawableSize: SIMD2<Int>, frameCount: Int) {
        self.renderer = renderer
        self.drawableSize = drawableSize
        self.frameCount = frameCount
    }
}

/// A handle an application holds so it can ask a ``Mesh3DView`` for its pixels.
///
/// **A view cannot be asked for anything -- it is a value that is rebuilt on
/// every update -- so the question has to be left somewhere that outlives it.**
/// This is that somewhere. The view fills it in when it commits, against
/// whichever widget the backend gave it, and empties it when the backend cannot
/// read pixels back at all.
///
/// 一個由應用程式持有的把手,用來向 ``Mesh3DView`` 要它的像素。
///
/// **一個 view 是問不了問題的——它是一個在每次更新時都會被重建的值——因此那個問題必須被放在某個
/// 比它活得久的地方。** 這就是那個地方。view 在 commit 時把它填上(針對 backend 交給它的那個 widget),
/// 而當 backend 根本讀不回像素時則把它清空。
@MainActor
public final class Mesh3DSnapshotter {
    private var take: (() -> WidgetSnapshot?)?

    public init() {}

    /// Whether the backend behind this view can read its pixels back.
    ///
    /// False before the view has committed once, and false on a backend with no
    /// ``BackendFeatures/WidgetSnapshots`` conformance. An application should
    /// show which of those it is rather than a disabled button with no reason.
    ///
    /// 這個 view 背後的 backend 是否讀得回它的像素。
    ///
    /// 在 view 第一次 commit 之前為 false;在沒有 ``BackendFeatures/WidgetSnapshots`` conformance 的
    /// backend 上也是 false。應用程式應該顯示「是哪一種」,而不是一顆沒有理由的停用按鈕。
    public var isAvailable: Bool { take != nil }

    /// Reads the pixels, or `nil` if there are none to read.
    /// 讀回那些像素;沒有東西可讀時回傳 `nil`。
    public func snapshot() -> WidgetSnapshot? { take?() }

    fileprivate func bind(_ take: (() -> WidgetSnapshot?)?) {
        self.take = take
    }
}

/// A view that shows a ``Mesh3DScene``.
///
/// **What a backend that has not implemented this does, and why it is not a
/// `fatalError`.** `@CastBackend` -- the macro behind ``WebView`` and the shapes
/// -- expands to `fatalError` when the backend does not conform, and `CLAUDE.md`
/// records what that cost once already: three test apps with no window at all on
/// macOS because two effects went through it. M10 lands on AppKit and UIKit
/// first by the user's decision of 2026-09-19, so three backends would meet that
/// `fatalError` on the day it landed. This checks conformance instead, draws an
/// empty container, and says so once per backend.
///
/// 一個顯示 ``Mesh3DScene`` 的 view。
///
/// **尚未實作的 backend 會怎樣,以及為何不是 `fatalError`。** `@CastBackend`——``WebView`` 與各種形狀
/// 背後的那個 macro——在 backend 不 conform 時會展開為 `fatalError`,而 `CLAUDE.md` 記載過那一次的代價:
/// 兩個效果走了它,結果三支測試 app 在 macOS 上根本開不出視窗。依使用者 2026-09-19 的決定,M10 先落在
/// AppKit 與 UIKit,因此落地當天會有三個 backend 撞上那個 `fatalError`。此處改為檢查 conformance、
/// 畫一個空容器,並且每個 backend 說一次。
public struct Mesh3DView: ElementaryView {
    private static let idealSize = ViewSize(320, 240)

    private var scene: Mesh3DScene
    private var onFrame: (@MainActor (Mesh3DFrameInfo) -> Void)?
    private var snapshotter: Mesh3DSnapshotter?

    public init(
        _ scene: Mesh3DScene,
        onFrame: (@MainActor (Mesh3DFrameInfo) -> Void)? = nil,
        snapshotter: Mesh3DSnapshotter? = nil
    ) {
        self.scene = scene
        self.onFrame = onFrame
        self.snapshotter = snapshotter
    }

    public func asWidget<Backend: BaseAppBackend>(backend: Backend) -> Backend.Widget {
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.Mesh3DViews
        else {
            Mesh3DDegradation.reportOnce(backend: "\(Backend.self)")
            return backend.createContainer()
        }
        return makeView(backend) as! Backend.Widget
    }

    private func makeView<Backend: BaseAppBackend & BackendFeatures.Mesh3DViews>(
        _ backend: Backend
    ) -> Backend.Widget {
        backend.createMesh3DView()
    }

    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        ViewLayoutResult.leafView(
            size: proposedSize.replacingUnspecifiedDimensions(by: Self.idealSize)
        )
    }

    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.setSize(of: widget, to: layout.size.vector)
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.Mesh3DViews
        else { return }
        update(backend, widget: widget, environment: environment)
    }

    private func update<Backend: BaseAppBackend & BackendFeatures.Mesh3DViews>(
        _ backend: Backend,
        widget: Any,
        environment: EnvironmentValues
    ) {
        let onFrame = self.onFrame
        let typedWidget = widget as! Backend.Widget
        backend.updateMesh3DView(
            typedWidget,
            scene: scene,
            onFrame: { info in onFrame?(info) },
            environment: environment
        )

        // Rebound on every commit rather than once. The widget a backend hands
        // back is not promised to be the same object across updates, and a
        // closure holding a stale one would read pixels from a view that is no
        // longer on screen -- which returns an image, not an error.
        // 每次 commit 都重新綁定,而不是只綁一次。backend 交回的那個 widget,並不保證在多次更新之間
        // 是同一個物件;而一個抓著舊 widget 的 closure,會從一個已經不在畫面上的 view 讀出像素
        // ——那會回傳一張影像,不是一個錯誤。
        if let snapshotter {
            if let snapshotBackend = backend as? any BaseAppBackend & BackendFeatures
                .WidgetSnapshots
            {
                bind(snapshotter, to: snapshotBackend, widget: typedWidget)
            } else {
                snapshotter.bind(nil)
            }
        }
    }

    private func bind<Backend: BaseAppBackend & BackendFeatures.WidgetSnapshots>(
        _ snapshotter: Mesh3DSnapshotter,
        to backend: Backend,
        widget: Any
    ) {
        let typed = widget as! Backend.Widget
        snapshotter.bind { backend.snapshotWidget(typed) }
    }
}

/// One report per backend, because a scene is committed every frame.
/// 每個 backend 只回報一次,因為場景是每一幀都會 commit 的。
enum Mesh3DDegradation {
    nonisolated(unsafe) private static var reported: Set<String> = []

    static func reportOnce(backend: String) {
        guard !reported.contains(backend) else { return }
        reported.insert(backend)
        logger.warning(
            """
            layout warning (the app keeps running and the view is still laid out): \
            \(backend) does not implement BackendFeatures.Mesh3DViews, so Mesh3DView \
            draws an empty box of the size the layout gave it. Nothing in the scene \
            is shown -- not the meshes, not the background colour. What to change: \
            implement the two methods of that protocol on this backend; M10 in \
            queue.md and testapp/plan/plan-3D.md carry the shape and the reasons, \
            and AppKitBackend is the worked example.
            """
        )
    }
}
