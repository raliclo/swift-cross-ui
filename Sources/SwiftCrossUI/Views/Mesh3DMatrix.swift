import Foundation

/// A 4x4 matrix, column-major, sixteen floats.
///
/// **Here rather than in a backend, because the alternative was two of them.** The Metal renderer
/// had `modelMatrix`, `rotationMatrix`, `lookAt` and `perspective` as private functions of
/// `Mesh3DMetalView`, each with a comment saying which convention it had chosen -- the Z-then-Y-
/// then-X Euler order, the right-handed look-at, the [0, 1] depth range. Writing the same four for
/// AndroidBackend would have meant four more chances to choose differently, and a cube that is
/// subtly wrong on one platform is not something a screenshot comparison reliably catches.
///
/// **`simd_float4x4` is not available on Android, which is why this type exists at all.** The
/// `simd` module is Apple-only; `SIMD4<Float>` is in the standard library and is what the columns
/// are made of, so `Mesh3DMetalView` converts to `simd_float4x4` in one place at the boundary and
/// nothing else has to know.
///
/// 一個 4x4 矩陣,column-major,十六個 float。
///
/// **放在這裡而不是某個 backend 裡,因為另一個選項是「有兩份」。** Metal renderer 原本把
/// `modelMatrix`、`rotationMatrix`、`lookAt`、`perspective` 寫成 `Mesh3DMetalView` 的私有函式,
/// 每一個都附著一段「它選了哪個慣例」的註解——Z 再 Y 再 X 的 Euler 順序、右手系 look-at、[0, 1] 的
/// 深度範圍。為 AndroidBackend 再寫一次同樣的四個,等於多四次「可以選得不一樣」的機會;而一個
/// 「在某個平台上細微地錯了」的立方體,並不是擷圖比對可靠抓得到的東西。
///
/// **`simd_float4x4` 在 Android 上不存在,那正是這個型別存在的理由。** `simd` 模組是 Apple 專屬的;
/// `SIMD4<Float>` 在標準函式庫裡,而它就是這些 column 的組成。因此 `Mesh3DMetalView` 只在一個邊界處
/// 轉成 `simd_float4x4`,其餘的東西都不必知道這件事。
public struct Mesh3DMatrix4: Equatable, Sendable {
    /// The four columns, in the order a shader expects them.
    /// 四個 column,依 shader 所預期的順序。
    public var columns: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)

    public init(
        _ column0: SIMD4<Float>,
        _ column1: SIMD4<Float>,
        _ column2: SIMD4<Float>,
        _ column3: SIMD4<Float>
    ) {
        columns = (column0, column1, column2, column3)
    }

    public static let identity = Mesh3DMatrix4(
        SIMD4(1, 0, 0, 0),
        SIMD4(0, 1, 0, 0),
        SIMD4(0, 0, 1, 0),
        SIMD4(0, 0, 0, 1)
    )

    public static func == (lhs: Mesh3DMatrix4, rhs: Mesh3DMatrix4) -> Bool {
        lhs.columns.0 == rhs.columns.0 && lhs.columns.1 == rhs.columns.1
            && lhs.columns.2 == rhs.columns.2 && lhs.columns.3 == rhs.columns.3
    }

    /// Sixteen floats, column by column -- the layout both Metal and OpenGL take.
    /// 十六個 float,逐 column 排列——Metal 與 OpenGL 都接受的排列。
    public var elements: [Float] {
        let c = columns
        return [
            c.0.x,
            c.0.y,
            c.0.z,
            c.0.w,
            c.1.x,
            c.1.y,
            c.1.z,
            c.1.w,
            c.2.x,
            c.2.y,
            c.2.z,
            c.2.w,
            c.3.x,
            c.3.y,
            c.3.z,
            c.3.w,
        ]
    }

    /// `lhs * rhs`, applying `rhs` first -- the usual convention, and the one the callers below
    /// are written in.
    /// `lhs * rhs`,先套用 `rhs`——慣例如此,而下方各呼叫端也是照這個慣例寫的。
    public static func * (lhs: Mesh3DMatrix4, rhs: Mesh3DMatrix4) -> Mesh3DMatrix4 {
        func column(_ v: SIMD4<Float>) -> SIMD4<Float> {
            lhs.columns.0 * v.x + lhs.columns.1 * v.y + lhs.columns.2 * v.z + lhs.columns.3 * v.w
        }
        return Mesh3DMatrix4(
            column(rhs.columns.0),
            column(rhs.columns.1),
            column(rhs.columns.2),
            column(rhs.columns.3)
        )
    }
}

