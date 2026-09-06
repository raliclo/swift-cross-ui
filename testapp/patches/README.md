# patches

Changes this tree needs in code it does not own, kept as patches because the
tree that owns them cannot be pushed to from here.

| patch | applies to | why it is a patch |
| --- | --- | --- |
| `gtk4-pkgconfig-relocate.patch` | a Homebrew gtk4 `.pc` file | rewritten per machine, not per checkout |
| `swift-bundler-android-service.patch` | `Vendor/swift-bundler` | the submodule points at `moreSwift/swift-bundler`, which is upstream and not ours to push to |

The swift-bundler patch now carries two changes: the `<service>` element, and a
strip step that removes `.swift_ast` from the packaged library.

## swift-bundler-android-service.patch

Adds a `<service>` element to the generated `AndroidManifest.xml`, which
`windowLevel(.floating)` needs: on Android a floating window is a
`TYPE_APPLICATION_OVERLAY` owned by a foreground service, and a service that is
not declared in the manifest cannot be started. See
`Sources/AndroidBackend/Kotlin/OverlayService.kt` for why a service and not a
plain overlay.

### The `.swift_ast` strip

The same patch removes `.swift_ast` from the library that goes into the APK.
That section is the serialized Swift AST lldb reads to describe types, and
nothing at runtime touches it. Measured 2026-09-04 with `llvm-size --format=sysv`
on a packaged `libP43.so`: 137.6 MB total, `.text` 56.7 MB, `.swift_ast` 45.0 MB
-- a third of the library and its second largest section. Removing it takes the
library from 130.3 MB to 87.3 and **the APK from 212 MB to 169**, and P43's
gradients measure pixel for pixel what they did before.

It runs after the library is copied into the project rather than at build time,
so the build tree keeps its debugging information and only the shipped copy
loses it. `-gnone` would drop the section at the source and take local
debuggability with it.

### `.swift_ast` 的剝除

同一份 patch 會把 `.swift_ast` 從進入 APK 的那個 library 中移除。該 section 是 lldb 用來描述型別的
序列化 Swift AST，執行期完全不會碰它。2026-09-04 以 `llvm-size --format=sysv` 量測一個已打包的
`libP43.so`：總計 137.6 MB，其中 `.text` 為 56.7 MB、`.swift_ast` 為 45.0 MB——佔該 library 的三分之
一，是其中第二大的 section。移除它使該 library 由 130.3 MB 降到 87.3，而 **APK 由 212 MB 降到
169**，且 P43 的漸層逐像素與先前相同。

它在 library 被複製進專案**之後**執行，而非在建置時，因此建置樹保留其除錯資訊，只有出貨的那一份
失去它。`-gnone` 會從源頭去掉該 section，並連帶取走本機的可除錯性。

Apply and rebuild with the script, which does both and refuses rather than
half-applying:

```zsh
bash Scripts/build-android-bundler.sh
```

`SCUI_KEEP_SWIFT_AST=1` on an APK build leaves the section in, for a build you
intend to attach lldb to. The default strips it.

以腳本套用並重建；它會兩件事一起做，而且寧可拒絕也不會做到一半：

```zsh
bash Scripts/build-android-bundler.sh
```

在建置 APK 時設定 `SCUI_KEEP_SWIFT_AST=1` 會把該 section 留著，供「你打算以 lldb 附加」的建置使用。
預設是剝除。

**That build system flag is not optional and the reason is worth knowing.**
`test_android.zsh` prefers `Vendor/swift-bundler/.build/out/Products/Debug/swift-bundler`
-- the swiftbuild build tree -- over `$repo_root/swift-bundler`. A plain
`swift build -c release` writes somewhere the Android path never looks, so the
old binary keeps running and the manifest keeps coming out unchanged. That cost
three rebuilds and a wrong diagnosis on 2026-09-04: the missing `<service>` was
read as XMLCoder refusing to encode the element, and a string-insertion
workaround was written for a bug that did not exist. Check the generated
`AndroidManifest.xml`, not the source, after any change here.

# patches

本樹需要、但不屬於本樹所有的程式碼變更，以 patch 形式保存，因為擁有它們的那棵樹無法從這裡推送。

## swift-bundler-android-service.patch

在產生的 `AndroidManifest.xml` 中加入一個 `<service>` 元素，那是 `windowLevel(.floating)` 所需要的：
在 Android 上，浮動視窗是一個由 foreground service 持有的 `TYPE_APPLICATION_OVERLAY`，而未在
manifest 中宣告的 service 無法被啟動。為何是 service 而非單純的 overlay，見
`Sources/AndroidBackend/Kotlin/OverlayService.kt`。

**上面那個 build system 旗標不是選配的，而它的理由值得知道。** `test_android.zsh` 會優先採用
`Vendor/swift-bundler/.build/out/Products/Debug/swift-bundler`——也就是 swiftbuild 的建置樹——而非
`$repo_root/swift-bundler`。單純的 `swift build -c release` 會寫到 Android 路徑從不查看的地方，
於是舊的執行檔繼續執行，而 manifest 也繼續保持原樣。2026-09-04 為此付出了三次重建與一個錯誤的
診斷：缺少的 `<service>` 被讀成「XMLCoder 拒絕編碼該元素」，並為一個並不存在的 bug 寫了一段字串
插入的變通做法。在此處做任何改動之後，請檢查產生出來的 `AndroidManifest.xml`，而不是原始碼。
