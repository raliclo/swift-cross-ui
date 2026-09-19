import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

// P72: does the backend actually RENDER a 3D scene, or only accept one? (M10)
//
// The number is checked: `ls testapp` gives P0..P71, and nothing under
// testapp/plan or matrix_coverage mentions P72.
//
// **A still of a cube proves the pipeline compiled. It does not prove the
// pipeline runs.** That distinction has cost this tree real time twice this
// month -- P64 exists because a `FrameClocks` conformance that had never been
// started would have looked exactly like a working one, and on 2026-09-18 a
// missing popover arrow turned out to be a photograph of a stale APK. So this
// app puts a FRAME COUNT on screen, driven by the renderer itself rather than
// by the code that asks it to draw, and the acceptance criterion is two
// captures a second apart: the count must have advanced AND the cube must be at
// a different angle. A count that moves with a frozen cube is a renderer
// drawing the same frame; a cube that moves with a frozen count is a readout
// wired to the wrong thing.
//
// **What it does NOT assert.** Nothing here checks that the cube is beautiful,
// or that the shading matches any other backend's. Colours are per vertex and
// the light is one direction, which is all `Mesh3DScene` carries; a test that
// compared pixels between AppKit and UIKit would be asserting that two Metal
// drivers round identically, which they need not.
//
// P72:backend 真的**算繪**出一個 3D 場景了嗎,還是只是收下了它?(M10)
//
// 編號是查過的:`ls testapp` 給出 P0..P71,而 testapp/plan 與 matrix_coverage 底下都沒有提到 P72。
//
// **一張立方體的靜止畫面,證明的是 pipeline 編得過,不是 pipeline 在跑。** 這個分野本月已經讓這棵樹
// 付出兩次實際代價——P64 之所以存在,是因為一個從未被啟動過的 `FrameClocks` conformance 看起來會與
// 一個能用的一模一樣;而 2026-09-18 那個「不見的 popover 箭頭」,結果是一張舊 APK 的照片。因此本 app
// 把一個**幀計數**放上畫面,而且是由 renderer 自己驅動、不是由「要求它畫」的那段程式驅動;驗收標準是
// 相隔一秒的兩張擷圖:計數必須前進,**而且**立方體必須在不同角度。計數在動、立方體凍住,那是一個
// 反覆畫同一幀的 renderer;立方體在動、計數凍住,那是一個接錯東西的讀數。
//
// **它不斷言什麼。** 此處沒有任何東西檢查那個立方體好不好看,或它的明暗是否與別的 backend 一致。
// 顏色是逐頂點的、光只有一個方向——那就是 `Mesh3DScene` 所承載的全部;一個比對 AppKit 與 UIKit 像素的
// 測試,斷言的會是「兩個 Metal 驅動的捨入方式相同」,而它們沒有義務相同。

enum P72Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P72] \(message)")

        guard let data = "P72 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? {
                    #if os(iOS) || os(tvOS)
                        return NSHomeDirectory() + "/Documents"
                    #else
                        return FileManager.default.currentDirectoryPath
                    #endif
                }()
        let url = URL(fileURLWithPath: directory)
            .appendingPathComponent("p72-debug-events.log")
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P72 ready, the clock starts now")
    }
}

