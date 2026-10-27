# APK size

Measured 2026-10-24 on P96, debug build. The release build (R8, compressed
native libraries) is 37 MB; see android-setting.md.

## What

P96's APK is **113 MB**, a Gradle debug variant (`assembleDebug`), arm64-v8a
only:

| Part | Size |
|---|---:|
| `lib_FoundationICU.so` | 38.2 MB |
| `libP96.so` | 33.1 MB |
| other Swift runtime and Foundation libraries | ~28 MB |
| dex (AndroidX and Material, no R8) | ~10.4 MB |

Inside `libP96.so`: about 23 MB AndroidKit bindings, 4.8 MB SwiftJava, 4.0 MB
SwiftCrossUI and 0.8 MB AndroidBackend. Native libraries are stored
uncompressed; gzipped they come to about 38 MB in total.

## Why it is large

Android has no system Swift. Every APK carries libswiftCore, Foundation,
FoundationEssentials, dispatch and ICU, which iOS apps get from the OS
(an iOS test app was 8.5 MB, 2026-09-06). ICU is a hard `NEEDED` of
libFoundation (readelf), so it cannot be dropped. The app library's largest
part is the AndroidKit bindings, not the framework (see swift-java-fork.md for
what AndroidKit is). Module shares come from `llvm-nm -S` on the unstripped
library grouped by Swift mangling (profiling.md).

## What has already come off (2026-09-05/06)

212 MB to about 110 MB: `.swift_ast` stripped (-43 MB), SwiftSyntax no longer
linked into Android (-15 MB), Swift built release (-28 MB), exports limited by
android-exports.map (-16 MB). See build-and-packaging.md.

## Tried and rejected

`-Osize` on P44: `.text` 21.59 -> 19.61 MB, but `.eh_frame` and
`.eh_frame_hdr` grew, net 109.9 -> 108.6 MB (1.2%) for slower code everywhere.
Reverted in 81e9b6fb.

## Still open (checked 2026-10-24)

- **ImageFormats and libwebp are linked into every app**, though only P3, P6 and
  P6-v2 import them: compile.zsh sets one `needs_image_formats` flag for the
  whole manifest and adds the product to the shared `testAppDependencies`.
  Per-target dependencies would fix it; the saving has not been measured.
- `--gc-sections` and `--icf=safe`: not tried. Section GC must keep the
  `swift5_*` sections that register metadata and conformances.
- Only arm64-v8a is built. Adding another ABI without ABI splits doubles the
  native part.

## Evidence

testapp/todo/todo-mobile_app_size.md (2026-09-06), testapp/android-exports.map,
compile.zsh (`needs_image_formats`, `testAppDependencies`).

---

# APK 大小

2026-10-24 在 P96 的 debug 建置上量測。release 建置(R8、原生函式庫壓縮)為 37 MB,見 android-setting.md。

## 內容

P96 的 APK 為 **113 MB**,是 Gradle 的 debug 版本(`assembleDebug`),只含 arm64-v8a:

| 部分 | 大小 |
|---|---:|
| `lib_FoundationICU.so` | 38.2 MB |
| `libP96.so` | 33.1 MB |
| 其餘 Swift runtime 與 Foundation 函式庫 | 約 28 MB |
| dex(AndroidX 與 Material,未經 R8) | 約 10.4 MB |

`libP96.so` 內：約 23 MB 是 AndroidKit 綁定、4.8 MB SwiftJava、4.0 MB SwiftCrossUI、0.8 MB AndroidBackend。原生函式庫以
未壓縮方式存放;gzip 後總共約 38 MB。

## 為什麼這麼大

Android 沒有系統層的 Swift。每個 APK 都要自帶 libswiftCore、Foundation、FoundationEssentials、dispatch 與 ICU,iOS app
則由作業系統提供(iOS 測試 app 為 8.5 MB,2026-09-06)。ICU 是 libFoundation 的硬性 `NEEDED`(readelf),拿不掉。app 函式庫
最大的部分是 AndroidKit 綁定，不是框架本身(AndroidKit 是什麼見 swift-java-fork.md)。各 module 的比例來自對未去符號的
函式庫跑 `llvm-nm -S`,再依 Swift mangling 分組(profiling.md)。

## 已經拿掉的(2026-09-05/06)

212 MB 降到約 110 MB:去除 `.swift_ast`(-43 MB)、Android 不再連入 SwiftSyntax(-15 MB)、Swift 以 release 建置(-28 MB)、
以 android-exports.map 限制匯出(-16 MB)。見 build-and-packaging.md。

## 試過而不採用

P44 上的 `-Osize`:`.text` 21.59 → 19.61 MB,但 `.eh_frame` 與 `.eh_frame_hdr` 變大，淨值 109.9 → 108.6 MB(1.2%),
代價是所有程式碼變慢。已於 81e9b6fb 還原。

## 仍未解決(2026-10-24 查)

- **ImageFormats 與 libwebp 被連進每一支 app**,但只有 P3、P6、P6-v2 import 它們:compile.zsh 對整份 manifest 只設一個
  `needs_image_formats` 旗標，並把該 product 加進共用的 `testAppDependencies`。改成每個 target 各自的依賴即可修正；省下
  多少尚未量測。
- `--gc-sections` 與 `--icf=safe`:未試。section GC 必須保留登記 metadata 與 conformance 的 `swift5_*` 各段。
- 只建 arm64-v8a。若加上其他 ABI 而不按 ABI 切分，原生部分會加倍。

## 證據

testapp/todo/todo-mobile_app_size.md(2026-09-06)、testapp/android-exports.map、compile.zsh(`needs_image_formats`、
`testAppDependencies`)。
