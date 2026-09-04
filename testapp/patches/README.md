# patches

Changes this tree needs in code it does not own, kept as patches because the
tree that owns them cannot be pushed to from here.

| patch | applies to | why it is a patch |
| --- | --- | --- |
| `gtk4-pkgconfig-relocate.patch` | a Homebrew gtk4 `.pc` file | rewritten per machine, not per checkout |
| `swift-bundler-android-service.patch` | `Vendor/swift-bundler` | the submodule points at `moreSwift/swift-bundler`, which is upstream and not ours to push to |

## swift-bundler-android-service.patch

Adds a `<service>` element to the generated `AndroidManifest.xml`, which
`windowLevel(.floating)` needs: on Android a floating window is a
`TYPE_APPLICATION_OVERLAY` owned by a foreground service, and a service that is
not declared in the manifest cannot be started. See
`Sources/AndroidBackend/Kotlin/OverlayService.kt` for why a service and not a
plain overlay.

Apply and rebuild:

```zsh
cd Vendor/swift-bundler
git apply ../../testapp/patches/swift-bundler-android-service.patch
swift build --build-system swiftbuild --product swift-bundler
```

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
