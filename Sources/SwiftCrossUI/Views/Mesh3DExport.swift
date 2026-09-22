import Foundation

extension Mesh3DScene {
    /// Writes this scene as a binary glTF 2.0 file (`.glb`).
    ///
    /// **Why glTF and not OBJ, STL or USDZ.** A `Mesh3DScene` carries indexed
    /// triangles, a normal and a colour per vertex, one transform per mesh and a
    /// perspective camera. glTF 2.0 has a slot for every one of those and loses
    /// nothing: `POSITION`, `NORMAL`, `COLOR_0`, `indices`, a node's TRS, and a
    /// `perspective` camera. OBJ has no official per-vertex colour and no
    /// camera; STL has neither colour nor shared vertices; USDZ is one
    /// ecosystem. glTF is also three.js's own format, which matters here because
    /// three.js is the yardstick `plan-3D.md` measures this work against -- a
    /// file this writes can be dropped into the thing it is being compared to.
    ///
    /// **Written by hand, with no dependency, because GLB is small enough to
    /// deserve one.** The container is a 12-byte header and two chunks: JSON,
    /// then the binary buffer. Pulling in a glTF package to emit 200 lines of
    /// JSON would put a third-party release cycle in front of a feature that
    /// five backends are supposed to share.
    ///
    /// 把這個場景寫成一份二進位 glTF 2.0 檔(`.glb`)。
    ///
    /// **為什麼是 glTF,而不是 OBJ、STL 或 USDZ。** 一個 `Mesh3DScene` 帶著:帶索引的三角形、逐頂點的
    /// 法線與顏色、每個 mesh 一個變換,以及一台透視相機。glTF 2.0 對上述每一項都有對應的位置,一樣都不會
    /// 掉:`POSITION`、`NORMAL`、`COLOR_0`、`indices`、node 的 TRS,以及 `perspective` 相機。OBJ 沒有
    /// 官方的逐頂點顏色、也沒有相機;STL 既沒有顏色也沒有共用頂點;USDZ 只屬於一個生態。glTF 同時也是
    /// three.js 自己的格式——而那在此處是有意義的:three.js 正是 `plan-3D.md` 用來衡量這件工作的那把尺,
    /// 而這裡寫出來的檔案,可以直接丟進那個被拿來比較的東西裡。
    ///
    /// **手寫、不帶任何相依,因為 GLB 小到值得這麼做。** 這個容器是一個 12 位元組的檔頭加上兩個 chunk:
    /// 先 JSON、再二進位 buffer。為了產生兩百行 JSON 而引入一個 glTF 套件,等於把一個「五個 backend 都要
    /// 共用」的功能,擋在某個第三方的發佈週期後面。
    public func glbData() -> Data {
        var binary = Data()
        var bufferViews: [[String: Any]] = []
        var accessors: [[String: Any]] = []
        var meshEntries: [[String: Any]] = []
        var nodes: [[String: Any]] = []
        var nodeIndices: [Int] = []

        for mesh in meshes where !mesh.vertices.isEmpty && mesh.indices.count >= 3 {
            let positions = mesh.vertices.map(\.position)
            let normals = mesh.vertices.map(\.normal)
            let colours = mesh.vertices.map(\.colour)
            // Whole triples only, the same rule `Mesh3D` states and the renderer
            // follows. An exporter that padded the remainder would write a file
            // that disagrees with what the app is looking at.
            // 只取完整的三元組——與 `Mesh3D` 所載明、renderer 所遵循的是同一條規則。一個會把餘數補齊的
            // 匯出器,寫出來的檔案會與使用者正在看的東西不一致。
            let indices = Array(mesh.indices.prefix((mesh.indices.count / 3) * 3))

            let positionAccessor = appendVec3(
                positions,
                withBounds: true,
                to: &binary,
                bufferViews: &bufferViews,
                accessors: &accessors
            )
            let normalAccessor = appendVec3(
                normals,
                withBounds: false,
                to: &binary,
                bufferViews: &bufferViews,
                accessors: &accessors
            )
            let colourAccessor = appendVec3(
                colours,
                withBounds: false,
                to: &binary,
                bufferViews: &bufferViews,
                accessors: &accessors
            )
            let indexAccessor = appendIndices(
                indices,
                to: &binary,
                bufferViews: &bufferViews,
                accessors: &accessors
            )

            meshEntries.append([
                "primitives": [
                    [
                        "attributes": [
                            "POSITION": positionAccessor,
                            "NORMAL": normalAccessor,
                            "COLOR_0": colourAccessor,
                        ],
                        "indices": indexAccessor,
                        // 4 is TRIANGLES. Named rather than written as a bare
                        // integer would be better, and glTF gives no name for it.
                        // 4 就是 TRIANGLES。能具名當然比裸整數好,而 glTF 沒有給它名字。
                        "mode": 4,
                    ]
                ]
            ])

            let t = mesh.transform
            let q = quaternion(fromEulerZYX: t.rotation)
            nodeIndices.append(nodes.count)
            nodes.append([
                "mesh": meshEntries.count - 1,
                "translation": [t.translation.x, t.translation.y, t.translation.z],
                "rotation": [q.x, q.y, q.z, q.w],
                "scale": [t.scale.x, t.scale.y, t.scale.z],
            ])
        }

        // The camera, as a node placed where the eye is and turned to face the
        // target. glTF's camera looks down -Z with +Y up, which is the same
        // convention the renderer's look-at builds, so the node's basis is
        // [right, up, -forward] and nothing needs flipping.
        // 相機,寫成一個「擺在眼睛位置、轉向目標」的 node。glTF 的相機沿 -Z 方向看、+Y 朝上,與 renderer
        // 的 look-at 所建立的慣例相同,因此這個 node 的基底就是 [right, up, -forward],不需要翻轉任何軸。
        let cameraQ = quaternion(lookingFrom: camera.position, at: camera.target, up: camera.up)
        nodeIndices.append(nodes.count)
        nodes.append([
            "camera": 0,
            "translation": [camera.position.x, camera.position.y, camera.position.z],
            "rotation": [cameraQ.x, cameraQ.y, cameraQ.z, cameraQ.w],
        ])

        let json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "SwiftCrossUI Mesh3DScene"],
            "scene": 0,
            "scenes": [["nodes": nodeIndices]],
            "nodes": nodes,
            "meshes": meshEntries,
            "cameras": [
                [
                    "type": "perspective",
                    "perspective": [
                        // glTF wants radians; `Mesh3DCamera` is in degrees,
                        // because that is what three.js's `PerspectiveCamera`
                        // takes and the two are meant to read alike.
                        // glTF 要的是弧度;`Mesh3DCamera` 用的是度,因為 three.js 的
                        // `PerspectiveCamera` 就是取度,而兩者是刻意寫得可以對讀的。
                        "yfov": camera.fieldOfView * .pi / 180,
                        "znear": camera.near,
                        "zfar": camera.far,
                    ],
                ]
            ],
            "bufferViews": bufferViews,
            "accessors": accessors,
            "buffers": [["byteLength": binary.count]],
        ]

        guard
            var jsonChunk = try? JSONSerialization.data(
                withJSONObject: json,
                options: [.sortedKeys]
            )
        else {
            return Data()
        }

        // Both chunks are padded to four bytes -- JSON with spaces, the buffer
        // with zeros, which the specification requires by name. A reader that
        // tolerates unpadded chunks exists; the next one does not.
        // 兩個 chunk 都要補齊到四位元組——JSON 補空格、buffer 補零,規格明文如此要求。容忍未補齊的 reader
        // 是有的;下一個就不是了。
        while jsonChunk.count % 4 != 0 { jsonChunk.append(0x20) }
        var binaryChunk = binary
        while binaryChunk.count % 4 != 0 { binaryChunk.append(0x00) }

        var glb = Data()
        // 0x4654_6C67 little-endian is 67 6C 54 46 -- 'g' 'l' 'T' 'F'. Written as
        // 0x4674_6C67 first, which is 'g' 'l' 't' 'F': a lowercase t, one bit
        // different, and the only thing that rejected it was three.js. Nothing
        // here could: the file's length, chunk headers, JSON and buffer were all
        // correct, so every check written on this side passed.
        // 0x4654_6C67 以 little-endian 排出來是 67 6C 54 46——'g' 'l' 'T' 'F'。一開始寫成 0x4674_6C67,
        // 那是 'g' 'l' 't' 'F':一個小寫 t、差一個位元,而唯一拒絕它的是 three.js。這一側沒有任何東西能
        // 發現:檔案長度、chunk 標頭、JSON 與 buffer 全都是對的,因此這邊寫的每一項檢查都通過了。
        glb.append(littleEndian: UInt32(0x4654_6C67)) // "glTF"
        glb.append(littleEndian: UInt32(2))
        glb.append(littleEndian: UInt32(12 + 8 + jsonChunk.count + 8 + binaryChunk.count))
        glb.append(littleEndian: UInt32(jsonChunk.count))
        glb.append(littleEndian: UInt32(0x4E4F_534A)) // "JSON"
        glb.append(jsonChunk)
        glb.append(littleEndian: UInt32(binaryChunk.count))
        glb.append(littleEndian: UInt32(0x004E_4942)) // "BIN\0"
        glb.append(binaryChunk)
        return glb
    }

    private func appendVec3(
        _ values: [SIMD3<Float>],
        withBounds: Bool,
        to binary: inout Data,
        bufferViews: inout [[String: Any]],
        accessors: inout [[String: Any]]
    ) -> Int {
        let offset = binary.count
        for v in values {
            binary.append(littleEndian: v.x.bitPattern)
            binary.append(littleEndian: v.y.bitPattern)
            binary.append(littleEndian: v.z.bitPattern)
        }
        bufferViews.append([
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": binary.count - offset,
            "target": 34962, // ARRAY_BUFFER
        ])

        var accessor: [String: Any] = [
            "bufferView": bufferViews.count - 1,
            "componentType": 5126, // FLOAT
            "count": values.count,
            "type": "VEC3",
        ]
        // `min` and `max` are REQUIRED on a POSITION accessor and optional
        // elsewhere. A file without them loads in some viewers and is rejected
        // by the specification's own validator, which is the kind of "works here"
        // this tree does not accept as evidence.
        // `min` 與 `max` 在 POSITION accessor 上是**必填**,在其他地方是選填。少了它們的檔案在某些檢視器
        // 裡打得開,卻會被規格自己的驗證器拒絕——而那正是這棵樹不接受作為證據的那種「在我這裡可以」。
        if withBounds, let first = values.first {
            var lo = first
            var hi = first
            for v in values {
                lo = SIMD3(min(lo.x, v.x), min(lo.y, v.y), min(lo.z, v.z))
                hi = SIMD3(max(hi.x, v.x), max(hi.y, v.y), max(hi.z, v.z))
            }
            accessor["min"] = [lo.x, lo.y, lo.z]
            accessor["max"] = [hi.x, hi.y, hi.z]
        }
        accessors.append(accessor)
        return accessors.count - 1
    }

    private func appendIndices(
        _ indices: [UInt32],
        to binary: inout Data,
        bufferViews: inout [[String: Any]],
        accessors: inout [[String: Any]]
    ) -> Int {
        let offset = binary.count
        for i in indices { binary.append(littleEndian: i) }
        bufferViews.append([
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": binary.count - offset,
            "target": 34963, // ELEMENT_ARRAY_BUFFER
        ])
        accessors.append([
            "bufferView": bufferViews.count - 1,
            "componentType": 5125, // UNSIGNED_INT
            "count": indices.count,
            "type": "SCALAR",
        ])
        return accessors.count - 1
    }
}