/// A unit cube, as twenty-four vertices rather than eight.
///
/// **Eight would be wrong, and wrong in a way that still draws a cube.** A
/// corner is shared by three faces pointing in three directions, so a single
/// vertex there can carry only one normal; the shading then interpolates across
/// the edges and the cube reads as a lumpy sphere. Four vertices per face, each
/// with that face's normal, is what makes the edges edges -- and edges are what
/// a capture needs in order to show that the thing turned.
///
/// 一個單位立方體,以二十四個頂點、而不是八個構成。
///
/// **八個是錯的,而且錯得依然畫得出一個立方體。** 一個角被三個朝向不同方向的面共用,因此那裡的單一
/// 頂點只能帶一個法線;明暗接著會跨過稜線內插,而那個立方體看起來會像一顆坑坑疤疤的球。每個面四個
/// 頂點、各帶該面自己的法線,才是讓稜線成為稜線的做法——而擷圖需要稜線,才顯示得出那東西轉過。
@MainActor
enum P72Cube {
    static let mesh: Mesh3D = {
        let half: Float = 0.8

        // Six faces, six colours, deliberately not magenta: the composed
        // comparison images in this tree use a gutter colour picked by measuring
        // what the apps themselves render, and one more app rendering magenta
        // makes that harder for everyone.
        // 六個面、六種顏色,刻意不用洋紅:這棵樹的合成比較圖,其分隔色是「量過各 app 自己畫出什麼」
        // 之後挑的,而多一支畫洋紅的 app 只會讓所有人更難挑。
        let faces:
            [(normal: SIMD3<Float>, colour: SIMD3<Float>, corners: [SIMD3<Float>])] = [
                (
                    SIMD3(0, 0, 1),
                    SIMD3(0.90, 0.30, 0.25),
                    [
                        SIMD3(-half, -half, half),
                        SIMD3(half, -half, half),
                        SIMD3(half, half, half),
                        SIMD3(-half, half, half),
                    ]
                ),
                (
                    SIMD3(0, 0, -1),
                    SIMD3(0.20, 0.55, 0.95),
                    [
                        SIMD3(half, -half, -half),
                        SIMD3(-half, -half, -half),
                        SIMD3(-half, half, -half),
                        SIMD3(half, half, -half),
                    ]
                ),
                (
                    SIMD3(1, 0, 0),
                    SIMD3(0.98, 0.72, 0.20),
                    [
                        SIMD3(half, -half, half),
                        SIMD3(half, -half, -half),
                        SIMD3(half, half, -half),
                        SIMD3(half, half, half),
                    ]
                ),
                (
                    SIMD3(-1, 0, 0),
                    SIMD3(0.30, 0.78, 0.45),
                    [
                        SIMD3(-half, -half, -half),
                        SIMD3(-half, -half, half),
                        SIMD3(-half, half, half),
                        SIMD3(-half, half, -half),
                    ]
                ),
                (
                    SIMD3(0, 1, 0),
                    SIMD3(0.92, 0.92, 0.95),
                    [
                        SIMD3(-half, half, half),
                        SIMD3(half, half, half),
                        SIMD3(half, half, -half),
                        SIMD3(-half, half, -half),
                    ]
                ),
                (
                    SIMD3(0, -1, 0),
                    SIMD3(0.45, 0.40, 0.70),
                    [
                        SIMD3(-half, -half, -half),
                        SIMD3(half, -half, -half),
                        SIMD3(half, -half, half),
                        SIMD3(-half, -half, half),
                    ]
                ),
            ]

        var vertices: [Mesh3DVertex] = []
        var indices: [UInt32] = []
        for face in faces {
            let base = UInt32(vertices.count)
            for corner in face.corners {
                vertices.append(
                    Mesh3DVertex(position: corner, normal: face.normal, colour: face.colour)
                )
            }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return Mesh3D(vertices: vertices, indices: indices)
    }()
}

@MainActor
final class P72Model: SwiftCrossUI.ObservableObject {
    /// One model for the process, for the reason P64 records at length: a
    /// `@ObservedObject var model = P72Model()` is rebuilt on every update, and
    /// the clock would be started on an object that is then dropped.
    /// 一個行程一個 model,理由 P64 已經詳述:`@ObservedObject var model = P72Model()` 在每次更新時都會
    /// 被重建,而時鐘會被啟動在一個隨即被丟棄的物件上。
    static let shared = P72Model()

    @SwiftCrossUI.Published var angle: Double = 0
    @SwiftCrossUI.Published var ticks = 0
    @SwiftCrossUI.Published var renderer = "no frame drawn yet"
    @SwiftCrossUI.Published var drawablePixels = "no frame drawn yet"
    @SwiftCrossUI.Published var framesDrawn = 0
    @SwiftCrossUI.Published var clockState = "not started"

