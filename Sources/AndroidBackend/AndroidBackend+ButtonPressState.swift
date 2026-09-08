@_spi(Backends) import SwiftCrossUI
import AndroidKit
import SwiftJava

/// `BackendFeatures.ButtonPressState` on Android.
///
/// **This extension names the protocol, and the other four do not.** The
/// conformance for GtkBackend, WinUIBackend, UIKitBackend and AppKitBackend is
/// declared on their class declarations (or, for AppKit, through
/// `FullAppBackend.swift:111`), so naming it again in their files is a redundant
/// conformance. `AndroidBackend` is not a `FullAppBackend` and lists its
/// features one extension at a time -- `AndroidBackend+HoverGestures.swift:63`
/// is the same shape -- so this file is the only place the conformance can be
/// stated. Dropping it from here does not fail the build: it fails at first
/// render, because the modifier reaches the backend through a runtime cast.
///
/// **What was reused.** Nothing; `AndroidBackend` had no press flag, exactly as
/// GtkBackend had none. Android itself does keep one -- `View.isPressed()`
/// (`AndroidKit/Sources/AndroidView/View.swift:568`) -- and `View.onTouchEvent`
/// maintains it including the abandon case, but Android publishes no callback
/// for it. So the touch stream is read directly, and `isPressed()` is used only
/// to seed a freshly installed listener.
///
/// **Why a Kotlin `View.OnTouchListener` and not something Swift-only.**
/// Implementing a Java interface from Swift needs a real JVM class; this tree
/// does that with a Kotlin file per listener, and `SecondaryClickListener.kt`
/// already implements this exact interface for `.onTapGesture(.secondary)`. The
/// mechanics of the press live in `ButtonPressListener.kt`, which records why it
/// never consumes an event and how it decides the finger has left the button.
///
/// **The one collision, stated rather than hidden.** A `View` has room for a
/// single `OnTouchListener`, and `updateTapGestureTarget` sets one for a
/// secondary tap on the widget it is given, unwrapped
/// (`AndroidBackend+TapGestures.swift:6,27`). A button carrying
/// `.onTapGesture(.secondary)` directly is therefore the one case where this
/// and that overwrite each other, and which of the two survives depends on
/// which modifier commits last. Every other Android widget arrangement is
/// unaffected, and no other feature in this backend uses `setOnTouchListener`.
///
/// Android 上的 `BackendFeatures.ButtonPressState`。
///
/// **本 extension 會寫出 protocol 名稱，其餘四個則不會。** GtkBackend、WinUIBackend、UIKitBackend
/// 與 AppKitBackend 的 conformance 已宣告在它們的類別宣告上（AppKit 則是透過
/// `FullAppBackend.swift:111`），因此在那些檔案中再寫一次就是重複 conformance。而 `AndroidBackend`
/// 並非 `FullAppBackend`，它是一個 extension 一項地列出自己的 feature——
/// `AndroidBackend+HoverGestures.swift:63` 就是同一種形狀——所以本檔是唯一能陳述該 conformance 的
/// 地方。從此處拿掉它並不會讓建置失敗：它會在第一次繪製時失敗，因為該 modifier 是透過執行期轉型抵達
/// backend 的。
///
/// **沿用了什麼。** 什麼也沒有；`AndroidBackend` 沒有任何按下旗標，與 GtkBackend 一樣是零。Android
/// 本身確實保有一個——`View.isPressed()`（`AndroidKit/Sources/AndroidView/View.swift:568`）——而
/// `View.onTouchEvent` 會維護它，連放棄的情況也包含在內，但 Android 並未為它公開任何 callback。因此
/// 此處直接讀取觸控串流，而 `isPressed()` 僅用於為一個剛安裝的 listener 設定初始值。
///
/// **為何採用 Kotlin 的 `View.OnTouchListener` 而非純 Swift 的做法。** 從 Swift 實作一個 Java
/// interface 需要一個真正的 JVM 類別；本樹的做法是每個 listener 一個 Kotlin 檔案，而
/// `SecondaryClickListener.kt` 早已為 `.onTapGesture(.secondary)` 實作了同一個 interface。按壓的
/// 具體機制位於 `ButtonPressListener.kt`，該檔記錄了它為何從不消耗事件，以及它如何判定手指已離開按鈕。
///
/// **唯一的衝突——如實陳述而非隱藏。** 一個 `View` 只有一個 `OnTouchListener` 的位置，而
/// `updateTapGestureTarget` 會在它拿到的（未經包裝的）widget 上為 secondary tap 設定一個
/// （`AndroidBackend+TapGestures.swift:6,27`）。因此，一顆直接帶有 `.onTapGesture(.secondary)` 的
/// 按鈕，就是此二者會互相覆蓋的那唯一情況，而最終存活的是哪一個，取決於哪個 modifier 最後 commit。
/// Android 上其他任何 widget 組合都不受影響，且本 backend 沒有其他功能使用 `setOnTouchListener`。
extension AndroidBackend: BackendFeatures.ButtonPressState {
    public func updateButtonPressHandler(
        _ button: Widget,
        handler: @escaping (Bool) -> Void
    ) {
        // A fresh listener per call, rather than a table that finds and mutates
        // the previous one. `Button.commit` reinstalls on every update
        // (`Sources/SwiftCrossUI/Views/Button.swift:349`), so a table would be
        // the cheaper shape -- but keying it would mean keying on a Swift
        // wrapper whose identity is not the JVM object's, and `setOnTouchListener`
        // already replaces rather than appends, so nothing accumulates.
        // `AndroidBackend+HoverGestures.swift:89` builds new `SwiftAction`s on
        // every update for the same reason.
        //
        // What that shape costs is the state the old listener held, and
        // `isPressed()` is what pays for it: a listener installed midway through
        // a press starts out knowing the finger is down, so a subsequent drag
        // off the button still reports `false`.
        //
        // 每次呼叫都建立一個全新的 listener，而不是用一張表去找出並修改前一個。`Button.commit` 每次
        // 更新都會重新安裝（`Sources/SwiftCrossUI/Views/Button.swift:349`），因此用表會是比較省的
        // 形狀——但為它建鍵，就等於以一個「識別並非 JVM 物件識別」的 Swift wrapper 為鍵；而
        // `setOnTouchListener` 本來就是替換而非附加，所以不會累積任何東西。
        // `AndroidBackend+HoverGestures.swift:89` 出於同樣的理由，每次更新都建立新的 `SwiftAction`。
        //
        // 這個形狀的代價是舊 listener 所持有的狀態，而 `isPressed()` 正是用來支付它的：一個在按壓
        // 進行到一半時才安裝的 listener，一開始就知道手指是按下的，因此隨後把它拖離按鈕仍會回報
        // `false`。
        let listener = ButtonPressListener(
            SwiftAction(environment: Self.env) { handler(true) },
            SwiftAction(environment: Self.env) { handler(false) },
            button.isPressed(),
            environment: Self.env
        )

        button.setOnTouchListener(
            listener.as(AndroidKit.View.OnTouchListener.self)!
        )
    }
}

