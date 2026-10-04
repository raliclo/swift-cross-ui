package dev.swiftcrossui.androidbackend

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * A `Mesh3DScene` drawn with OpenGL ES 2.0.
 *
 * **`RENDERMODE_WHEN_DIRTY`, and it is the single most important line in the file.** A
 * `GLSurfaceView` defaults to `RENDERMODE_CONTINUOUSLY`, which redraws about sixty times a second
 * whether or not anything changed. P72's acceptance test is a frame count that stops when the app's
 * own clock stops -- with continuous rendering that count keeps climbing and the app reports a
 * renderer that drives itself, which is exactly the failure P72 exists to detect. `MTKView` has the
 * same trap under a different name, and `Mesh3DMetalView` sets `enableSetNeedsDisplay = true` for
 * the same reason.
 *
 * **No matrix arithmetic here.** The MVP and normal matrices arrive from Swift already multiplied,
 * computed by `Mesh3DMatrix4` in SwiftCrossUI, which is the same code the Metal renderer uses. A
 * second implementation of `lookAt` would be a second chance to pick a handedness.
 *
 * **The shader is the Metal one, transliterated.** Lambert against one directional light plus a
 * fixed 0.25 ambient. Keeping the constants identical is what makes a cube look the same on both,
 * and a difference here would show up as "Android's cube is darker" with nothing to point at.
 *
 * **Per mesh, the same choices as Metal (2026-10-05).** Indexed triangles, or lines and points
 * drawn straight from the vertex array; lines and points are never lit; `lit == false` draws the
 * vertex colour as is; `depthTested == false` always passes and writes no depth. Indices are 32
 * bits: `GL_UNSIGNED_INT` needs `OES_element_index_uint` on GLES 2.0 (core in 3.0), and a device
 * without it refuses triangles past index 65,535 with a warning instead of truncating them.
 *
 * 以 OpenGL ES 2.0 繪製的 `Mesh3DScene`。
 *
 * **`RENDERMODE_WHEN_DIRTY`,而它是本檔最重要的一行。** `GLSurfaceView` 預設是
 * `RENDERMODE_CONTINUOUSLY`,不管有沒有東西改變,每秒都重畫約六十次。P72 的驗收標準是「一個會在 app
 * 自己的時鐘停下時跟著停」的幀計數——在連續算繪之下,那個計數會一直往上爬,而 app 會回報一個 「自己在跑」的 renderer;那正是 P72 存在所要偵測的失敗。`MTKView`
 * 有同一個陷阱、只是名字不同, 而 `Mesh3DMetalView` 基於相同理由設定 `enableSetNeedsDisplay = true`。
 *
 * **此處沒有矩陣運算。** MVP 與法線矩陣是從 Swift 那邊乘好了才送過來的,由 SwiftCrossUI 的 `Mesh3DMatrix4` 計算——與 Metal renderer
 * 用的是同一份程式碼。第二份 `lookAt` 實作,就是第二次 「可以挑錯慣用手系」的機會。
 *
 * **著色器是 Metal 那一份的音譯。** 一盞方向光的 Lambert 加上固定的 0.25 環境光。常數保持一致, 才讓同一個立方體在兩邊看起來一樣;此處的差異會表現為「Android
 * 的立方體比較暗」,而且無從指認。
 *
 * **逐 mesh 的選擇與 Metal 相同(2026-10-05)。** 帶索引的三角形,或直接依頂點陣列畫的線段與點;線段與點
 * 永不打光;`lit == false` 原樣畫出頂點顏色;`depthTested == false` 一律通過、不寫深度。索引為 32 位元:
 * GLES 2.0 上 `GL_UNSIGNED_INT` 需要 `OES_element_index_uint`(3.0 為核心功能);沒有它的裝置會拒絕索引
 * 超過 65,535 的三角形並警告,而不是截斷它們。
 */
class Mesh3DSurfaceView(context: Context) : GLSurfaceView(context) {
    var onFrame: SwiftAction? = null