    /// Whether the cube spins in the XY plane. The camera keeps orbiting either
    /// way.
    ///
    /// **Two motions with one switch would have told you nothing.** Stopping the
    /// clock freezes both, so a still of a frozen cube cannot say which of the
    /// two was drawing it. With this off and the clock running, the transform is
    /// constant and the camera is not -- so anything still moving is the camera,
    /// and anything that stopped was the transform. That is the only way, from a
    /// capture, to tell that `Mesh3DTransform` is what turned the cube rather
    /// than the camera going round it.
    ///
    /// 立方體是否在 XY 平面上自轉。無論如何,相機都會繼續公轉。
    ///
    /// **兩種運動只給一個開關,什麼也說明不了。** 停掉時鐘會讓兩者一起凍住,因此一張凍住的立方體靜止圖
    /// 無法說出是哪一個在畫它。把這個關掉、時鐘繼續跑,變換就是定值而相機不是——於是還在動的就是相機,
    /// 停下來的就是變換。那是「單憑一張擷圖,判斷出讓立方體轉起來的是 `Mesh3DTransform` 而不是繞著它
    /// 跑的相機」的唯一辦法。
    @SwiftCrossUI.Published var spinning = true

    /// The two numbers the action file asserts on.
    ///
    /// **Together they ask whether the view draws only when it is asked to.**
    /// The readout deliberately does not publish the frame count from the
    /// render callback (see `latestFrame` below), but a view that re-drew itself
    /// on a timer of its own would defeat that: the picture would keep moving
    /// with the clock stopped, and every "the count advanced" result in this app
    /// would stop meaning anything about the clock. So: stop the clock, wait,
    /// then read the count again. `MTKView` defaults to 60 Hz of its own
    /// (`isPaused = false`), and `Mesh3DMetalView` turns that off -- if that line
    /// were ever deleted, the two numbers would be about ninety apart and
    /// nothing else here would notice.
    ///
    /// 動作檔所斷言的兩個數字。
    ///
    /// **它們合起來問的是:這個 view 是否只在被要求時才繪製。** 那個讀數刻意不從算繪回呼發布幀計數
    /// (見下方 `latestFrame`),但一個「自己用計時器重畫」的 view 會使那個設計失效:時鐘停了,畫面
    /// 仍在動,而本 app 裡每一個「計數有前進」的結果就不再對那個時鐘說明任何事。因此:停掉時鐘、等待、
    /// 再讀一次計數。`MTKView` 預設自帶 60 Hz(`isPaused = false`),而 `Mesh3DMetalView` 把它關掉了
    /// ——若那一行哪天被刪掉,這兩個數字會差上大約九十,而此處其他任何東西都不會發覺。
    @SwiftCrossUI.Published var framesAtStop = -1
    @SwiftCrossUI.Published var framesAtCheck = -1

    /// What the last `.glb` export did, as one line for the readout.
    /// 上一次 `.glb` 匯出做了什麼,以一行呈現在讀數區。
    @SwiftCrossUI.Published var exportResult = "not exported"

    /// What the last snapshot found.
    /// 上一次快照發現了什麼。
    @SwiftCrossUI.Published var snapshotResult = "not taken"

    /// The handle the view fills in so this model can ask it for pixels.
    /// 那個由 view 填上的把手,好讓這個 model 能向它要像素。
    let snapshotter = Mesh3DSnapshotter()