/// The Swift face of `ButtonPressListener.kt`.
///
/// Shaped after `SecondaryClickListener` (`SecondaryClickListener.swift:4`),
/// which binds the other `View.OnTouchListener` in this backend. Two
/// `SwiftAction`s rather than one taking a `Bool`, because `SwiftAction` wraps a
/// `() -> Void` and nothing else (`SwiftAction.swift:5`); `HoverContainer` splits
/// its `Bool` the same way, into `setEnterAction`/`setExitAction`.
///
/// `ButtonPressListener.kt` 的 Swift 面。
///
/// 形狀比照 `SecondaryClickListener`（`SecondaryClickListener.swift:4`）——本 backend 中另一個
/// `View.OnTouchListener` 的繫結。使用兩個 `SwiftAction` 而非一個帶 `Bool` 的，因為 `SwiftAction`
/// 包裝的就只有 `() -> Void`（`SwiftAction.swift:5`）；`HoverContainer` 也是以同樣方式把它的 `Bool`
/// 拆成 `setEnterAction`/`setExitAction`。
@JavaClass(
    "dev.swiftcrossui.androidbackend.ButtonPressListener",
    implements: AndroidKit.View.OnTouchListener.self
)
class ButtonPressListener: JavaObject {
    @JavaMethod
    convenience init(
        _ pressedAction: SwiftAction?,
        _ releasedAction: SwiftAction?,
        _ initiallyDown: Bool,
        environment: JNIEnvironment? = nil
    )
}