    var frameCount = 0
        private set

    var rendererName = ""
        private set

    var drawableWidth = 0
        private set

    var drawableHeight = 0
        private set

    /** Microseconds the last frame took until the GPU finished it; -1 when not measured. */
    var renderMicros = -1L
        private set

    @Volatile private var measureRenderTime = false

    /**
     * Off by default: measuring means `glFinish` at the end of each frame, waiting for the GPU
     * instead of letting the next frame overlap (Mesh3DScene.measuresRenderTime).
     * 預設關閉:量測代表每幀結尾 `glFinish`,等待 GPU 而不讓下一幀重疊(Mesh3DScene.measuresRenderTime)。
     */
    fun setMeasureRenderTime(on: Boolean) {
        measureRenderTime = on
    }

    private val lock = Any()

    private var vertices: FloatArray = FloatArray(0)
    private var indices: IntArray = IntArray(0)
    private var meshModes: IntArray = IntArray(0)
    private var meshStarts: IntArray = IntArray(0)
    private var meshCounts: IntArray = IntArray(0)
    private var meshPointSizes: FloatArray = FloatArray(0)
    private var meshFlags: IntArray = IntArray(0)
    private var mvpMatrices: FloatArray = FloatArray(0)
    private var normalMatrices: FloatArray = FloatArray(0)
    private var light = floatArrayOf(-0.4f, -0.7f, -0.6f)
    private var background = floatArrayOf(0f, 0f, 0f, 1f)
    private var geometryDirty = false

    private var captureLatch: CountDownLatch? = null
    private var capturedPixels: ByteArray? = null

    init {
        setEGLContextClientVersion(2)
        // A depth buffer is not part of the default config on every device, and without one the
        // far faces of a cube draw over the near ones in index order -- which looks like a mesh
        // with its triangles in the wrong order rather than like a missing depth buffer.
        // 深度緩衝區不是每台裝置預設 config 的一部分;少了它,立方體的遠側面會依索引順序蓋過近側面
        // ——那看起來像「三角形順序錯了的 mesh」,而不像「少了深度緩衝區」。
        setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        setRenderer(SceneRenderer())
        renderMode = RENDERMODE_WHEN_DIRTY
    }

    /**
     * One entry per mesh in `modes` .. `flags`, in scene order. `modes`: 0 indexed triangles,
     * 1 lines, 2 points; `starts`/`counts` are indices for triangles, vertices otherwise;
     * `flags` bit 0 lit, bit 1 depth-tested.
     *
     * `modes` 到 `flags` 每個 mesh 一筆、依場景順序。`modes`:0 帶索引的三角形、1 線段、2 點;
     * `starts`/`counts` 對三角形是索引、其餘是頂點;`flags` bit 0 打光、bit 1 深度測試。
     */
    fun setGeometry(
        vertices: FloatArray,
        indices: IntArray,
        modes: IntArray,
        starts: IntArray,
        counts: IntArray,
        pointSizes: FloatArray,
        flags: IntArray,
    ) {
        synchronized(lock) {
            this.vertices = vertices
            this.indices = indices
            this.meshModes = modes
            this.meshStarts = starts
            this.meshCounts = counts
            this.meshPointSizes = pointSizes
            this.meshFlags = flags
            geometryDirty = true
        }
    }

    /** Sixteen floats per mesh in each array, column-major, already multiplied. */
    fun setMatrices(mvps: FloatArray, normals: FloatArray) {
        synchronized(lock) {
            mvpMatrices = mvps
            normalMatrices = normals
        }
    }

    fun setLight(x: Float, y: Float, z: Float) {
        synchronized(lock) { light = floatArrayOf(x, y, z) }
    }

    fun setBackground(r: Float, g: Float, b: Float, a: Float) {
        synchronized(lock) { background = floatArrayOf(r, g, b, a) }
    }

    fun redraw() {
        requestRender()
    }

