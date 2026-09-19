// Reads a .glb back with three.js's OWN GLTFLoader and prints what it found.
//
//   node testapp/test_support/measure/gltf_check.mjs testapp/debug-events/p72-scene.glb
//
// It needs three.js resolvable as a bare `three` import. There is no checkout in
// this repo; the one used on 2026-09-19 was /Volumes/LinuxCS/render/three.js
// (submodule ea56c2f4, 0.185.0), reached with a symlink:
//
//   mkdir -p /tmp/gltfcheck/node_modules
//   ln -sfn /Volumes/LinuxCS/render/three.js /tmp/gltfcheck/node_modules/three
//   printf '{"type":"module"}' > /tmp/gltfcheck/package.json
//   cp testapp/test_support/measure/gltf_check.mjs /tmp/gltfcheck/
//   (cd /tmp/gltfcheck && node gltf_check.mjs <path to .glb>)
//
// **Why three.js and not a reader written here.** A reader written beside the
// writer agrees with it about anything they both got wrong, and this exporter
// did get something wrong: its GLB magic spelled "gltF", one bit off from
// "glTF". The length, the chunk headers, the JSON and the buffer were all
// correct, so nothing on the Swift side could have noticed. three.js refused
// the file in one line. glTF is also the format three.js reads natively, which
// is the interoperability the export exists for -- so this is the reader that
// matters, not a convenient one.
//
// 以 three.js **自己的** GLTFLoader 把一份 .glb 讀回來,並印出它讀到了什麼。
//
// 它需要能以裸 `three` 匯入解析到 three.js。本 repo 沒有 checkout;2026-09-19 使用的是
// /Volumes/LinuxCS/render/three.js(submodule ea56c2f4、0.185.0),以 symlink 接上(見上方指令)。
//
// **為什麼用 three.js,而不是在這裡寫一個 reader。** 一個寫在 writer 旁邊的 reader,會在「兩邊都弄錯的
// 地方」與它取得一致——而這個匯出器確實弄錯過一件事:它的 GLB magic 拼成了「gltF」,與「glTF」只差一個
// 位元。長度、chunk 標頭、JSON 與 buffer 全都是對的,因此 Swift 這一側沒有任何東西可能發覺。three.js
// 用一行就拒絕了那個檔案。glTF 同時也是 three.js 原生讀得懂的格式,而那正是這個匯出功能存在的理由
// ——所以它是**該用**的那個 reader,不是剛好方便的那個。
import fs from 'node:fs'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { Euler } from 'three'

const path = process.argv[2]
if (!path) { console.log('usage: node gltf_check.mjs <file.glb>'); process.exit(64) }
const buf = fs.readFileSync(path)
const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength)

new GLTFLoader().parse(ab, '', (gltf) => {
  console.log(`file          ${path} (${buf.length} bytes)`)
  console.log(`generator     ${gltf.asset.generator}  glTF ${gltf.asset.version}`)
  let meshes = 0
  gltf.scene.traverse((o) => {
    if (!o.isMesh) return
    meshes++
    const g = o.geometry
    const e = new Euler().setFromQuaternion(o.quaternion, 'XYZ')
    const p = g.attributes.position
    console.log(`mesh ${meshes}`)
    console.log(`  vertices    ${p.count}`)
    console.log(`  indices     ${g.index ? g.index.count : 0}  (${g.index ? g.index.count / 3 : 0} triangles)`)
    console.log(`  has NORMAL  ${!!g.attributes.normal}`)
    console.log(`  has COLOR_0 ${!!g.attributes.color}`)
    console.log(`  vertex[0]   ${p.getX(0).toFixed(3)}, ${p.getY(0).toFixed(3)}, ${p.getZ(0).toFixed(3)}`)
    if (g.attributes.color) {
      const c = g.attributes.color
      console.log(`  colour[0]   ${c.getX(0).toFixed(2)}, ${c.getY(0).toFixed(2)}, ${c.getZ(0).toFixed(2)}`)
    }
    // The node rotation is the one field a dropped Mesh3DTransform would zero,
    // and a zeroed one still loads. Print it.
    // node 的旋轉,正是「`Mesh3DTransform` 被丟掉」時會歸零的那一個欄位——而歸零的檔案照樣載得進來。印出來。
    console.log(`  node euler  x ${e.x.toFixed(4)}  y ${e.y.toFixed(4)}  z ${e.z.toFixed(4)} rad`)
    g.computeBoundingBox()
    const b = g.boundingBox
    console.log(`  bbox        ${b.min.x.toFixed(2)}..${b.max.x.toFixed(2)} x ${b.min.y.toFixed(2)}..${b.max.y.toFixed(2)} x ${b.min.z.toFixed(2)}..${b.max.z.toFixed(2)}`)
  })
  const cam = gltf.cameras[0]
  if (cam) {
    console.log(`camera        fov ${cam.fov.toFixed(1)} deg  near ${cam.near}  far ${cam.far}`)
    console.log(`  position    ${cam.position.x.toFixed(3)}, ${cam.position.y.toFixed(3)}, ${cam.position.z.toFixed(3)}`)
  }
  console.log(`meshes        ${meshes}`)
  if (meshes === 0) { console.log('FAIL: no mesh in the file'); process.exit(1) }
}, (err) => { console.log('FAIL:', err.message ?? err); process.exit(1) })
