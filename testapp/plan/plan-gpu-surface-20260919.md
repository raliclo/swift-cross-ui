# A GPU surface, measured against three.js — plan, 2026-09-19 (Mac)

Published before any code is written, which is the rule mistakes entry 12 exists
to enforce. What follows is what this tree has today, what `three.js` has, and
the smallest thing that would close the distance rather than a promise to close
all of it.

先公開形狀,再動手——這是 mistakes 第 12 條存在的理由。以下是這棵樹今天有什麼、`three.js` 有什麼,
以及「能真正縮短距離的最小一步」,而不是一個「全部補完」的承諾。

Sources read: `/Volumes/LinuxCS/render/three.js` (submodule at `ea56c2f4`, version
0.185.0), `/Volumes/LinuxCS/render/wiki/three.js/README.md`,
`/Volumes/LinuxCS/render/metal-tools` and its wiki note, and this repository's
`Sources/SwiftCrossUI/Backend/BackendFeatures/`.

---

## 0. CORRECTION, same day, before any code was written

**Section 1's headline claim — "there is no view in this framework that hands an
application a surface to draw on" — is false, and the thing that disproves it is
an application built on this fork.**

`/Volumes/Windows/proj_Win/SoftPCB/SoftPCB-UI` renders a 3D board view with
Metal **today**: `Sources/SoftPCB-UI/Render/MetalBoxRenderer.swift` is an
`MTKView` behind `NSViewRepresentable`, with its own shader source, and
`MeshBenchmark.swift` measures the same shaders. Its `Package.swift` takes
`AppKitBackend` as a macOS-only dependency to do it.

And it is not only AppKit. Every backend already ships an escape hatch:

| Backend | File |
| --- | --- |
| AppKit | `NSViewRepresentable.swift` |
| UIKit | `UIViewRepresentable.swift`, `UIViewControllerRepresentable.swift` |
| Android | `AndroidViewRepresentable.swift`, `AndroidxFragmentRepresentable.swift` |
| GTK | `GtkWidgetRepresentable.swift` |
| WinUI | `WinUIElementRepresentable.swift` |

So the question is not "can an app draw on the GPU" — it can, on all five — but
**what it costs**: an app must write one view per backend and import each
backend to do it, which is what SoftPCB's manifest shows.

**第 1 節的那句主張——「這個框架裡沒有任何一種 view 會把可以自己畫的表面交給 app」——是錯的,
而推翻它的,正是一支建在這個 fork 上的 app。** SoftPCB-UI 今天就用 Metal 畫 3D 板:
`MetalBoxRenderer.swift` 是放在 `NSViewRepresentable` 後面的 `MTKView`。而且不只 AppKit——
五個 backend 各自都有逃生門(見上表)。因此問題不是「app 能不能用 GPU 畫」(五個都能),
而是**代價**:app 得為每個 backend 各寫一個 view、各 import 一個 backend。

### What that makes the real gap

1. **Portability.** Five hatches, no shared shape. An app wanting one 3D view on
   five platforms writes five views and takes five backend dependencies.
