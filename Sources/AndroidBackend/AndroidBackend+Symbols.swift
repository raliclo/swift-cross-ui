import AndroidKit
@_spi(Backends) import SwiftCrossUI
import SwiftJava

extension AndroidKit.ImageView {
    @JavaMethod
    func setImageResource(_ resId: Int32)

    @JavaMethod
    func setColorFilter(_ color: Int32)
}

// swiftlint:disable force_try

/// `android.R.drawable` icons, resolved by name and checked before they are drawn.
///
/// **The check is the feature, and on Android it is unavoidable rather than
/// merely wise.** The symbol table's `androidDrawable` column holds names like
/// `ic_input_add`, and a name has to become a resource identifier before
/// anything can draw it. `Resources.getIdentifier` is what does that, and it
/// answers `0` for a name the platform does not have -- an identifier that
/// `setImageResource` accepts without complaint and that draws nothing. The
/// framework's own API hands back the silent failure; taking `0` as a real
/// answer is what turns it into a visible one.
///
/// The names are `android.R` rather than the application's own, so what varies
/// is the API level rather than the app's resources. A drawable added in a
/// recent Android is simply absent on an older one, and the fallback covers it
/// without the table having to carry a minimum SDK per row.
///
/// `android.R.drawable` 圖示：依名稱解析，並在繪製之前先行檢查。
///
/// **那次檢查本身就是這項功能；而在 Android 上，它是無可迴避的，不只是明智而已。** 符號表的
/// `androidDrawable` 欄位存放的是 `ic_input_add` 這類名稱，而任何東西要畫它之前，該名稱都必須先變成
/// 一個資源識別碼。負責這件事的是 `Resources.getIdentifier`，而對於平台所沒有的名稱，它的回答是
/// `0`——一個 `setImageResource` 會照單全收、且什麼都不會畫的識別碼。框架自身的 API 直接把那個靜默
/// 失敗交到手上；把 `0` 當成一個真實的答案來看待，才使它成為看得見的失敗。
///
/// 這些名稱屬於 `android.R` 而非應用程式自身，因此變動的是 API level，而不是 app 的資源。一個在較新
/// Android 中才加入的 drawable，在較舊的系統上就是不存在，而退路涵蓋了這種情況，表格也因此不必為
/// 每一列各自記載一個最低 SDK 版本。
extension AndroidBackend {
    public func createSymbolView() -> Widget {
        // A container, for the same reason GtkBackend needs one: ImageView
        // cannot draw text and TextView cannot draw a drawable resource, and
        // which is needed is unknown until a symbol arrives.
        // 使用容器，理由與 GtkBackend 需要容器相同：ImageView 畫不了文字，TextView 也畫不了
        // drawable 資源，而需要哪一個，在符號抵達之前都無從得知。
        createContainer()
    }