    /// The last frame the renderer reported, held UNPUBLISHED on purpose.
    ///
    /// Publishing it straight from the callback closes a loop: a new frame
    /// count changes the state, the state change commits the view, the commit
    /// hands the view a scene, the scene asks for a frame. The app would then
    /// render continuously whether or not the clock was running, and "the count
    /// is going up" would stop meaning anything about the clock. The frame clock
    /// copies this into the published fields once per tick instead.
    ///
    /// renderer 回報的最後一幀,刻意**不**發布。
    ///
    /// 直接從 callback 發布它會閉合成一個迴圈:新的幀計數改變狀態、狀態改變使 view commit、commit 把
    /// 場景交給 view、場景又要求畫一幀。那樣這支 app 會不論時鐘是否在跑都持續算繪,而「計數在上升」
    /// 就不再對那個時鐘說明任何事。改由 frame clock 每跳一次,把它抄進已發布的欄位。
    private var latestFrame: Mesh3DFrameInfo?

    private var started = false

    /// Held so the two buttons can stop and restart the same clock the view
    /// started; `@Environment(\.backend)` is reachable from the view, but the
    /// model is what the buttons call.
    /// 保留下來,好讓那兩個按鈕能停止與重啟「view 所啟動的同一個時鐘」;`@Environment(\.backend)` 在
    /// view 裡取得到,而按鈕呼叫的是這個 model。
    private var clock: (any BackendFeatures.FrameClocks)?

    /// The first timestamp the clock delivered, subtracted from every later one.
    ///
    /// **Not cosmetic: without it the cube rotates in visible steps.**
    /// `FrameClocks` hands out the backend's monotonic clock, which on this Mac
    /// is uptime -- the first reading on 2026-09-19 was 177182 seconds. The
    /// camera takes `Float`, and `Float`'s spacing at 177182 is about 0.0156,
    /// while one frame at 0.6 rad/s advances the angle by 0.01. So roughly every
    /// other frame would round to the same angle and the motion would quantise,
    /// which reads as a stutter and would be blamed on the renderer. Elapsed
    /// time starts at zero and has the precision the arithmetic assumes.
    ///
    /// 時鐘送來的第一個時間戳記,之後每一個都減去它。
    ///
    /// **這不是美觀問題:少了它,那個立方體會以看得見的階梯在轉。** `FrameClocks` 交出的是 backend 的
    /// 單調時鐘,在這台 Mac 上是開機以來的時間——2026-09-19 的第一個讀數是 177182 秒。相機取的是
    /// `Float`,而 `Float` 在 177182 附近的間距約為 0.0156;但以 0.6 rad/s 計,一幀只讓角度前進 0.01。
    /// 於是大約每隔一幀就會捨入到同一個角度,運動因而量化——那看起來像頓挫,而且會被算到 renderer 頭上。
    /// 「經過時間」由零開始,具備這段運算所假設的精度。
    private var firstTimestamp: Double?