/// A rotation, as glTF stores one.
/// 一個旋轉,以 glTF 儲存它的形式表示。
private struct Quaternion {
    var x: Float
    var y: Float
    var z: Float
    var w: Float
}

/// Euler angles to a quaternion, in the Z-then-Y-then-X order
/// ``Mesh3DTransform`` documents.
///
/// **The order is the whole content of this function.** Every Euler-to-
/// quaternion formula on the internet is correct for some order, and using one
/// written for a different order produces a file that is wrong only when two of
/// the three angles are non-zero -- which a cube spinning about one axis will
/// never reveal.
///
/// Euler 角轉四元數,採 ``Mesh3DTransform`` 所載明的「先 Z、再 Y、後 X」之序。
///
/// **這個函式的全部內容就是那個順序。** 網路上每一條 Euler 轉四元數的公式,對**某個**順序而言都是對的;
/// 而用了一條為別的順序所寫的公式,產生的檔案只有在三個角當中有兩個不為零時才會錯——而一個只繞單軸自轉的
/// 立方體,永遠不會讓那件事顯露出來。
private func quaternion(fromEulerZYX euler: SIMD3<Float>) -> Quaternion {
    // **Halved and turned in `Double`, because `sin(Float)` is not a function
    // every target has.** The `Float` overload comes from the platform's own
    // maths module -- Darwin has one, Bionic does not: its `math.h` offers
    // `double sin(double)` and `float sinf(float)` and nothing in between. So a
    // bare `sin(euler.x / 2)` type-checks on macOS, and on Android the compiler
    // cannot even settle what `/` means, which is what it reported. Going
    // through `Double` needs no `#if` and no `sinf`, and the extra precision is
    // free at six calls.
    //
    // **先取半、以 `Double` 運算,因為 `sin(Float)` 不是每個目標都有的函式。** 那個 `Float` 多載來自
    // 平台自己的數學模組——Darwin 有,Bionic 沒有:它的 `math.h` 只給 `double sin(double)` 與
    // `float sinf(float)`,中間什麼都沒有。因此一句光禿禿的 `sin(euler.x / 2)` 在 macOS 上型別檢查
    // 得過,而在 Android 上編譯器連 `/` 是什麼意思都定不下來——它回報的正是那個。走 `Double` 不需要
    // 任何 `#if`、也不需要 `sinf`,而六次呼叫多出來的精度不花什麼。
    let half = SIMD3<Double>(Double(euler.x), Double(euler.y), Double(euler.z)) / 2
    let sx = Float(sin(half.x))
    let cx = Float(cos(half.x))
    let sy = Float(sin(half.y))
    let cy = Float(cos(half.y))
    let sz = Float(sin(half.z))
    let cz = Float(cos(half.z))
    return Quaternion(
        x: sx * cy * cz + cx * sy * sz,
        y: cx * sy * cz - sx * cy * sz,
        z: cx * cy * sz + sx * sy * cz,
        w: cx * cy * cz - sx * sy * sz
    )
}

