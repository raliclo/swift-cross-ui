# 3DViewBox: a 3D view with camera control, on every backend

A view that draws a 3D scene and lets the pointer move the **camera** around it,
with the same vocabulary on every platform.

一個繪製 3D 場景、並讓指標繞著它移動**攝影機**的 view，且在每個平台上使用同一套詞彙。

## Status

**Design only. Nothing here is implemented, and nothing here is measured.**
Written 2026-09-01 from a naming discussion; every capability claim below is
either cited from an existing measurement in this repository or marked as an
assumption. Do not read the backend table as a report.

**僅為設計。此處沒有任何一項已實作，也沒有任何一項經過量測。** 2026-09-01 依一次命名討論寫成；
下方每一項能力主張，若非引用本 repository 中既有的量測，即已標示為假設。**請勿**把 backend 表格
當成實測報告。

## The vocabulary, and why it is worth pinning first

These are the established names. Using them means a reader who knows Blender,
three.js or Autodesk already knows what the API does, and it stops the same
behaviour being re-invented under three names inside this project.

以下是既有的名稱。採用它們，意味著熟悉 Blender、three.js 或 Autodesk 的讀者一看就知道這個 API
在做什麼，也能避免同一個行為在本專案內被用三個名字重新發明一次。

| what it is / 指的東西 | name / 名稱 |
|---|---|
| dragging to swing the view around an object / 拖曳讓視角繞著物體轉 | **orbit** — Blender calls the operation Orbit View |
| Blender's two rotation models / Blender 的兩種轉法 | **turntable** (default, the world's up axis stays fixed) and **trackball** (free tumbling) |
| the classic "drag on a virtual sphere" algorithm / 「在虛擬球面上拖曳」的經典演算法 | **arcball** (Shoemake, 1992), also called a virtual trackball |
| the component a library gives you / 程式庫裡那個元件 | **orbit controls** / camera controller — three.js names it `OrbitControls` |
| the little axis indicator in the corner / 角落那個小座標軸 | Blender calls it a **navigation gizmo**; the cube form is Autodesk's **ViewCube** |

**Turntable and trackball are not a preference, they are different behaviour**,
and the distinction is the reason to name them rather than ship "rotate". Under
turntable the horizon stays level, because yaw is applied about a fixed world up
axis; a user can drag for a minute and the model is still the right way up.
Under trackball there is no preferred up, so the object tumbles freely and can
end upside down. Blender defaults to turntable for that reason. **Arcball is an
implementation of trackball**, not a third option: it maps the pointer onto a
sphere and converts drags into rotations of it.

**turntable 與 trackball 不是偏好設定，而是兩種不同的行為**，而這正是應該把它們命名出來、而非只
提供一個「rotate」的理由。turntable 之下地平線保持水平，因為 yaw 是繞著固定的世界上方向套用的；
使用者拖曳一分鐘之後，模型仍然是正的。trackball 之下沒有優先的上方向，因此物體會自由翻滾，可能
變成上下顛倒。Blender 之所以預設 turntable，理由即在此。**arcball 是 trackball 的一種實作**，
而非第三個選項：它把指標映射到一個球面上，再將拖曳換算成該球面的旋轉。

## Shape

Three separable pieces. They are listed separately because each can ship and be
judged on its own, and because the third one is a normal 2D widget that happens
to be about 3D.

三個可分離的部分。分開列出，是因為每一部分都能各自交付與評斷，也因為第三項其實是一個「剛好和 3D
有關」的普通 2D widget。

1. **The view.** Somewhere to draw a 3D scene, sized and placed by the existing
   layout system like any other view.
2. **The camera controller** — the `OrbitControls` equivalent. Turns pointer
   drags into camera movement: orbit, plus the pan and dolly/zoom that always
   travel with it. Takes a mode, `.turntable` (default) or `.trackball`.
3. **The navigation gizmo.** The corner axis indicator, and optionally a
   ViewCube whose faces are clickable to snap to an axis. This one needs no 3D
   pipeline at all — it is a small widget drawing lines and labels, driven by
   the same camera orientation.

## What each backend would have to draw with, and what is known

**This is the part to distrust.** Only the GTK rows are measured, and they were
measured for a different reason.

**這是最該存疑的部分。** 只有 GTK 那幾列是量測過的，而且當初量測是為了另一個目的。