    var scene: Mesh3DScene {
        // **Two rotations, and they are two different things on purpose.**
        //
        // The camera orbits about Y, which moves the eye and leaves the cube
        // where it is. The MESH spins in the XY plane -- about Z, so it turns in
        // the plane of the screen -- through `Mesh3DTransform`, which is part of
        // the protocol. The app writes an angle; it does not touch a vertex.
        //
        // **That placement is the whole reason the spin is cheap.** An earlier
        // version of this app rotated the 24 vertices itself and handed the
        // backend a different mesh every frame, which made the renderer
        // re-upload geometry 60 times a second to draw the same cube. Moving the
        // transform into `Mesh3D` means the geometry is uploaded once and the
        // angle travels as a uniform -- and it means Android, GTK and WinUI
        // inherit the same spin rather than each app reimplementing it.
        //
        // The spin is the slower of the two so the motions stay separable by
        // eye. Both are driven by the one `FrameClocks` tick.
        //
        // **兩種旋轉,而它們刻意是兩件不同的事。**
        //
        // 相機繞 Y 軸公轉——那移動的是眼睛,立方體待在原處。而 **mesh** 在 XY 平面上自轉(繞 Z 軸,
        // 因此它在螢幕所在的平面上轉動),經由 `Mesh3DTransform`——那是協定的一部分。這支 app 寫的是
        // 一個角度,它沒有碰任何一個頂點。
        //
        // **那個「放在哪裡」正是這個自轉便宜的全部理由。** 本 app 的前一版是自己旋轉那 24 個頂點、
        // 每一幀交給 backend 一個不同的 mesh,於是 renderer 為了畫同一個立方體、每秒重傳 60 次幾何資料。
        // 把變換移進 `Mesh3D`,代表幾何只上傳一次、角度以 uniform 傳遞——也代表 Android、GTK 與 WinUI
        // 會繼承同一個自轉,而不是每支 app 各自重做一遍。
        //
        // 自轉是兩者中較慢的那一個,好讓兩種運動用肉眼就分得開。兩者都由同一個 `FrameClocks` 跳動驅動。
        let radius: Float = 3.4
        let orbit = Float(angle)
        let spin = spinning ? Float(angle) * 0.45 : 0
        var cube = P72Cube.mesh
        cube.transform = .rotatedInXY(spin)
        return Mesh3DScene(
            meshes: [cube],
            camera: Mesh3DCamera(
                position: SIMD3(radius * sin(orbit), 1.3, radius * cos(orbit)),
                target: SIMD3(0, 0, 0),
                fieldOfView: 45
            ),
            background: Color(red: 0.08, green: 0.09, blue: 0.13)
        )
    }

    func record(_ info: Mesh3DFrameInfo) {
        latestFrame = info
    }

    /// Takes `BaseAppBackend`, which is what `@Environment(\.backend)` holds.
    ///
    /// `AppBackend` is deprecated and `FullAppBackend` is narrower than what the
    /// environment carries, so asking for either makes this a compile error
    /// rather than a cast that fails at run time.
    ///
    /// 取 `BaseAppBackend`,那正是 `@Environment(\.backend)` 所持有的型別。
    ///
    /// `AppBackend` 已被棄用,而 `FullAppBackend` 比 environment 所帶的更窄;要求其中任何一個,
    /// 都會讓這裡變成編譯錯誤,而不是一次在執行期失敗的轉型。
    func start(backend: any BaseAppBackend) {
        guard !started else { return }
        started = true

        guard let clock = backend as? any BackendFeatures.FrameClocks else {
            clockState = "this backend does not conform to FrameClocks -- the cube will not turn"
            P72Diagnostics.write("NO FRAME CLOCK on \(String(describing: type(of: backend)))")
            return
        }
        self.clock = clock
        clockState = "running"
        begin(clock: clock)
    }

    /// Stops the clock and records the count as it stood.
    /// 停掉時鐘,並記下當下的計數。
    func stopAndRecord() {
        guard let clock else {
            clockState = "no clock to stop"
            return
        }
        clock.stopFrameClock()
        clockState = "stopped"
        framesAtStop = latestFrame?.frameCount ?? -1
        framesDrawn = framesAtStop
        P72Diagnostics.write("STOPPED at frame \(framesAtStop)")
    }

    /// Turns the XY spin on or off, leaving the clock and the orbit alone.
    /// 開關 XY 自轉,不動時鐘、也不動公轉。
    func toggleSpin() {
        spinning.toggle()
        P72Diagnostics.write("AUTO SPIN \(spinning ? "on" : "off")")
    }