    public func updateSymbolView(
        _ symbolView: Widget,
        symbol: SystemSymbol,
        environment: EnvironmentValues
    ) {
        removeAllChildren(of: symbolView)

        let child: Widget
        if let resourceId = Self.drawableId(for: symbol, in: environment) {
            let imageView = AndroidKit.ImageView(Self.activity, environment: Self.env)
            imageView.setImageResource(resourceId)
            // The stock android.R drawables are grey artwork rather than
            // tintable masks, so this is a colour filter over the whole
            // drawable. That matches what the other backends do with the
            // foreground colour and keeps a symbol legible in dark mode, where
            // the untinted artwork is close to invisible.
            // 內建的 android.R drawable 是灰階圖稿，而非可染色的遮罩，因此此處是對整個 drawable 套上
            // 一層顏色濾鏡。這與其他 backend 對前景色的處理一致，也讓符號在深色模式下保持可讀——在
            // 那裡，未經上色的圖稿幾乎看不見。
            imageView.setColorFilter(
                environment.suggestedForegroundColor.resolve(in: environment).asColorInt()
            )
            child = imageView.as(Widget.self)!
        } else {
            let textView = createTextView()
            updateTextView(textView, content: symbol.textFallback, environment: environment)
            child = textView
        }

        // The child needs its own size. `Image.commit` sizes the widget that
        // `createSymbolView()` returned, and here that is the container -- so
        // without this the child sits at its default extent, which on Android is
        // zero and draws nothing at all. The Apple backends never hit this
        // because they return the drawing view itself and the size lands on it.
        //
        // After `insert`, never before. `setSize` begins with
        // `guard let layoutParams = widget.getLayoutParams() else { return }`,
        // and a view that has not been added to a parent has none -- so the
        // call returns having done nothing, silently, and the symbol is laid
        // out with space reserved for it and nothing drawn in that space.
        // That is what the first attempt at this fix did, and the screenshot
        // afterwards was identical to the one before it.
        //
        // 必須在 `insert` 之後,絕不能在之前。`setSize` 的第一行是
        // `guard let layoutParams = widget.getLayoutParams() else { return }`,
        // 而一個尚未被加入父層的 view 沒有 layout params——於是該呼叫什麼都沒做就返回了,
        // 而且是靜默的,結果就是符號的位置被保留了空間、空間裡卻什麼都沒畫。這正是本修正第一次
        // 嘗試時所做的事,而其後的截圖與修正前那張一模一樣。
        //
        // Computed rather than remembered: the size depends only on the symbol
        // and the environment, both of which are arguments here, so there is no
        // state to keep in step.
        //
        // 子 widget 需要有自己的尺寸。`Image.commit` 設定的是 `createSymbolView()` 所回傳的那個
        // widget,而在此處那是容器——因此少了這一步,子 widget 就會停留在其預設範圍,而那在 Android
        // 上是零,於是什麼都畫不出來。Apple 那兩個 backend 不會遇到這件事,因為它們回傳的就是負責繪製
        // 的那個 view,尺寸直接落在它身上。
        //
        // 這裡是「算出來」而非「記下來」:該尺寸只取決於符號與 environment,而兩者都是此處的參數,
        // 因此沒有任何需要保持同步的狀態。
        insert(child, into: symbolView, at: 0)
        setPosition(ofChildAt: 0, in: symbolView, to: .zero)
        setSize(
            of: child,
            to: size(ofSymbol: symbol, whenDisplayedIn: symbolView, environment: environment)
        )
    }

    public func size(
        ofSymbol symbol: SystemSymbol,
        whenDisplayedIn widget: Widget,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        guard Self.drawableId(for: symbol, in: environment) != nil else {
            return size(
                of: symbol.textFallback,
                whenDisplayedIn: widget,
                proposedWidth: nil,
                proposedHeight: nil,
                environment: environment
            )
        }
        // Square, at the font's point size, as GtkBackend does -- so a symbol is
        // the same height as the text beside it. Logical points, not pixels: the
        // layout system scales by windowScaleFactor on the way to the platform.
        // 正方形，尺寸為字型的點級，與 GtkBackend 相同——如此符號便與其旁邊的文字等高。此處是邏輯點
        // 而非像素：版面系統會在送往平台的途中依 windowScaleFactor 縮放。
        let side = Int(environment.resolvedFont.pointSize.rounded(.awayFromZero))
        return SIMD2(side, side)
    }

    /// The resource identifier this device will actually draw, or `nil`.
    ///
    /// `getIdentifier` returns `0` for an unknown name, and `0` is exactly the
    /// value `setImageResource` accepts while drawing nothing -- so it is mapped
    /// to `nil` here, at the one place that knows it means "absent", rather than
    /// being carried around as a number that looks usable.
    ///
    /// 本裝置實際會畫出來的資源識別碼；若無則為 `nil`。
    ///
    /// `getIdentifier` 對未知名稱回傳 `0`，而 `0` 正是 `setImageResource` 會接受、卻什麼都不畫的那個
    /// 值——因此在此處、在唯一知道它意謂「不存在」的地方，把它對應為 `nil`，而不是讓它以一個看起來
    /// 可用的數字被四處傳遞。
    static func drawableId(
        for symbol: SystemSymbol,
        in environment: EnvironmentValues
    ) -> Int32? {
        guard !symbol.androidDrawable.isEmpty else { return nil }
        let identifier = environment.androidActivity.getResources()
            .getIdentifier(symbol.androidDrawable, "drawable", "android")
        return identifier == 0 ? nil : identifier
    }
}
