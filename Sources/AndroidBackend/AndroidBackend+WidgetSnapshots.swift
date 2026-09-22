import AndroidGraphics
import AndroidKit
import SwiftCrossUI
import SwiftJava

/// Reading a widget's pixels back on Android.
///
/// **`View.draw(Canvas)` into a software `Bitmap`, not `getDrawingCache`.** The cache API has been
/// deprecated since API 28 and returns whatever was last composited, which for a view that has not
/// been on screen is nothing. Drawing into a bitmap asks the view to draw NOW, which is what a
/// snapshot means and what makes the result independent of whether the window was visible.
///
/// **`ARGB_8888` is RGBA in memory, and that is not a typo in the name.** Android stores that
/// config as four bytes in R, G, B, A order; the constant is historical. `copyPixelsToBuffer`
/// therefore hands back exactly the layout ``WidgetSnapshot`` wants, with no shuffling.
/// `AndroidBackend+Images.swift` relies on the same fact in the opposite direction -- it wraps
/// this package's `rgbaData` and calls `copyPixelsFromBuffer` -- so if that assumption were wrong,
/// every image in every test app would already be drawn with its channels swapped.
///
/// 在 Android 上把一個 widget 的像素讀回來。
///
/// **用 `View.draw(Canvas)` 畫進一張軟體 `Bitmap`,不是 `getDrawingCache`。** 那個快取 API 自 API 28
/// 起已被棄用,且回傳的是「上一次被合成出來的東西」;對一個從未出現在螢幕上的 view 而言,那是空的。
/// 畫進一張 bitmap 是要求該 view **現在**畫,那才是快照的意思,也才讓結果與「視窗當時是否可見」無關。
///
/// **`ARGB_8888` 在記憶體中是 RGBA,而那不是名字打錯。** Android 把該 config 以 R、G、B、A 四個位元組
/// 的順序儲存;那個常數名稱是歷史遺留。因此 `copyPixelsToBuffer` 交回來的,正好就是 ``WidgetSnapshot``
/// 要的排列,不需要任何重排。`AndroidBackend+Images.swift` 在反方向依賴同一個事實——它包住本套件的
/// `rgbaData` 並呼叫 `copyPixelsFromBuffer`——因此若這個假設是錯的,每一支測試 app 裡的每一張圖早就
/// 通道錯位了。
extension AndroidBackend: BackendFeatures.WidgetSnapshots {
    public func snapshotWidget(_ widget: Widget) -> WidgetSnapshot? {
        // **The mesh view first, because the generic path returns a blank box for it rather than
        // failing.** A `GLSurfaceView` is a `SurfaceView`: its pixels live on a surface the window
        // compositor owns and the view itself is a hole punched in the layout, so
        // `View.draw(Canvas)` faithfully draws the hole. AppKitBackend checks for
        // `Mesh3DMetalView` before reaching for `cacheDisplay` for exactly the same reason, and
        // its comment says the same thing about Metal content and `drawRect`.
        // **先處理 mesh view,因為通用路徑對它會回傳一個空盒子、而不是失敗。** `GLSurfaceView` 是一個
        // `SurfaceView`:它的像素住在一個由視窗合成器持有的 surface 上,而那個 view 本身是版面上挖的一個
        // 洞;因此 `View.draw(Canvas)` 會忠實地把那個洞畫出來。AppKitBackend 在動用 `cacheDisplay`
        // 之前先檢查 `Mesh3DMetalView`,理由完全相同;它的註解對 Metal 內容與 `drawRect` 說的是同一件事。
        if let mesh = widget.as(Mesh3DSurfaceView.self), mesh.getDrawableWidth() > 0 {
            let pixels = mesh.snapshotPixels()
            let width = Int(mesh.getDrawableWidth())
            let height = Int(mesh.getDrawableHeight())
            guard pixels.count >= width * height * 4 else { return nil }
            return WidgetSnapshot(
                width: width,
                height: height,
                rgbaData: pixels.prefix(width * height * 4).map { UInt8(bitPattern: $0) }
            )
        }

        let width = widget.getWidth()
        let height = widget.getHeight()
        // A view that has not been laid out has no pixels, and a zero-sized bitmap is a crash
        // rather than an empty image -- `createBitmap` throws IllegalArgumentException below 1.
        // 一個還沒排版過的 view 沒有像素,而一張尺寸為零的 bitmap 會是一次崩潰、不是一張空圖
        // ——`createBitmap` 在小於 1 時會丟 IllegalArgumentException。
        guard width > 0, height > 0 else { return nil }

        let bitmap = try! JavaClass<AndroidKit.Bitmap>().createBitmap(
            width,
            height,
            try! JavaClass<AndroidKit.Bitmap.Config>().ARGB_8888,
            true
        )!
        widget.draw(AndroidGraphics.Canvas(bitmap))

        let byteCount = Int(width) * Int(height) * 4
        let buffer = try! JavaClass<AndroidKit.ByteBuffer>().allocate(Int32(byteCount))!
        bitmap.copyPixelsToBuffer(buffer.as(JavaNioBuffer.self)!)

        // `array()` rather than reading the buffer a byte at a time: one JNI call for the whole
        // image instead of 326,400 for a 340x240 view. `allocate` (not `allocateDirect`) is what
        // makes that array exist.
        // 用 `array()` 而不是逐位元組讀取:整張圖一次 JNI 呼叫,而不是 340x240 的 view 要 326,400 次。
        // `array()` 之所以存在,是因為用的是 `allocate` 而不是 `allocateDirect`。
        let signed = buffer.array()
        guard signed.count >= byteCount else { return nil }
        return WidgetSnapshot(
            width: Int(width),
            height: Int(height),
            rgbaData: signed.prefix(byteCount).map { UInt8(bitPattern: $0) }
        )
    }
}

extension AndroidKit.Bitmap {
    /// Not in the generated bindings, and needed here. Declared the way
    /// `AndroidBackend+Fonts.swift` declares `TextView.setGravity` for the same reason.
    /// 不在產生出來的綁定裡,而此處需要它。宣告方式與 `AndroidBackend+Fonts.swift` 為
    /// `TextView.setGravity` 所做的相同,理由也相同。
    @JavaMethod
    func copyPixelsToBuffer(_ arg0: JavaNioBuffer?)
}