    /// Writes the scene as it stands to a binary glTF file.
    ///
    /// **Exported as it stands, spin included, and that is the assertion.** The
    /// cube's angle lives in `Mesh3DTransform`, which becomes the node's
    /// rotation quaternion in the file -- so an exporter that dropped the
    /// transform would still write a perfectly valid cube, just an unrotated
    /// one. Pressing this while the cube is visibly turned, and then reading the
    /// angle back out of the file, is what separates those two.
    ///
    /// 把當下的場景寫成一份二進位 glTF 檔。
    ///
    /// **「當下」包含自轉,而那正是斷言本身。** 立方體的角度住在 `Mesh3DTransform` 裡,而它在檔案中會
    /// 變成 node 的旋轉四元數——因此一個把變換丟掉的匯出器,仍然會寫出一個完全合法的立方體,只是沒轉。
    /// 在立方體明顯轉過去的時候按下它,再從檔案裡把角度讀回來,才分得開這兩者。
    func exportGLB() {
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? {
                    #if os(iOS) || os(tvOS)
                        return NSHomeDirectory() + "/Documents"
                    #else
                        return FileManager.default.currentDirectoryPath
                    #endif
                }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p72-scene.glb")
        let data = scene.glbData()
        do {
            try data.write(to: url)
            exportResult = "wrote \(data.count) bytes"
            P72Diagnostics.write("EXPORTED \(data.count) bytes to \(url.path)")
        } catch {
            exportResult = "failed: \(error)"
            P72Diagnostics.write("EXPORT FAILED \(error)")
        }
    }

    /// Reads the mesh view's pixels back and says what is in them.
    ///
    /// **This is the gap SoftPCB `plan.md` §10.7 calls the one with no way out:
    /// "what an `MTKView` drew inside itself is invisible" to the inspection
    /// machinery.** So the assertion is not a screenshot of the window -- the
    /// window capture already exists and shows the app, not the view. It is the
    /// view's own pixels, read off its own texture, and three numbers taken from
    /// them:
    ///
    /// - the size, which must be the drawable size and not the layout size
    /// - the distinct colour count, which is 1 for a view that drew nothing
    /// - the centre pixel, which must be a face colour and not the background
    ///
    /// A blank render passes none of those. A window screenshot passes all three
    /// whatever the view did, because it is a picture of the window.
    ///
    /// 把 mesh view 的像素讀回來,並說出裡面有什麼。
    ///
    /// **這正是 SoftPCB `plan.md` §10.7 稱為「沒有出路」的那個缺口:`MTKView` 內部畫了什麼,對那套
    /// inspection 機制而言是「看不到的」。** 因此這裡的斷言**不是**視窗截圖——視窗截圖本來就有,而它拍到的
    /// 是那支 app、不是那個 view。斷言的是那個 view 自己的像素、從它自己的 texture 讀出來,再從中取三個數字:
    ///
    /// - 尺寸,它必須是 drawable 尺寸、不是版面尺寸
    /// - 相異顏色數,一個什麼都沒畫的 view 會是 1
    /// - 中心像素,它必須是某個面的顏色、不是背景色
    ///
    /// 一張空白的算繪,這三項一項都過不了。而一張視窗截圖,無論那個 view 做了什麼都三項全過——因為它是
    /// 一張視窗的照片。
    func takeSnapshot() {
        guard snapshotter.isAvailable else {
            snapshotResult = "this backend does not implement WidgetSnapshots"
            P72Diagnostics.write("SNAPSHOT UNAVAILABLE -- no WidgetSnapshots conformance")
            return
        }
        guard let shot = snapshotter.snapshot() else {
            snapshotResult = "the backend returned nothing"
            P72Diagnostics.write("SNAPSHOT NIL -- the backend returned no pixels")
            return
        }

        let colours = shot.distinctColourCount()
        let centre = shot.pixel(x: shot.width / 2, y: shot.height / 2)
        let centreText =
            centre.map { "\($0.r),\($0.g),\($0.b)" } ?? "none"
        snapshotResult = "\(shot.width)x\(shot.height) px, \(colours) colours, centre \(centreText)"
        P72Diagnostics.write(
            "SNAPSHOT \(shot.width)x\(shot.height) px, \(colours) distinct colours, "
                + "centre pixel \(centreText)"
        )

        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? {
                    #if os(iOS) || os(tvOS)
                        return NSHomeDirectory() + "/Documents"
                    #else
                        return FileManager.default.currentDirectoryPath
                    #endif
                }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p72-snapshot.png")
        let png = shot.pngData()
        do {
            try png.write(to: url)
            P72Diagnostics.write("SNAPSHOT PNG \(png.count) bytes to \(url.path)")
        } catch {
            P72Diagnostics.write("SNAPSHOT PNG FAILED \(error)")
        }
    }