/// **The depth convention a projection matrix is built for.**
///
/// A matrix copied from an OpenGL tutorial renders a Metal scene that looks right until something
/// is behind something else, and then the depth test decides wrongly in the half of the range that
/// got squashed. The symptom appears far from the cause, so the choice is a parameter with a name
/// rather than a constant inside the function.
///
/// **一個投影矩陣是為哪一種深度慣例而建的。**
///
/// 從 OpenGL 教學抄來的矩陣,在 Metal 上畫出的場景在「沒有東西擋住東西」之前都看起來正確;一旦有遮擋,
/// 深度測試就會在被壓扁的那半個範圍裡做出錯誤判斷。症狀離成因很遠,因此這個選擇是一個**具名的參數**,
/// 而不是函式內部的一個常數。
public enum Mesh3DDepthRange: Sendable {
    /// Metal, Direct3D and Vulkan: clip-space z runs 0 at the near plane to 1 at the far one.
    /// Metal、Direct3D 與 Vulkan:clip space 的 z 從近平面的 0 到遠平面的 1。
    case zeroToOne
    /// OpenGL and OpenGL ES: -1 at the near plane to 1 at the far one.
    /// OpenGL 與 OpenGL ES:近平面 -1、遠平面 1。
    case minusOneToOne
}

extension Mesh3DMatrix4 {
    /// Scale, then rotate (Z, then Y, then X), then translate -- the order ``Mesh3DTransform``
    /// documents, in one place so that no backend can pick a different one.
    /// 先縮放、再旋轉(Z、Y、X 之序)、最後平移——即 ``Mesh3DTransform`` 所載明的順序;寫在同一個地方,
    /// 好讓沒有任何 backend 能挑一個不同的順序。
    public static func model(_ transform: Mesh3DTransform) -> Mesh3DMatrix4 {
        let s = transform.scale
        let scale = Mesh3DMatrix4(
            SIMD4(s.x, 0, 0, 0),
            SIMD4(0, s.y, 0, 0),
            SIMD4(0, 0, s.z, 0),
            SIMD4(0, 0, 0, 1)
        )
        var m = rotation(transform.rotation) * scale
        m.columns.3 = SIMD4(
            transform.translation.x,
            transform.translation.y,
            transform.translation.z,
            1
        )
        return m
    }