    /**
     * The pixels of the last frame, RGBA, top row first.
     *
     * **`View.draw(Canvas)` cannot do this and returns a blank box instead of failing.** A
     * `GLSurfaceView` is a `SurfaceView`: its content lives on a separate surface that the window
     * compositor owns, and the view itself punches a hole in the layout. A canvas snapshot of it is
     * the hole. So the generic path in `AndroidBackend+WidgetSnapshots.swift` checks for this class
     * first and calls here, the same way AppKitBackend checks for `Mesh3DMetalView` before reaching
     * for `cacheDisplay`.
     *
     * `glReadPixels` must run on the GL thread, so this asks for a frame and waits for it.
     * Bottom-up is OpenGL's convention and `WidgetSnapshot` is top-down, so the rows are flipped on
     * the way out.
     *
     * 最後一幀的像素,RGBA,第一列在最上。
     *
     * **`View.draw(Canvas)` 做不到這件事,而且它會回傳一個空盒子、不是失敗。** `GLSurfaceView` 是一個
     * `SurfaceView`:它的內容住在一個由視窗合成器持有的獨立 surface 上,而那個 view 本身只是在版面上 挖了一個洞。對它做 canvas 快照,拿到的就是那個洞。因此
     * `AndroidBackend+WidgetSnapshots.swift` 的通用路徑會**先**檢查這個類別再呼叫此處 ——與 AppKitBackend 在動用
     * `cacheDisplay` 之前先檢查 `Mesh3DMetalView` 是同一個做法。
     *
     * `glReadPixels` 必須在 GL 執行緒上跑,因此此處要求一幀並等待它。由下而上是 OpenGL 的慣例,而 `WidgetSnapshot`
     * 是由上而下,所以列在交出去時會被翻轉。
     */
    fun snapshotPixels(): ByteArray {
        val latch = CountDownLatch(1)
        synchronized(lock) {
            capturedPixels = null
            captureLatch = latch
        }
        requestRender()
        // Two seconds, not forever: a surface that has not been created yet never draws, and a
        // snapshot button that hangs the UI thread is worse than one that returns nothing.
        // 兩秒,不是永遠:一個尚未建立的 surface 永遠不會畫,而一個「把 UI 執行緒卡住」的快照按鈕,
        // 比一個「什麼都不回傳」的更糟。
        latch.await(2, TimeUnit.SECONDS)
        return synchronized(lock) {
            captureLatch = null
            capturedPixels ?: ByteArray(0)
        }
    }

    private inner class SceneRenderer : Renderer {
        private var program = 0
        private var positionAttribute = 0
        private var normalAttribute = 0
        private var colourAttribute = 0
        private var mvpUniform = 0
        private var normalUniform = 0
        private var lightUniform = 0
        private var pointSizeUniform = 0
        private var litUniform = 0

        private var vertexBuffer: java.nio.FloatBuffer? = null
        // Exactly one of the two is used: 32-bit when the context can draw them, 16-bit otherwise.
        // 兩者只用其一:context 能畫 32 位元索引時用它,否則用 16 位元。
        private var intIndexBuffer: java.nio.IntBuffer? = null
        private var shortIndexBuffer: java.nio.ShortBuffer? = null
        private var uint32Indices = false
        private var refusedWideIndices = false

        override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
            program = buildProgram()
            positionAttribute = GLES20.glGetAttribLocation(program, "aPosition")
            normalAttribute = GLES20.glGetAttribLocation(program, "aNormal")
            colourAttribute = GLES20.glGetAttribLocation(program, "aColour")
            mvpUniform = GLES20.glGetUniformLocation(program, "uMvp")
            normalUniform = GLES20.glGetUniformLocation(program, "uNormal")
            lightUniform = GLES20.glGetUniformLocation(program, "uLight")
            pointSizeUniform = GLES20.glGetUniformLocation(program, "uPointSize")
            litUniform = GLES20.glGetUniformLocation(program, "uLit")
            GLES20.glEnable(GLES20.GL_DEPTH_TEST)
            val version = GLES20.glGetString(GLES20.GL_VERSION) ?: ""
            val extensions = GLES20.glGetString(GLES20.GL_EXTENSIONS) ?: ""
            uint32Indices =
                version.startsWith("OpenGL ES 3") ||
                    extensions.split(' ').contains("GL_OES_element_index_uint")
            rendererName =
                (GLES20.glGetString(GLES20.GL_RENDERER) ?: "") +
                    " / " +
                    (GLES20.glGetString(GLES20.GL_VERSION) ?: "")
            // The geometry buffers belong to the old context; a surface can be recreated when the
            // activity resumes, and reusing them then draws nothing.
            // 幾何緩衝區屬於舊的 context;activity 恢復時 surface 可能被重建,那時沿用它們會畫不出東西。
            synchronized(lock) { geometryDirty = true }
        }

