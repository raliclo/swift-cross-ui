# The Kotlin half of AndroidBackend

Checked 2026-10-24.

## What

`Sources/AndroidBackend/Kotlin/` (package `dev.swiftcrossui.androidbackend`)
holds the views and listeners Swift cannot subclass through JNI: custom
containers (`CustomContainer`, `ScrollContainer`, `RootScrollHost`,
`ShortcutHostLayout`, `KeyEventContainer`, geometric and visual effect
containers), controls (`CustomButton`, `CustomSlider`, `CustomEditText`,
pickers), `PathView`, `Mesh3DSurfaceView`, `FrontWindows`,
`ScuiWindowActivity`, `OverlayService`, `AndroidBackendHelpers` and the
listener classes that call back into Swift (`SwiftAction`, `SwiftObject`).
Swift reaches them through AndroidKit/swift-java (swift-java-fork.md).

## How it gets into an APK

package_android.zsh mirrors the `.kt` files into the shared Gradle project's
`src/main/kotlin` with `rsync --delete` (a file deleted from Sources is deleted
there too), and Gradle compiles them once for all apps. A Kotlin change needs
no Swift rebuild but does need a repackage: `test_android.zsh Pn` without
`--no-build`. The launcher activity is `gradleProject/src/main/java/.../MainActivity.java`;
`libshim.so` connects its `setup()` to `AndroidBackend_entrypoint`.

## Rules

- **ktfmt breaks Chinese comments.** `Scripts/format.zsh` runs
  `Tools/ktfmt.jar --kotlinlang-style` on the whole directory. In f7674d3a it
  reflowed six Chinese comment blocks as if they were English (spaces in the
  middle of sentences, breaks after one character); 87790bd2 restored them.
  Running it again reflows them again: review the diff of any ktfmt run.
- **Key handling depends on focus**: a container that needs keys takes focus
  with `FOCUS_AFTER_DESCENDANTS` (KeyEventContainer, ShortcutHostLayout); see
  keys-and-shortcuts.md.
- **Units**: Kotlin touch code sees pixels; the backend lays out in points
  times density. `ContinuousGestureContainer` once reported drags in pixels (an
  80 pt drag read 210 at 2.625, 96c59726); convert before handing coordinates
  to Swift. Ratios and angles (magnify, rotate) need no conversion.
- **Five-backend rule**: a fix in a shared Kotlin helper is re-captured on
  Android and on iOS (ui-alignment-with-ios.md).

---

# AndroidBackend 的 Kotlin 那一半

2026-10-24 查過。

## 內容

`Sources/AndroidBackend/Kotlin/`(package `dev.swiftcrossui.androidbackend`)放的是 Swift 無法經 JNI 子類別化的 view 與
listener:自訂容器(`CustomContainer`、`ScrollContainer`、`RootScrollHost`、`ShortcutHostLayout`、`KeyEventContainer`、幾何與
視覺效果容器)、控制項(`CustomButton`、`CustomSlider`、`CustomEditText`、各種 picker)、`PathView`、`Mesh3DSurfaceView`、
`FrontWindows`、`ScuiWindowActivity`、`OverlayService`、`AndroidBackendHelpers`,以及回呼 Swift 的 listener 類別(`SwiftAction`、
`SwiftObject`)。Swift 經由 AndroidKit/swift-java 使用它們(swift-java-fork.md)。

## 如何進入 APK

package_android.zsh 以 `rsync --delete` 把 `.kt` 檔鏡像到共用 Gradle 專案的 `src/main/kotlin`(從 Sources 刪掉的檔案在那裡也會
刪掉),Gradle 為所有 app 只編一次。改 Kotlin 不需要重建 Swift,但需要重新打包:執行不加 `--no-build` 的 `test_android.zsh Pn`。
啟動用的 activity 是 `gradleProject/src/main/java/.../MainActivity.java`;`libshim.so` 把它的 `setup()` 接到
`AndroidBackend_entrypoint`。

## 規則

- **ktfmt 會弄壞中文註解。** `Scripts/format.zsh` 對整個目錄執行 `Tools/ktfmt.jar --kotlinlang-style`。f7674d3a 時它把六段中文
  註解當成英文重排(句子中間插入空白、在單一字元後斷行);87790bd2 還原了它們。再跑一次又會重排：任何 ktfmt 執行都要檢查 diff。
- **按鍵處理取決於焦點**:需要按鍵的容器以 `FOCUS_AFTER_DESCENDANTS` 取得焦點(KeyEventContainer、ShortcutHostLayout);見
  keys-and-shortcuts.md。
- **單位**:Kotlin 的觸控程式碼看到的是 pixel;backend 以 point 乘以密度排版。`ContinuousGestureContainer` 曾以 pixel 回報拖曳
  (2.625 下 80 pt 的拖曳讀成 210,96c59726);把座標交給 Swift 之前先換算。比例與角度(縮放、旋轉)不需換算。
- **五個 backend 的規則**:改到共用的 Kotlin helper 時,Android 與 iOS 都要重新擷取(ui-alignment-with-ios.md)。