    /// The rotation alone, as Euler angles applied Z, then Y, then X.
    ///
    /// The turns go through `Double`, for the reason `quaternion(fromEulerZYX:)` in
    /// `Mesh3DExport.swift` records: `sin(Float)` is a Darwin overload and Bionic does not have
    /// one, so a bare `sin(euler.x)` here would build on macOS and stop the whole package building
    /// for Android. That cost this tree two days once already.
    ///
    /// 只有旋轉,以 Euler 角依 Z、Y、X 之序套用。
    ///
    /// 這些角度走 `Double`,理由記在 `Mesh3DExport.swift` 的 `quaternion(fromEulerZYX:)`:
    /// `sin(Float)` 是 Darwin 的多載,Bionic 沒有;因此此處一句光禿禿的 `sin(euler.x)` 會在 macOS 上
    /// 建得過,並讓**整個套件**在 Android 上建不起來。那件事已經讓這棵樹付出過兩天的代價。
    public static func rotation(_ euler: SIMD3<Float>) -> Mesh3DMatrix4 {
        let x = Double(euler.x)
        let y = Double(euler.y)
        let z = Double(euler.z)
        let sx = Float(sin(x))
        let cx = Float(cos(x))
        let sy = Float(sin(y))
        let cy = Float(cos(y))
        let sz = Float(sin(z))
        let cz = Float(cos(z))
        let rx = Mesh3DMatrix4(
            SIMD4(1, 0, 0, 0),
            SIMD4(0, cx, sx, 0),
            SIMD4(0, -sx, cx, 0),
            SIMD4(0, 0, 0, 1)
        )
        let ry = Mesh3DMatrix4(
            SIMD4(cy, 0, -sy, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(sy, 0, cy, 0),
            SIMD4(0, 0, 0, 1)
        )
        let rz = Mesh3DMatrix4(
            SIMD4(cz, sz, 0, 0),
            SIMD4(-sz, cz, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        )
        return rx * ry * rz
    }

    /// Right-handed look-at, the same construction three.js's `Matrix4.lookAt` makes, kept here
    /// rather than pulled from a maths package: it is eleven lines, and a dependency for eleven
    /// lines is a dependency to update.
    /// 右手系的 look-at,與 three.js `Matrix4.lookAt` 的構造相同;留在此處而不引入數學套件:
    /// 它只有十一行,而為了十一行引入相依,就是多一個要維護的相依。
    public static func lookAt(
        eye: SIMD3<Float>,
        target: SIMD3<Float>,
        up: SIMD3<Float>
    ) -> Mesh3DMatrix4 {
        let forward = normalized(target - eye)
        let right = normalized(cross(forward, up))
        let trueUp = cross(right, forward)
        return Mesh3DMatrix4(
            SIMD4(right.x, trueUp.x, -forward.x, 0),
            SIMD4(right.y, trueUp.y, -forward.y, 0),
            SIMD4(right.z, trueUp.z, -forward.z, 0),
            SIMD4(-dot(right, eye), -dot(trueUp, eye), dot(forward, eye), 1)
        )
    }

    /// Perspective, for the depth range the caller's API uses. See ``Mesh3DDepthRange``.
    /// 透視投影,依呼叫端 API 所用的深度範圍而定。見 ``Mesh3DDepthRange``。
    public static func perspective(
        fovyDegrees: Float,
        aspect: Float,
        near: Float,
        far: Float,
        depthRange: Mesh3DDepthRange
    ) -> Mesh3DMatrix4 {
        let fovy = Double(fovyDegrees) * .pi / 180
        let y = Float(1 / tan(fovy * 0.5))
        let x = y / max(aspect, 0.0001)
        switch depthRange {
            case .zeroToOne:
                let z = far / (near - far)
                return Mesh3DMatrix4(
                    SIMD4(x, 0, 0, 0),
                    SIMD4(0, y, 0, 0),
                    SIMD4(0, 0, z, -1),
                    SIMD4(0, 0, z * near, 0)
                )
            case .minusOneToOne:
                let z = (far + near) / (near - far)
                return Mesh3DMatrix4(
                    SIMD4(x, 0, 0, 0),
                    SIMD4(0, y, 0, 0),
                    SIMD4(0, 0, z, -1),
                    SIMD4(0, 0, 2 * far * near / (near - far), 0)
                )
        }
    }

    /// Projection times view, for a camera and an aspect ratio.
    /// 投影乘以視圖,給定一台相機與一個長寬比。
    public static func viewProjection(
        camera: Mesh3DCamera,
        aspect: Float,
        depthRange: Mesh3DDepthRange
    ) -> Mesh3DMatrix4 {
        perspective(
            fovyDegrees: camera.fieldOfView,
            aspect: aspect,
            near: camera.near,
            far: camera.far,
            depthRange: depthRange
        ) * lookAt(eye: camera.position, target: camera.target, up: camera.up)
    }
}

/// Written out because `simd`'s versions are Apple-only, and these three are four lines between
/// them. `Mesh3DExport.swift` has the same pair for the same reason.
/// 自己寫出來,因為 `simd` 的版本是 Apple 專屬的,而這三個加起來只有四行。`Mesh3DExport.swift` 基於
/// 同樣的理由有同一對函式。
func normalized(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let length = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
    return length > 0 ? v / length : v
}

func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
}

func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    a.x * b.x + a.y * b.y + a.z * b.z
}