| backend | plausible surface | evidence |
|---|---|---|
| GtkBackend, Windows | needs `GskGLRenderer`, which needs Direct Composition | measured: without DComp, GTK on Windows realizes `GskCairoRenderer`, which cannot even draw a transform node — see `bugs/Gtk4-bugs.md` §1 and §3 |
| GtkBackend, WSL | `GskVulkanRenderer`, on lavapipe | measured: hardware Vulkan is absent on this machine, so anything drawn is drawn by the CPU — `bugs/Gtk4-bugs.md` §2 |
| GtkBackend, Linux native | `GskGLRenderer` on real hardware | **assumption**, not measured here |
| WinUIBackend | D3D11 through a composition swapchain | the mechanism already exists in this repository: `Sources/WinUIBackend/D3D11VideoInterop.swift` uses `CreateSwapChainForComposition` for P6 |
| AppKitBackend / UIKitBackend | Metal, presumably `MTKView` or `CAMetalLayer` | **assumption** — out of scope on this machine, and needs a Mac |

Two consequences follow from the measured rows and should shape the design
rather than be discovered during it:

- **On Windows, GTK cannot do this today at all.** The renderer that could is
  unreachable without Direct Composition, and Direct Composition is off by
  default. That is not a 3D problem; it is the same blocker as the hotpink
  transform, and it is tracked as its own decision.
- **On WSL, it would run but on the CPU.** A scene that renders is not a scene
  that renders acceptably, and any frame-rate number taken there measures
  lavapipe.

## Declining, not crashing

Whatever protocol this becomes, a backend that cannot draw 3D must **conform and
decline**, not omit the conformance. `@CastBackend` turns a *missing*
conformance into `fatalError`, so refusing the protocol aborts every application
that mentions a 3DViewBox rather than showing it a placeholder. GtkBackend's
`setGeometricEffect` is the existing example of that shape.

And declining must say so once, through `debugLogOnce`. The lesson this project
keeps paying for is that a silent no-op is indistinguishable from a bug in the
caller — and here the failure would be a blank rectangle, which looks exactly
like a scene that failed to load.

無論這最後成為什麼 protocol，畫不出 3D 的 backend 都必須**遵從並拒絕**，而不是不遵從。
`@CastBackend` 會把**缺少**的遵從轉成 `fatalError`，因此拒絕遵從等於讓每一個提到 3DViewBox 的
應用程式直接中止，而不是看到一個佔位圖。GtkBackend 的 `setGeometricEffect` 就是這個形狀的既有範例。

而拒絕必須透過 `debugLogOnce` 說一次。本專案一再付出代價的教訓是：無聲的 no-op 與「呼叫端有 bug」
無從分辨——而在此處，失敗的樣子會是一塊空白矩形，那看起來正好就像「場景載入失敗」。

## Open questions

- **Where does the scene come from?** A retained scene graph owned by the
  framework, or a draw callback the application fills each frame? The second is
  far less API and puts the choice of renderer with the application; the first
  is what a declarative framework would normally offer. This decision precedes
  everything else and nothing below is stable until it is made.
- **Does the gizmo belong here at all?** It needs no 3D pipeline. Shipping it as
  an ordinary view that takes an orientation would make it usable on every
  backend immediately, including the ones that cannot draw a scene.
- **What does a test look like?** A rotating scene has no stable screenshot.
  Fixing the camera to named orientations and comparing those is one answer;
  asserting on the camera matrix rather than on pixels is another, and does not
  need the scene to render at all.
- **Does this belong in SwiftCrossUI or beside it?** Every other backend feature
  here wraps something the platform toolkit already provides. A 3D view does not:
  GTK, WinUI and AppKit would each be given a surface and left to do the work,
  which is a different kind of dependency from the rest of the project.

- **場景從哪裡來？** 由框架持有的保留式 scene graph，還是由應用程式每一格填入的繪製回呼？後者的
  API 少得多，且把繪製器的選擇留給應用程式；前者才是宣告式框架通常會提供的東西。這個決定先於其他
  一切，在它做出之前，以下各項都不穩定。
- **gizmo 到底屬不屬於這裡？** 它完全不需要 3D 管線。把它做成一個「接受一個方位」的普通 view，
  就能立刻在每個 backend 上使用——包括那些畫不出場景的 backend。
- **測試長什麼樣子？** 旋轉中的場景沒有穩定的截圖。把攝影機固定到幾個具名方位再比對，是一種答案；
  斷言攝影機矩陣而非像素，是另一種，而且完全不需要場景真的被繪製出來。
- **這該放進 SwiftCrossUI，還是放在它旁邊？** 此處其他每一個 backend feature，包裝的都是平台
  toolkit 已經提供的東西。3D view 不是：GTK、WinUI 與 AppKit 各自只會拿到一個 surface，其餘全得
  自己做——那是與本專案其他部分性質不同的一種依賴。