    /// Reads the count again without touching the clock.
    /// 在不碰那個時鐘的情況下,再讀一次計數。
    func checkAgain() {
        framesAtCheck = latestFrame?.frameCount ?? -1
        framesDrawn = framesAtCheck
        let delta = framesAtCheck - framesAtStop
        // The number, and what it means, without a threshold baked into the app.
        //
        // A few frames are expected: each press commits the view, and a commit
        // hands the view a scene and asks for one frame. How many "a few" is
        // differs per backend and was measured on 2026-09-19 rather than
        // guessed -- AppKit 1, UIKit 3, the extra two being the touch-down and
        // touch-up states a tap puts the button through. The number that means
        // failure is not near either: 1.5 seconds of a self-driving MTKView is
        // about 90.
        //
        // 印出數字與其意義,而不把門檻寫死在 app 裡。
        //
        // 出現幾幀是預期中的:每一次按下都會使 view commit,而一次 commit 會把場景交給 view 並要求一幀。
        // 「幾幀」依 backend 而異,而那是 2026-09-19 量出來的、不是猜的——AppKit 是 1、UIKit 是 3,
        // 多出來的兩幀來自一次點擊讓按鈕經過的 touch-down 與 touch-up 兩個狀態。代表失敗的數字離兩者都很遠:
        // 一個自走的 MTKView,1.5 秒約為 90。
        P72Diagnostics.write(
            "CHECK at frame \(framesAtCheck), \(delta) since the stop "
                + "(a few is right -- each press commits the view, and a commit draws one "
                + "frame; measured 1 on AppKit and 3 on UIKit. ~90 means the view drives itself)"
        )
    }

    private func begin<Clock: BackendFeatures.FrameClocks>(clock: Clock) {
        clock.startFrameClock { [weak self] timestamp in
            guard let self else { return }
            self.ticks += 1
            // 0.6 radians a second: a second between two captures is about 34
            // degrees, which is plainly a different angle and is nowhere near
            // the 90 degrees that would make a cube look unchanged.
            // 每秒 0.6 弧度:兩張擷圖相隔一秒約 34 度,那顯然是不同的角度,而且離「會讓立方體看起來
            // 沒變」的 90 度還很遠。
            let first = self.firstTimestamp ?? timestamp
            self.firstTimestamp = first
            self.angle = (timestamp - first) * 0.6
            if let frame = self.latestFrame {
                self.renderer = frame.renderer
                self.drawablePixels = "\(frame.drawableSize.x) x \(frame.drawableSize.y) px"
                self.framesDrawn = frame.frameCount
            }
            if self.ticks % 60 == 0 {
                P72Diagnostics.write(
                    "tick \(self.ticks), frames \(self.framesDrawn), "
                        + "angle \(String(format: "%.2f", self.angle)) rad, "
                        + "renderer \(self.renderer), drawable \(self.drawablePixels)"
                )
            }
        }
    }
}

@main
@HotReloadable
struct P72App: App {
    var body: some Scene {
        WindowGroup("P72 mesh view") {
            #hotReloadable {
                P72RootView()
            }
        }
        .defaultSize(width: 520, height: 660)
    }
}