        override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
            GLES20.glViewport(0, 0, width, height)
            drawableWidth = width
            drawableHeight = height
        }

        override fun onDrawFrame(gl: GL10?) {
            val measuring = measureRenderTime
            val started = if (measuring) System.nanoTime() else 0L
            val snapshot =
                synchronized(lock) {
                    if (geometryDirty) {
                        vertexBuffer = floatBuffer(vertices)
                        intIndexBuffer = null
                        shortIndexBuffer = null
                        if (uint32Indices) {
                            intIndexBuffer = intBuffer(indices)
                        } else if (indices.all { it in 0..0xFFFF }) {
                            shortIndexBuffer = shortBuffer(indices)
                        } else if (!refusedWideIndices) {
                            refusedWideIndices = true
                            android.util.Log.w(
                                "SwiftCrossUI",
                                "render warning (the app keeps running; lines and points are still " +
                                    "drawn): this GLES context has no OES_element_index_uint and the " +
                                    "scene's triangles use indices past 65,535, so they are not drawn " +
                                    "rather than drawn wrong. What to change: a GLES 3 device, or " +
                                    "fewer than 65,536 vertices before the last triangle mesh.",
                            )
                        }
                        geometryDirty = false
                    }
                    Frame(
                        vertexBuffer,
                        intIndexBuffer,
                        shortIndexBuffer,
                        meshModes.copyOf(),
                        meshStarts.copyOf(),
                        meshCounts.copyOf(),
                        meshPointSizes.copyOf(),
                        meshFlags.copyOf(),
                        mvpMatrices.copyOf(),
                        normalMatrices.copyOf(),
                        light.copyOf(),
                        background.copyOf(),
                        captureLatch,
                    )
                }

            GLES20.glClearColor(
                snapshot.background[0],
                snapshot.background[1],
                snapshot.background[2],
                snapshot.background[3],
            )
            // Depth writes back on before the clear: glClear honours glDepthMask, and an overlay
            // drawn last in the previous frame left it off, which would keep that frame's depth.
            // 清除前先把深度寫入打開:glClear 會遵守 glDepthMask,而上一幀最後畫的覆蓋層把它關掉了,
            // 那會讓上一幀的深度留下來。
            GLES20.glDepthMask(true)
            GLES20.glDepthFunc(GLES20.GL_LESS)
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

            val vertexBuffer = snapshot.vertices
            if (program != 0 && vertexBuffer != null) {
                GLES20.glUseProgram(program)
                GLES20.glUniform3f(
                    lightUniform,
                    snapshot.light[0],
                    snapshot.light[1],
                    snapshot.light[2],
                )

                val stride = 9 * 4
                bind(positionAttribute, vertexBuffer, 0, stride)
                bind(normalAttribute, vertexBuffer, 3, stride)
                bind(colourAttribute, vertexBuffer, 6, stride)

                for (i in snapshot.modes.indices) {
                    if (i * 16 + 16 > snapshot.mvps.size) break
                    val count = snapshot.counts[i]
                    if (count <= 0) continue
                    val flags = snapshot.flags[i]
                    GLES20.glUniformMatrix4fv(mvpUniform, 1, false, snapshot.mvps, i * 16)
                    GLES20.glUniformMatrix4fv(normalUniform, 1, false, snapshot.normals, i * 16)
                    GLES20.glUniform1f(pointSizeUniform, snapshot.pointSizes[i])
                    GLES20.glUniform1f(litUniform, if (flags and 1 != 0) 1f else 0f)
                    if (flags and 2 != 0) {
                        GLES20.glDepthFunc(GLES20.GL_LESS)
                        GLES20.glDepthMask(true)
                    } else {
                        GLES20.glDepthFunc(GLES20.GL_ALWAYS)
                        GLES20.glDepthMask(false)
                    }
                    val start = snapshot.starts[i]
                    when (snapshot.modes[i]) {
                        0 -> {
                            val wide = snapshot.intIndices
                            val narrow = snapshot.shortIndices
                            if (wide != null) {
                                wide.position(start)
                                GLES20.glDrawElements(
                                    GLES20.GL_TRIANGLES, count, GLES20.GL_UNSIGNED_INT, wide)
                            } else if (narrow != null) {
                                narrow.position(start)
                                GLES20.glDrawElements(
                                    GLES20.GL_TRIANGLES, count, GLES20.GL_UNSIGNED_SHORT, narrow)
                            }
                        }
                        1 -> GLES20.glDrawArrays(GLES20.GL_LINES, start, count)
                        2 -> GLES20.glDrawArrays(GLES20.GL_POINTS, start, count)
                    }
                }
                GLES20.glDepthMask(true)
                GLES20.glDepthFunc(GLES20.GL_LESS)

                GLES20.glDisableVertexAttribArray(positionAttribute)
                GLES20.glDisableVertexAttribArray(normalAttribute)
                GLES20.glDisableVertexAttribArray(colourAttribute)
            }

            // Before onFrame, so the Swift side reads this frame's figure, not the previous one's.
            // 在 onFrame 之前,好讓 Swift 那邊讀到的是這一幀的數字,而不是上一幀的。
            if (measuring) {
                GLES20.glFinish()
                renderMicros = (System.nanoTime() - started) / 1_000
            } else {
                renderMicros = -1L
            }
            frameCount += 1
            onFrame?.call()

            val latch = snapshot.captureLatch
            if (latch != null) {
                val pixels = readPixels()
                synchronized(lock) {
                    capturedPixels = pixels
                    captureLatch = null
                }
                latch.countDown()
            }
        }

        private fun bind(
            attribute: Int,
            buffer: java.nio.FloatBuffer,
            offsetInFloats: Int,
            stride: Int,
        ) {
            if (attribute < 0) return
            buffer.position(offsetInFloats)
            GLES20.glVertexAttribPointer(attribute, 3, GLES20.GL_FLOAT, false, stride, buffer)
            GLES20.glEnableVertexAttribArray(attribute)
        }

        private fun readPixels(): ByteArray? {
            val width = drawableWidth
            val height = drawableHeight
            if (width <= 0 || height <= 0) return null
            val buffer =
                ByteBuffer.allocateDirect(width * height * 4).order(ByteOrder.nativeOrder())
            GLES20.glReadPixels(
                0,
                0,
                width,
                height,
                GLES20.GL_RGBA,
                GLES20.GL_UNSIGNED_BYTE,
                buffer,
            )
            val bottomUp = ByteArray(width * height * 4)
            buffer.rewind()
            buffer.get(bottomUp)
            val topDown = ByteArray(bottomUp.size)
            val rowBytes = width * 4
            for (row in 0 until height) {
                System.arraycopy(
                    bottomUp,
                    (height - 1 - row) * rowBytes,
                    topDown,
                    row * rowBytes,
                    rowBytes,
                )
            }
            return topDown
        }
    }

    private class Frame(
        val vertices: java.nio.FloatBuffer?,
        val intIndices: java.nio.IntBuffer?,
        val shortIndices: java.nio.ShortBuffer?,
        val modes: IntArray,
        val starts: IntArray,
        val counts: IntArray,
        val pointSizes: FloatArray,
        val flags: IntArray,
        val mvps: FloatArray,
        val normals: FloatArray,
        val light: FloatArray,
        val background: FloatArray,
        val captureLatch: CountDownLatch?,
    )

    private fun floatBuffer(values: FloatArray): java.nio.FloatBuffer? {
        if (values.isEmpty()) return null
        val buffer =
            ByteBuffer.allocateDirect(values.size * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
        buffer.put(values)
        buffer.position(0)
        return buffer
    }

    private fun intBuffer(values: IntArray): java.nio.IntBuffer? {
        if (values.isEmpty()) return null
        val buffer =
            ByteBuffer.allocateDirect(values.size * 4)
                .order(ByteOrder.nativeOrder())
                .asIntBuffer()
        buffer.put(values)
        buffer.position(0)
        return buffer
    }

    /** Only called once every index is known to fit in 16 bits. / 只在確認每個索引都放得進 16 位元後呼叫。 */
    private fun shortBuffer(values: IntArray): java.nio.ShortBuffer? {
        if (values.isEmpty()) return null
        val buffer =
            ByteBuffer.allocateDirect(values.size * 2)
                .order(ByteOrder.nativeOrder())
                .asShortBuffer()
        for (value in values) buffer.put(value.toShort())
        buffer.position(0)
        return buffer
    }

    private fun buildProgram(): Int {
        val vertex = compile(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER)
        val fragment = compile(GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER)
        if (vertex == 0 || fragment == 0) return 0
        val program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertex)
        GLES20.glAttachShader(program, fragment)
        GLES20.glLinkProgram(program)
        val status = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            // Logged rather than swallowed. A zero program draws nothing, and "nothing drew" is
            // indistinguishable from "the scene was empty" on a screen.
            // 記錄下來而不是吞掉。一個為零的 program 什麼都不畫,而「什麼都沒畫出來」在螢幕上與
            // 「場景是空的」無法區分。
            android.util.Log.e(
                "SwiftCrossUI",
                "Mesh3D program link failed: " + GLES20.glGetProgramInfoLog(program),
            )
            GLES20.glDeleteProgram(program)
            return 0
        }
        return program
    }

    private fun compile(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        val status = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            android.util.Log.e(
                "SwiftCrossUI",
                "Mesh3D shader compile failed: " + GLES20.glGetShaderInfoLog(shader),
            )
            GLES20.glDeleteShader(shader)
            return 0
        }
        return shader
    }

    companion object {
        private const val VERTEX_SHADER =
            """
            uniform mat4 uMvp;
            uniform mat4 uNormal;
            uniform float uPointSize;
            attribute vec3 aPosition;
            attribute vec3 aNormal;
            attribute vec3 aColour;
            varying vec3 vNormal;
            varying vec3 vColour;
            void main() {
                gl_Position = uMvp * vec4(aPosition, 1.0);
                // Read by the rasteriser for GL_POINTS only, as Metal's [[point_size]] is.
                // 只有 GL_POINTS 會讀它,與 Metal 的 [[point_size]] 相同。
                gl_PointSize = uPointSize;
                vNormal = (uNormal * vec4(aNormal, 0.0)).xyz;
                vColour = aColour;
            }
            """

        private const val FRAGMENT_SHADER =
            """
            precision mediump float;
            uniform vec3 uLight;
            uniform float uLit;
            varying vec3 vNormal;
            varying vec3 vColour;
            void main() {
                if (uLit < 0.5) {
                    gl_FragColor = vec4(vColour, 1.0);
                    return;
                }
                vec3 n = normalize(vNormal);
                vec3 l = normalize(-uLight);
                float lambert = max(dot(n, l), 0.0);
                gl_FragColor = vec4(vColour * (0.25 + 0.75 * lambert), 1.0);
            }
            """
    }
}
