@_spi(Backends) import SwiftCrossUI
import AndroidKit
import SwiftJava

/// Methods `android.widget.PopupWindow` has and AndroidKit's generated wrapper
/// does not.
///
/// Declared here rather than waited for upstream, which is the same workaround
/// `AndroidBackend+List.swift` uses for `ListView.setSelector` and
/// `AndroidBackend+Menu.swift` uses for `PopupMenu.getMenu`. `@JavaMethod` on an
/// extension resolves the real Java method by name and signature, so these are
/// the platform methods, not reimplementations of them.
///
/// `android.widget.PopupWindow` 具備、但 AndroidKit 生成的 wrapper 沒有的方法。
///
/// 在此宣告而非等待上游補齊，這與 `AndroidBackend+List.swift` 對 `ListView.setSelector`、
/// `AndroidBackend+Menu.swift` 對 `PopupMenu.getMenu` 所採用的變通做法相同。extension 上的
/// `@JavaMethod` 會依名稱與簽章解析出真正的 Java 方法，因此這些就是平台方法本身，而非它們的重新實作。
extension AndroidKit.PopupWindow {
    @JavaMethod
    public func setContentView(_ contentView: AndroidKit.View?)

    @JavaMethod
    public func showAsDropDown(_ anchor: AndroidKit.View?, _ xoff: Int32, _ yoff: Int32)

    @JavaMethod
    public func setBackgroundDrawable(_ background: AndroidKit.Drawable?)
}

/// The Kotlin shim that turns `PopupWindow.OnDismissListener` into a closure.
/// See `Kotlin/CustomPopupDismissListener.kt`.
/// 把 `PopupWindow.OnDismissListener` 變成 closure 的 Kotlin 墊片。
/// 見 `Kotlin/CustomPopupDismissListener.kt`。
@JavaClass(
    "dev.swiftcrossui.androidbackend.CustomPopupDismissListener",
    implements: AndroidKit.PopupWindow.OnDismissListener.self
)
class CustomPopupDismissListener: JavaObject {
    @JavaMethod
    convenience init(
        _ action: SwiftAction!,
        environment: JNIEnvironment? = nil
    )
}

/// `.popover` for Android, built on `PopupWindow`.
///
/// `PopupWindow` is the primitive Android's own drop-downs, autocomplete lists
/// and `PopupMenu` are built from -- `PopupMenu`, which this backend already
/// uses for ``BackendFeatures/AttachedMenus``, is a `MenuPopupHelper` around
/// one. The difference is that `PopupMenu` can only hold menu items, whereas
/// `setContentView` takes any `View`, which is what a `@ViewBuilder` produces.
///
/// **Not a `BottomSheetDialogFragment`.** That is what `AndroidBackend+Sheets.swift`
/// uses, and it is modal and bottom-anchored; a popover is neither.
///
/// 為 Android 實作的 `.popover`，建構於 `PopupWindow` 之上。
///
/// `PopupWindow` 正是 Android 自身的下拉選單、自動完成清單與 `PopupMenu` 所建構於其上的基本元件
/// ——本 backend 已用於 ``BackendFeatures/AttachedMenus`` 的 `PopupMenu`，其實就是包住一個
/// `PopupWindow` 的 `MenuPopupHelper`。差別在於 `PopupMenu` 只能裝選單項目，而 `setContentView`
/// 接受任何 `View`，那正是 `@ViewBuilder` 所產出的東西。
///
/// **它不是 `BottomSheetDialogFragment`。** 那是 `AndroidBackend+Sheets.swift` 所使用的，它是模態的、
/// 且錨定在底部；popover 兩者皆非。
extension AndroidBackend: BackendFeatures.Popovers {
    @MainActor
    public final class Popover {
        let popup: AndroidKit.PopupWindow
        /// Held so its Swift-side signal handlers outlive the call that made
        /// it, exactly as `GtkBackend.Popover` holds its content.
        /// 持有它，好讓其 Swift 端的處理器活得比建立它的那次呼叫更久，與 `GtkBackend.Popover`
        /// 持有其內容的做法完全相同。
        let content: AndroidKit.View
        var onDismiss: (() -> Void)?
        var isProgrammaticDismissal = false
        var attachmentEdge: Edge = .bottom

        init(content: AndroidKit.View) {
            self.content = content
            popup = AndroidKit.PopupWindow(environment: AndroidBackend.env)
            popup.setContentView(content)

            // Both are needed for light dismiss, and neither is enough alone.
            // `outsideTouchable` lets a touch outside the popup reach the popup
            // at all; `focusable` is what makes that touch close it and makes
            // the back button close it too. A popup with only the first stays
            // open until something else dismisses it -- which, for a popover
            // whose binding lives outside it, is nothing.
            //
            // 兩者對「點擊外部即關閉」缺一不可。`outsideTouchable` 讓 popup 之外的觸控能夠被 popup
            // 收到；`focusable` 才是讓那次觸控真的關閉它、也讓返回鍵能關閉它的關鍵。只設定前者的
            // popup 會一直開著，直到有別的東西關閉它——而對於 binding 位於自身之外的 popover 來說，
            // 那個「別的東西」並不存在。
            popup.setOutsideTouchable(true)
            popup.setFocusable(true)

            popup.setOnDismissListener(
                CustomPopupDismissListener(
                    SwiftAction(environment: AndroidBackend.env) { [weak self] in
                        guard let self else { return }
                        let wasProgrammatic = self.isProgrammaticDismissal
                        self.isProgrammaticDismissal = false
                        guard !wasProgrammatic else { return }
                        self.onDismiss?()
                    },
                    environment: AndroidBackend.env
                )
                .as(AndroidKit.PopupWindow.OnDismissListener.self)
            )
        }
    }