struct P72RootView: View {
    @ObservedObject var model = P72Model.shared
    @Environment(\.backend) var backend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P72: a mesh view, drawn by the backend (M10)")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text(
                "mesh view supported: "
                    + "\(backend is any BackendFeatures.Mesh3DViews ? "yes" : "NO")"
            )

            Mesh3DView(
                model.scene,
                onFrame: { info in P72Model.shared.record(info) },
                snapshotter: model.snapshotter
            )
            .frame(width: 340, height: 240)

            Text("renderer: \(model.renderer)")
            Text("drawable: \(model.drawablePixels)")
            Text("frames drawn: \(model.framesDrawn)")
            Text("clock ticks: \(model.ticks)  (\(model.clockState))")

            // A Button rather than a `Toggle`, and that is not laziness.
            // P45 records a SoftPCB report, reproduced on macOS, that a `Toggle`
            // whose `isOn` is a `Binding(get:set:)` over a model resets the view
            // around it when pressed. Every `Toggle` in this tree binds to
            // `@State` through `$`; this state lives on the shared model, so a
            // Button is the shape that is known to work here. Its label carries
            // the state, so a capture still says which way it is set.
            //
            // 這裡用 Button 而不是 `Toggle`,那不是偷懶。P45 記錄了一份 SoftPCB 的回報(已在 macOS 上
            // 重現):一個 `isOn` 為「讀寫某個 model 的 `Binding(get:set:)`」的 `Toggle`,按下時會把它
            // 周圍的 view 重置掉。這棵樹裡每一個 `Toggle` 都是以 `$` 綁到 `@State`;而此處的狀態住在
            // 共用 model 上,因此 Button 才是這裡已知可用的形狀。它的標籤帶著狀態,所以一張擷圖仍然
            // 說得出它現在是哪一邊。
            HStack(spacing: 10) {
                Button("Auto spin: \(model.spinning ? "on" : "off")") {
                    P72Model.shared.toggleSpin()
                }
                Button("Stop the clock") {
                    P72Model.shared.stopAndRecord()
                }
                Button("Check again") {
                    P72Model.shared.checkAgain()
                }
            }
            // A second row rather than a fourth button beside the other three,
            // to keep the row above readable at phone width.
            //
            // **It does NOT leave the coordinates above it alone, which is what
            // this comment first claimed.** The window is a fixed 660 points and
            // the content is centred in it, so one more row lifts EVERYTHING by
            // half a row: the button row above moved from y 511 to y 483. The
            // capture said so; the reasoning had not. Any change to this view's
            // height means re-measuring both action files, wherever the change
            // is made.
            //
            // 這裡用第二列、而不是在那三顆旁邊再加第四顆,是為了讓上面那一列在手機寬度下仍然讀得出來。
            //
            // **它並**不會**讓它上方的座標維持不動——而那正是這段註解一開始的說法。** 視窗固定 660 點、
            // 內容在其中置中,因此多一列會把**所有東西**往上抬半列:上面那一列的按鈕由 y 511 移到 y 483。
            // 是擷圖這麼說的,推理並沒有。只要改動這個 view 的高度,不管改在哪裡,兩份動作檔都要重新量。
            HStack(spacing: 10) {
                Button("Export .glb") {
                    P72Model.shared.exportGLB()
                }
                Button("Snapshot") {
                    P72Model.shared.takeSnapshot()
                }
            }
            Text("glTF export: \(model.exportResult)")
            Text("snapshot: \(model.snapshotResult)")

            Text(
                "frames at the stop: \(model.framesAtStop)   "
                    + "at the check: \(model.framesAtCheck)"
            )
            Text(
                "Two captures a second apart must differ in BOTH: the frame count and the "
                    + "cube's angle. One without the other is a failure, not a partial pass. "
                    + "Then: stop, wait, check -- the two counts must be within 2."
            )
            Text(
                "相隔一秒的兩張擷圖,必須在**兩件事**上都不同:幀計數,以及立方體的角度。"
                    + "只有其一,是失敗,不是部分通過。接著:停止、等待、檢查——兩個計數的差必須在 2 以內。"
            )
        }
        .padding(20)
        .onAppear {
            P72Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P72Diagnostics.write(
                "mesh view supported: "
                    + "\(backend is any BackendFeatures.Mesh3DViews ? "yes" : "NO")"
            )
            P72Model.shared.start(backend: backend)
            P72Diagnostics.renderComplete()
        }
    }
}