2. **The input and output a 3D view needs**, which SoftPCB listed against this
   source in its own `plan.md` §10.7 as nine items. Re-checked here on
   2026-09-19, four of the nine have closed since they wrote it:

   | # | Their gap | Today |
   | --- | --- | --- |
   | 1 | Drag to rotate: "no DragGesture" | **closed** — `BackendFeatures.DragGestures`, driven on five backends (P65) |
   | 2 | Scroll to zoom | **open** — no scroll API; the `scrollWheel` in the tree is a list workaround |
   | 3 | Pinch to zoom: "no MagnificationGesture" | **closed** — `MagnifyGestures` and `RotateGestures`, driven on five (P65) |
   | 4 | Modifier keys / key events | **partly** — `keyboardShortcut` (#121) on five backends; no raw key events |
   | 5 | Focus: "no focus API at all" | **closed** — `FocusableViews.focus(_:)` (#122, P70) |
   | 6 | Cursor while dragging | **open** — `NSCursor` appears nowhere |
   | 7 | Context menu | **open** — `Menu` is menu-bar bound |
   | 8 | Per-frame timing | **closed** — `FrameClocks` |
   | 9 | Export the render as an image | **open** — no snapshot API |

3. **Their second "real obstacle", which is this tree's own problem**: nothing
   can test what an embedded native view drew. `InspectionModifiers` inspects
   SwiftCrossUI's widget tree, not the pixels an `MTKView` produced. **Item 9
   answers item 3**: a snapshot API is both the export an application asks for
   and the hook a test needs, which is why it goes first.

### The direction, decided by the user on 2026-09-19

> "raise the Metal renderer in protocol level and then move most Metal renderer
> in macOS and iOS backend first, we will do the rest platforms later"

So not a handle to a surface, and not snapshot-first: **the renderer itself is
lifted into the framework.** An application describes a mesh and a camera; the
backend draws it. That is the same relationship `Paths` already has for 2D, and
it is what stops the next application from writing SoftPCB's `MTKView` and
shaders a second time.

**方向由使用者於 2026-09-19 定下:把 renderer 升到協定層,Metal 實作先進 macOS 與 iOS 的 backend,
其餘平台後補。** 因此不是「交出一塊表面」,也不是「先做快照」:**是把 renderer 本身放進框架**。
app 描述一個 mesh 與一台相機,由 backend 畫出來——那正是 `Paths` 在 2D 上已有的關係,
也是讓下一支 app 不必再寫一次 SoftPCB 那份 `MTKView` 與著色器的方式。

#### The shape

In `SwiftCrossUI`, backend-agnostic values only — no Metal type crosses this line:

```swift
public struct Mesh3DVertex { var position, normal, colour: SIMD3<Float> }
public struct Mesh3D       { var vertices: [Mesh3DVertex]; var indices: [UInt32] }
public struct Mesh3DCamera { var eye, target, up: SIMD3<Float>; var fieldOfView, near, far: Float }
public struct Mesh3DScene  { var meshes: [Mesh3D]; var camera: Mesh3DCamera
                             var background: Color; var lightDirection: SIMD3<Float> }

extension BackendFeatures {
    @MainActor public protocol Mesh3DViews<Widget>: Core {
        func createMesh3DView() -> Widget
        func updateMesh3DView(_ view: Widget, scene: Mesh3DScene, environment: EnvironmentValues)
    }
}
```

Conformance-checked, like `TableSelection` and `PopoverArrowEdges`: a backend
that has not implemented it yet keeps building and the app's own readout says
`mesh view supported: NO`.

#### Where the Metal lives

One new target, `SwiftCrossUIMetal`, depended on by **both** AppKitBackend and
UIKitBackend. `MTKView` is the same class from MetalKit on macOS and iOS, so the
renderer, the shaders and the scene-to-buffer mapping are written once. Writing
them twice is how the two backends end up disagreeing about what a mesh looks
like, and this tree has spent this week fixing exactly that kind of divergence
in popovers and accessibility.

Metal 實作放在一個新 target `SwiftCrossUIMetal`,由 AppKitBackend 與 UIKitBackend **共同**依賴。
`MTKView` 在 macOS 與 iOS 上是 MetalKit 的同一個類別,因此 renderer、著色器與「scene 轉 buffer」只寫一次。
寫兩次正是兩個 backend 對「一個 mesh 該長什麼樣」各說各話的起點——而本週這棵樹才剛在 popover 與
accessibility 上修完同一類分歧。

#### Judged by

**P72**: a cube, `FrameClocks` turning it, a readout naming the backend, the
drawable size in pixels and the frame count. Two captures a second apart must
show the count advanced **and** the cube at a different angle. One picture of a
cube proves the pipeline compiles and nothing about it running — the same
distinction M9 turned on.

#### Then, in order

1. AppKit — the renderer, and P72 driven on macOS.
2. UIKit — the same target, P72 driven on the simulator.
3. Android (mine), GTK and WinUI (Windows side) — later, by the user's decision
   above. The protocol is conformance-checked so they stay green meanwhile.
4. The five input/output gaps from the table above (scroll, raw keys, cursor,
   context menu, snapshot) as separate work, snapshot first, because it is also
   the only way a test can judge what was drawn.

---

## 1. What is actually missing (as first written, kept for the trail)

`three.js` is a scene graph plus a renderer: `Scene`, `Object3D`, `Mesh`,
`BufferGeometry`, materials, textures, `PerspectiveCamera`, lights, an animation
system, a raycaster, and WebGL/WebGPU backends behind them. Addons add loaders
(glTF and friends), controls and post-processing.

SwiftCrossUI has none of that, and the gap is not one feature:

| three.js | SwiftCrossUI today |
| --- | --- |
| `WebGLRenderer` / `WebGPURenderer` — a drawing surface the app owns | **nothing**: every view is a native widget the backend draws |
| `Scene` / `Object3D` / `Mesh` / `Group` | nothing |
| `BufferGeometry`, `BufferAttribute` | nothing |
| materials, textures, lights | `Gradients`, `VisualEffects`, `Images` — 2D, backend-drawn |
| `PerspectiveCamera`, `Matrix4`, `Quaternion` | `GeometricEffects` applies a `CATransform3D` to a 2D widget |
| animation loop | `FrameClocks.startFrameClock(handler:)` — this one exists |
| raycasting / hit testing in 3D | `HitTesting` — 2D, widget-level |
| `GPU` selection | `GraphicsAdapters` — this one exists, and is only about which GPU draws the UI |

**The one thing everything else waits on is the first row.** There is no view in
this framework that hands an application a surface to draw on. `Paths` is the
closest thing and it is the opposite shape: the app describes a path, the
backend draws it with its own 2D engine.

**除了第一列之外,其餘每一列都在等它。** 這個框架裡沒有任何一種 view 會把「一塊可以自己畫的表面」
交給應用程式。`Paths` 是最接近的東西,而它的形狀恰好相反:app 描述一條路徑,由 backend 用它自己的
2D 引擎畫出來。

### The evidence that this is the missing piece, not a wish

Two backends have already built private versions of it because they had to:

- `Sources/WinUIBackend/D3D11VideoInterop.swift` — D3D11 texture interop so
  video frames reach the screen without a CPU round trip.
- `Sources/Gtk/Widgets/NV12GLView.swift` — a `GtkGLArea` doing the same for GTK.

And P6, the video app, still goes the long way round on Apple: it decodes to an
`ImageFormats.Image` and hands SwiftCrossUI an `Image` **per frame**
(`testapp/P6.swift:966`). That is a CPU upload per frame because there is no
surface to put a texture on.

有兩個 backend 已經各自私下造過這個東西,因為他們不得不;而 Apple 這一側的 P6 仍然每一幀都走
「解碼成 `Image` 再交給框架」的長路——那是每幀一次 CPU 上傳,只因為沒有一塊可以放 texture 的表面。

---

## 2. What NOT to build

A port of three.js's scene graph. Writing `Scene`/`Mesh`/`Material` in Swift is
weeks of work whose first honest capture is still a triangle, and it would have
to be reimplemented per backend or bring a renderer of its own. This plan does
not propose it, and deliberately leaves the question open: with a surface in
place, an application can use SceneKit, RealityKit, a Metal renderer of its own,
or a future SwiftCrossUI layer, and we will know which by watching what people
reach for.

不做的事:把 three.js 的 scene graph 移植過來。用 Swift 寫 `Scene`/`Mesh`/`Material` 是好幾週的工作,
而它第一張誠實的擷圖仍然只是一個三角形;何況那還得逐 backend 重做、或自帶一個 renderer。本計畫不提議它,
並刻意把問題留著:有了表面之後,app 可以用 SceneKit、RealityKit、自己的 Metal renderer,或未來的
SwiftCrossUI 層——而我們會從「人們實際伸手去拿什麼」看出答案。

---

## 3. The shape proposed

One new conformance-checked protocol, in the family the others already use:

```swift
extension BackendFeatures {
    /// A widget whose contents the application draws on the GPU.
    @MainActor
    public protocol GPUSurfaces<Widget>: Core {
        /// A view backed by a native GPU surface, sized by the layout system.
        func createGPUSurface() -> Widget

        /// The surface's drawable size in PIXELS and its scale, which is not
        /// the widget's size in points and is the number a renderer needs.
        func gpuSurfaceDrawableSize(_ surface: Widget) -> (size: SIMD2<Int>, scale: Double)

        /// Called when the surface is ready to be drawn into and whenever it is
        /// resized; the handle is the platform object a renderer binds to.
        func setGPUSurfaceHandler(
            _ surface: Widget,
            to handler: @escaping @MainActor (GPUSurfaceHandle) -> Void
        )
    }
}
```

`GPUSurfaceHandle` is an enum with one case per platform object —
`.caMetalLayer(CAMetalLayer)`, `.glArea(OpaquePointer)`, `.androidSurface(...)`,
`.swapChainPanel(...)` — so an application matches on the one it knows and the
type system says which platforms it has handled. **No lowest common denominator
API**: pretending a single abstraction covers Metal, GL and D3D is how a
framework ends up shipping a renderer nobody asked for.

`GPUSurfaceHandle` 是一個 enum,每個平台物件一個 case,因此 app 以 pattern match 處理它認得的那一個,
而型別系統會說出它涵蓋了哪些平台。**刻意不做最小公約數 API**:假裝單一抽象層能同時覆蓋 Metal、GL 與 D3D,
正是一個框架最後出貨了一個沒人要的 renderer 的原因。

Driving: the existing `FrameClocks` already provides the per-frame callback, so
this protocol adds no timer of its own.

### Why conformance-checked rather than required

Because the rule in `CLAUDE.md` is about features being *implemented* on the five
shipped backends, and this one genuinely can be on all five —
`CAMetalLayer` (AppKit, UIKit), `GtkGLArea` (GTK), `SurfaceView` (Android),
`SwapChainPanel` (WinUI) — but not all five by me. Conformance-checked means the
two I cannot compile here keep building, and `P72` reads
`gpu surface supported: NO` on them until they land, which is the same signal
`#109` used.

---

## 4. First slice, and how it will be judged

1. The protocol above, plus a `GPUSurface` view in SwiftCrossUI.
2. `AppKitBackend` and `UIKitBackend` implementations over `CAMetalLayer`.
3. **`P72`**, a new test app: one surface, a rotating triangle drawn by a small
   Metal renderer in the app itself, a readout line naming the backend, the
   drawable size in pixels and the frame count, and `gpu surface supported:`.
4. Action files for macOS, iOS and Android, and captures from all three.

**What counts as done**: the readout's frame count advances between two captures
taken a second apart, and the triangle is at a different angle in each. A single
capture of a triangle proves the surface exists; it does not prove anything is
being driven, which is the same distinction M9's gesture work turned on.

**判定完成的條件**:相隔一秒的兩張擷圖,其讀數的 frame count 要前進,而三角形要在不同角度。
單獨一張三角形的擷圖只證明表面存在,不證明有東西在驅動它——那正是 M9 手勢那件事上的同一個分野。

Android and the two Windows backends are named here as the rest of the work, not
skipped: Android is mine and comes after Apple; GTK and WinUI are the Windows
side's, and the handle cases for them are in the enum from the first commit so
that adding them is an implementation rather than a protocol change.

---

## 5. What `metal-tools` is and is not for

`/Volumes/LinuxCS/render/metal-tools` is a Swift package wrapping Metal
workflows — `MTLContext`, compute kernels for image processing, a lines and text
renderer. It is Apple-only by design, which makes it a poor dependency for a
cross-platform framework, and P72's renderer is a hundred lines of Metal that
does not need it. It is worth reading for the `MTLContext` shape and worth
mentioning to an application author who wants more than a triangle; it is not
proposed as a dependency here.

`metal-tools` 按設計就是 Apple-only,因此不適合成為一個跨平台框架的相依項;而 P72 的 renderer 是一百行
Metal、用不到它。它值得一讀(`MTLContext` 的形狀)、也值得推薦給「想要的不只是一個三角形」的 app 作者;
但此處不提議把它列為相依。

---

## 6. Open question for the Windows side

Does `SwapChainPanel` inside WinUI's XAML island behave with the
single-threaded apartment startup that landed on 2026-09-17? If it does not, the
WinUI case of the handle enum may need to be a composition surface instead. That
is a question, not an assumption: I cannot build WinUI here.

給 Windows 那邊的一個問題:在 2026-09-17 落地的單執行緒 apartment 啟動之下,XAML island 裡的
`SwapChainPanel` 行為正常嗎?若否,handle enum 的 WinUI case 可能要改成 composition surface。
這是問題,不是假設——我在此處建不了 WinUI。