    public func createPopover(content: Widget) -> Popover {
        Popover(content: content)
    }

    public func updatePopover(
        _ popover: Popover,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        attachmentEdge: Edge,
        backgroundColor: SwiftCrossUI.Color.Resolved?,
        onDismiss: @escaping () -> Void
    ) {
        popover.onDismiss = onDismiss
        popover.attachmentEdge = attachmentEdge

        // Points to pixels. `PopupWindow` takes raw pixels, and SwiftCrossUI
        // sizes are points, so the density conversion is not optional here --
        // it is the same one `AndroidBackend.layoutLength` does for every other
        // widget, and skipping it produces a popup that is correct on a density
        // 1.0 emulator and roughly a third of the intended size on a real phone.
        //
        // 點轉像素。`PopupWindow` 接受的是原始像素，而 SwiftCrossUI 的尺寸是點，因此此處的 density
        // 換算不是可有可無的——它與 `AndroidBackend.layoutLength` 為其他每一個 widget 所做的換算相同，
        // 略過它會得到「在 density 1.0 的模擬器上正確、在真實手機上約只有預期三分之一大小」的 popup。
        let density = popover.content.getResources().getDisplayMetrics().density
        popover.popup.setWidth(Int32(Float(size.x) * density))
        popover.popup.setHeight(Int32(Float(size.y) * density))

        // A background is mandatory, not decorative. `PopupWindow` only draws a
        // shadow and only dispatches outside touches when it has a background
        // drawable; with a null background, `setOutsideTouchable(true)` above
        // silently does nothing. So a caller-supplied colour is used when there
        // is one, and an opaque platform-ish default when there is not -- never
        // null.
        //
        // 背景是必要的，不是裝飾。`PopupWindow` 只有在具備 background drawable 時才會繪製陰影、
        // 也才會派送外部觸控；若背景為 null，上方的 `setOutsideTouchable(true)` 會靜默失效。因此：
        // 呼叫端有提供顏色時使用該顏色，沒有時使用一個不透明的近似平台預設值——絕不使用 null。
        let backgroundColorInt =
            if let backgroundColor {
                backgroundColor.asColorInt()
            } else {
                switch environment.colorScheme {
                    case .dark:
                        // Matches the sheet default in
                        // `AndroidBackend+Sheets.swift`, colour-picked from an
                        // emulator, so a popover and a sheet in the same app do
                        // not disagree about what "dark surface" means.
                        // 與 `AndroidBackend+Sheets.swift` 中的 sheet 預設值一致，取自模擬器的取色，
                        // 好讓同一個 app 中的 popover 與 sheet 對「深色表面」的認知不致互相牴觸。
                        Int32(bitPattern: 0xff25_232b)
                    case .light:
                        Int32(bitPattern: 0xffff_ffff)
                }
            }
        popover.popup.setBackgroundDrawable(
            AndroidKit.ColorDrawable(backgroundColorInt, environment: Self.env)
        )
    }

    public func showPopover(_ popover: Popover, relativeTo widget: Widget, window: Window) {
        // `showAsDropDown` always measures from the anchor's bottom-left corner,
        // so every edge other than `.bottom` is expressed as an offset from
        // there. Android re-positions the popup itself when the result would
        // leave the screen, which is why these are offsets rather than absolute
        // coordinates.
        //
        // `showAsDropDown` 一律從錨點的左下角起算，因此 `.bottom` 以外的每一個邊，都是以相對該處的
        // 位移來表達。當結果會超出螢幕時，Android 會自行重新定位該 popup，這正是此處使用位移而非
        // 絕對座標的原因。
        let anchorWidth = widget.getWidth()
        let anchorHeight = widget.getHeight()
        let popupWidth = popover.popup.getWidth()
        let popupHeight = popover.popup.getHeight()

        let offset: (x: Int32, y: Int32) = switch popover.attachmentEdge {
            case .bottom: (0, 0)
            case .top: (0, -(anchorHeight + popupHeight))
            case .trailing: (anchorWidth, -anchorHeight)
            case .leading: (-popupWidth, -anchorHeight)
        }

        popover.popup.showAsDropDown(widget, offset.x, offset.y)
    }

    public func dismissPopover(_ popover: Popover) {
        popover.isProgrammaticDismissal = true
        popover.popup.dismiss()
    }
}