/// The orientation of a camera at `eye` facing `target`.
/// 一台位於 `eye`、面向 `target` 的相機的方位。
private func quaternion(
    lookingFrom eye: SIMD3<Float>,
    at target: SIMD3<Float>,
    up: SIMD3<Float>
) -> Quaternion {
    let forward = normalized(target - eye)
    let right = normalized(cross(forward, up))
    let trueUp = cross(right, forward)
    let back = -forward

    // Matrix to quaternion, branching on which diagonal term is largest. The
    // single-formula version divides by a number that approaches zero at a
    // 180-degree rotation, and what comes out is not an error but a camera
    // pointing somewhere else.
    // 矩陣轉四元數,依對角線上哪一項最大而分支。單一公式的版本,其除數在旋轉接近 180 度時趨近於零,
    // 而出來的東西不是一個錯誤,是一台指向別處的相機。
    let trace = right.x + trueUp.y + back.z
    if trace > 0 {
        let s = (trace + 1).squareRoot() * 2
        return Quaternion(
            x: (trueUp.z - back.y) / s,
            y: (back.x - right.z) / s,
            z: (right.y - trueUp.x) / s,
            w: 0.25 * s
        )
    } else if right.x > trueUp.y, right.x > back.z {
        let s = (1 + right.x - trueUp.y - back.z).squareRoot() * 2
        return Quaternion(
            x: 0.25 * s,
            y: (trueUp.x + right.y) / s,
            z: (back.x + right.z) / s,
            w: (trueUp.z - back.y) / s
        )
    } else if trueUp.y > back.z {
        let s = (1 + trueUp.y - right.x - back.z).squareRoot() * 2
        return Quaternion(
            x: (trueUp.x + right.y) / s,
            y: 0.25 * s,
            z: (back.y + trueUp.z) / s,
            w: (back.x - right.z) / s
        )
    } else {
        let s = (1 + back.z - right.x - trueUp.y).squareRoot() * 2
        return Quaternion(
            x: (back.x + right.z) / s,
            y: (back.y + trueUp.z) / s,
            z: 0.25 * s,
            w: (right.y - trueUp.x) / s
        )
    }
}

// `normalized` and `cross` used to be file-private here. They now live beside the matrices in
// `Mesh3DMatrix.swift`, which needs the same two and would otherwise have been a second copy --
// and a second copy of `cross` is a sign error waiting to disagree with this file's quaternion.
// `normalized` 與 `cross` 原本是本檔的 file-private 函式。它們現在與各矩陣一同住在
// `Mesh3DMatrix.swift`——那邊需要同樣這兩個,否則就會是第二份;而第二份 `cross` 是一個
// 「等著與本檔四元數對不上的正負號錯誤」。

extension Data {
    /// glTF is little-endian everywhere, on every platform, whatever the host is.
    /// glTF 處處都是 little-endian,在每個平台上都是,不論主機是什麼。
    fileprivate mutating func append(littleEndian value: UInt32) {
        // `Swift.withUnsafeBytes`, spelled out: unqualified, it resolves to
        // `Data`'s own instance method, which reads THIS data rather than the
        // value -- and appends nothing.
        // 寫成 `Swift.withUnsafeBytes`:不加限定時,它會解析到 `Data` 自己的實例方法——那讀的是**這份
        // data**、不是那個值,而且什麼也不會附加上去。
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
